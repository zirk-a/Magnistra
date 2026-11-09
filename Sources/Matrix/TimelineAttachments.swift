// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: attaching and uploading images and videos.
import UIKit
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import Security
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration

extension RoomTimelineVC {


    @objc func attachTapped() {
        messageField.resignFirstResponder()
        let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
#if LEGACY_TARGET
        let sheet = UIActionSheet()
        sheet.delegate = self
        sheet.title = "Attach"
        if hasCamera { sheet.addButton(withTitle: "Take Photo") }
        sheet.addButton(withTitle: "Choose from Library")
        sheet.addButton(withTitle: "Stickers")
        sheet.addButton(withTitle: "Voice Message")
        let cancelIndex = sheet.addButton(withTitle: "Cancel")
        sheet.cancelButtonIndex = cancelIndex
        sheet.show(in: view)
#else
        let sheet = UIAlertController(title: "Attach", message: nil, preferredStyle: .actionSheet)
        if hasCamera {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentPicker(source: .camera)
            })
        }
        sheet.addAction(UIAlertAction(title: "Choose from Library", style: .default) { [weak self] _ in
            self?.presentPicker(source: .photoLibrary)
        })
        sheet.addAction(UIAlertAction(title: "Voice Message", style: .default) { [weak self] _ in
            self?.enterVoiceMode()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
#endif
    }

    func presentPicker(source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source

        let available = UIImagePickerController.availableMediaTypes(for: source) ?? []
        var types = ["public.image"]
        if available.contains("public.movie") { types.append("public.movie") }
        picker.mediaTypes = types

        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 60
        picker.delegate = self
        present(picker, animated: true)
    }

    func uploadAndSendImage(_ image: UIImage) {
        guard !isSending else { return }
        let resized = downscale(image, maxDimension: 1600)
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return }
        endReply()
        setSending(true)
        let filename = "magnistra-\(Int64(Date().timeIntervalSince1970 * 1000)).jpg"
        let spoolPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
        guard (data as NSData).write(toFile: spoolPath, atomically: true) else {
            setSending(false)
            showAlert(title: "Couldn't send photo",
                      message: "The photo couldn't be prepared for upload.")
            return
        }
        let size = data.count
        setUploadProgress(0)

        MatrixE2EEManager.shared.prepareOutboundMedia(roomId: room.roomId, inputPath: spoolPath) {
            [weak self] prepared, prepareError in
            guard let self = self else { return }
            guard let prepared = prepared else {
                try? FileManager.default.removeItem(atPath: spoolPath)
                self.setUploadProgress(nil)
                self.setSending(false)
                self.showSendError(prepareError ?? MatrixAPIClient.MatrixError(
                    errcode: "M_UNKNOWN", error: "Encrypted photo preparation failed"))
                return
            }
            let uploadMime = prepared.encrypted == nil ? "image/jpeg" : "application/octet-stream"
            self.client.uploadMediaFile(path: prepared.path, filename: filename, mimeType: uploadMime,
                                        progress: { [weak self] fraction in
                self?.setUploadProgress(fraction)
            }) { json, error in
                if prepared.removeWhenDone { try? FileManager.default.removeItem(atPath: prepared.path) }
                try? FileManager.default.removeItem(atPath: spoolPath)
                self.setUploadProgress(nil)
                guard let mxc = json?["content_uri"] as? String else {
                    self.setSending(false)
                    self.showSendError(error ?? MatrixAPIClient.MatrixError(
                        errcode: "M_UNKNOWN", error: "Upload returned no content_uri"))
                    return
                }
                if let encrypted = prepared.encrypted {
                    MatrixE2EEManager.registerEncryptedMedia(encrypted, mxc: mxc)
                }
                self.sendImageMessage(mxc: mxc, image: resized, size: size,
                                      filename: filename, encrypted: prepared.encrypted)
            }
        }
    }

    func sendImageMessage(mxc: String, image: UIImage, size: Int, filename: String,
                                  encrypted: MagnistraEncryptedMediaRecord?) {
        let info: [String: Any] = ["mimetype": "image/jpeg",
                                    "w": Int(image.size.width),
                                    "h": Int(image.size.height),
                                    "size": size]
        var body: [String: Any] = ["msgtype": "m.image", "body": filename, "info": info]
        if let encrypted = encrypted {
            body["file"] = encrypted.descriptor(url: mxc)
        } else {
            body["url"] = mxc
        }

        let (reqW, reqH) = ImageEventCell.thumbnailRequestSize(imageWidth: Int(image.size.width),
                                                               imageHeight: Int(image.size.height))
        MediaCache.shared.storeThumbnail(image, mxc: mxc, width: reqW, height: reqH)
        MediaCache.shared.storeFull(image, mxc: mxc)

        sendRoomEvent(type: "m.room.message", content: body, txnId: newTxnId(),
                      knownEncrypted: encrypted != nil) { [weak self] _, error in
            guard let self = self else { return }
            self.setSending(false)
            if let error = error { self.showSendError(error) }
        }
    }

    func uploadAndSendVideo(atPath path: String) {
        guard !isSending else { return }

        endReply()

        setSending(true)
        remuxToMP4(path: path) { [weak self] preparedPath, isTemporary in
            self?.uploadPreparedVideo(atPath: preparedPath, temporary: isTemporary)
        }
    }

    func remuxToMP4(path: String, completion: @escaping (String, Bool) -> Void) {
        guard RoomTimelineVC.videoExtension(of: path) != "mp4" else {
            completion(path, false)
            return
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))

        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetPassthrough),
              session.supportedFileTypes.contains(.mp4) else {
            completion(path, false)
            return
        }

        let name = "magnistra-remux-\(Int64(Date().timeIntervalSince1970 * 1000)).mp4"
        let outPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        session.outputURL = URL(fileURLWithPath: outPath)
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {

            DispatchQueue.main.async {
                guard session.status == .completed else {
                    try? FileManager.default.removeItem(atPath: outPath)
                    completion(path, false)
                    return
                }
                completion(outPath, true)
            }
        }
    }

    func uploadPreparedVideo(atPath path: String, temporary: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let sizeBytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        guard sizeBytes > 0 else {
            failVideoSend(title: "Couldn't read video",
                          message: "The picked video couldn't be opened.",
                          temporaryPath: temporary ? path : nil)
            return
        }

        let meta = videoMeta(path: path)
        let ext = RoomTimelineVC.videoExtension(of: path)
        let mime = RoomTimelineVC.videoMimeType(extension: ext)
        let filename = "magnistra-\(Int64(Date().timeIntervalSince1970 * 1000)).\(ext)"

        MatrixE2EEManager.shared.prepareOutboundMedia(roomId: room.roomId, inputPath: path) {
            [weak self] prepared, prepareError in
            guard let self = self else { return }
            guard let prepared = prepared else {
                if temporary { try? FileManager.default.removeItem(atPath: path) }
                self.failVideoSend(title: "Couldn't encrypt video",
                                   message: "\(prepareError ?? MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN", error: "Encrypted video preparation failed"))",
                                   temporaryPath: nil)
                return
            }

            let uploadMain: (String?, [String: Any]?, UIImage?, MagnistraEncryptedMediaRecord?) -> Void = {
                thumbMxc, thumbInfo, thumbImage, thumbEncrypted in
                self.setUploadProgress(0)
                let uploadMime = prepared.encrypted == nil ? mime : "application/octet-stream"
                self.client.uploadMediaFile(path: prepared.path, filename: filename, mimeType: uploadMime,
                                            progress: { [weak self] fraction in
                    self?.setUploadProgress(fraction)
                }) { json, error in
                    if prepared.removeWhenDone { try? FileManager.default.removeItem(atPath: prepared.path) }
                    if temporary { try? FileManager.default.removeItem(atPath: path) }
                    self.setUploadProgress(nil)
                    guard let mxc = json?["content_uri"] as? String else {
                        self.setSending(false)
                        self.showSendError(error ?? MatrixAPIClient.MatrixError(
                            errcode: "M_UNKNOWN", error: "Upload returned no content_uri"))
                        return
                    }
                    if let encrypted = prepared.encrypted {
                        MatrixE2EEManager.registerEncryptedMedia(encrypted, mxc: mxc)
                    }
                    self.sendVideoMessage(mxc: mxc, filename: filename, mimeType: mime,
                                          size: sizeBytes, meta: meta,
                                          thumbMxc: thumbMxc, thumbInfo: thumbInfo,
                                          thumbImage: thumbImage, thumbEncrypted: thumbEncrypted,
                                          encrypted: prepared.encrypted)
                }
            }

            if prepared.encrypted != nil {
                self.uploadEncryptedVideoThumbnail(path: path, roomId: self.room.roomId,
                                                   completion: uploadMain)
            } else {
                self.uploadVideoThumbnail(path: path) { mxc, info, image in
                    uploadMain(mxc, info, image, nil)
                }
            }
        }
    }

    func failVideoSend(title: String, message: String, temporaryPath: String?) {
        if let temporaryPath = temporaryPath { try? FileManager.default.removeItem(atPath: temporaryPath) }
        setUploadProgress(nil)
        setSending(false)
        showAlert(title: title, message: message)
    }

    func sendVideoMessage(mxc: String, filename: String, mimeType: String, size: Int,
                                  meta: VideoMeta, thumbMxc: String?, thumbInfo: [String: Any]?,
                                  thumbImage: UIImage?, thumbEncrypted: MagnistraEncryptedMediaRecord?,
                                  encrypted: MagnistraEncryptedMediaRecord?) {
        var info: [String: Any] = ["mimetype": mimeType, "size": size]
        if meta.width > 0 { info["w"] = meta.width }
        if meta.height > 0 { info["h"] = meta.height }
        if meta.durationMs > 0 { info["duration"] = meta.durationMs }

        if let thumbMxc = thumbMxc {
            if let thumbEncrypted = thumbEncrypted {
                info["thumbnail_file"] = thumbEncrypted.descriptor(url: thumbMxc)
                if let thumbInfo = thumbInfo { info["thumbnail_info"] = thumbInfo }
            } else if encrypted == nil {
                info["thumbnail_url"] = thumbMxc
                if let thumbInfo = thumbInfo { info["thumbnail_info"] = thumbInfo }
            }
        }

        var body: [String: Any] = ["msgtype": "m.video", "body": filename, "info": info]
        if let encrypted = encrypted {
            body["file"] = encrypted.descriptor(url: mxc)
        } else {
            body["url"] = mxc
        }

        if let thumbMxc = thumbMxc, let thumbImage = thumbImage {
            let (reqW, reqH) = ImageEventCell.thumbnailRequestSize(imageWidth: meta.width,
                                                                  imageHeight: meta.height)
            MediaCache.shared.storeThumbnail(thumbImage, mxc: thumbMxc, width: reqW, height: reqH)
        }

        sendRoomEvent(type: "m.room.message", content: body, txnId: newTxnId(),
                      knownEncrypted: encrypted != nil) { [weak self] _, error in
            guard let self = self else { return }
            self.setSending(false)
            if let error = error { self.showSendError(error) }
        }
    }

    func uploadEncryptedVideoThumbnail(
        path: String,
        roomId: String,
        completion: @escaping (String?, [String: Any]?, UIImage?, MagnistraEncryptedMediaRecord?) -> Void) {
        guard let thumb = videoThumbnail(path: path),
              let data = thumb.jpegData(compressionQuality: 0.7) else {
            completion(nil, nil, nil, nil)
            return
        }

        let filename = "magnistra-thumb-\(Int64(Date().timeIntervalSince1970 * 1000)).jpg"
        let spoolPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
        guard (data as NSData).write(toFile: spoolPath, atomically: true) else {
            completion(nil, nil, nil, nil)
            return
        }

        MatrixE2EEManager.shared.prepareOutboundMedia(roomId: roomId, inputPath: spoolPath) {
            [weak self] prepared, _ in
            guard let self = self else { return }
            guard let prepared = prepared else {
                try? FileManager.default.removeItem(atPath: spoolPath)
                completion(nil, nil, nil, nil)
                return
            }

            let uploadMime = prepared.encrypted == nil ? "image/jpeg" : "application/octet-stream"
            self.client.uploadMediaFile(path: prepared.path, filename: filename, mimeType: uploadMime,
                                        progress: nil) { json, _ in
                if prepared.removeWhenDone {
                    try? FileManager.default.removeItem(atPath: prepared.path)
                }
                try? FileManager.default.removeItem(atPath: spoolPath)

                guard let mxc = json?["content_uri"] as? String, !mxc.isEmpty else {
                    completion(nil, nil, nil, nil)
                    return
                }

                if let encrypted = prepared.encrypted {
                    MatrixE2EEManager.registerEncryptedMedia(encrypted, mxc: mxc)
                }
                completion(mxc,
                           ["mimetype": "image/jpeg",
                            "w": Int(thumb.size.width),
                            "h": Int(thumb.size.height),
                            "size": data.count],
                           thumb,
                           prepared.encrypted)
            }
        }
    }

    func uploadVideoThumbnail(path: String,
                                      completion: @escaping (String?, [String: Any]?, UIImage?) -> Void) {
        guard let thumb = videoThumbnail(path: path),
              let data = thumb.jpegData(compressionQuality: 0.7) else {
            completion(nil, nil, nil)
            return
        }
        let filename = "magnistra-thumb-\(Int64(Date().timeIntervalSince1970 * 1000)).jpg"
        client.uploadMedia(data: data, filename: filename, mimeType: "image/jpeg") { json, _ in
            guard let mxc = json?["content_uri"] as? String, !mxc.isEmpty else {
                completion(nil, nil, nil)
                return
            }
            completion(mxc, ["mimetype": "image/jpeg",
                             "w": Int(thumb.size.width),
                             "h": Int(thumb.size.height),
                             "size": data.count], thumb)
        }
    }

    func videoThumbnail(path: String) -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))

        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)

        let time = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    func videoMeta(path: String) -> VideoMeta {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let seconds = CMTimeGetSeconds(asset.duration)
        let durationMs = (seconds.isFinite && seconds > 0) ? Int(seconds * 1000) : 0
        var width = 0
        var height = 0
        if let track = asset.tracks(withMediaType: .video).first {

            let size = track.naturalSize.applying(track.preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }
        return VideoMeta(width: width, height: height, durationMs: durationMs)
    }

    static func videoExtension(of path: String) -> String {
        let ext = fileExtension(of: path)
        return ["mov", "mp4", "m4v", "3gp"].contains(ext) ? ext : "mov"
    }

    static func videoMimeType(extension ext: String) -> String {
        switch ext {
        case "mp4", "m4v": return "video/mp4"
        case "3gp": return "video/3gpp"
        default: return "video/quicktime"
        }
    }
}
