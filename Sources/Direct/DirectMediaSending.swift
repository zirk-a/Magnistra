// Overview: Direct thread: sending prepared attachments, video thumbnails and upload error display.
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

extension MagnistraDirectThreadViewController {


    func sendDirectPreparedAttachment(
        fileURL:
            URL,
        fileName:
            String,
        mimeType:
            String,
        voiceClip:
            Bool,
        kindName:
            String
    ) {
        if magnistraDirectIsMatrix {
            sendMatrixPreparedMedia(
                fileURL: fileURL,
                fileName: fileName,
                mimeType: mimeType,
                voiceClip: voiceClip
            )
            return
        }
        guard !sending else { return }
        if magnistraDirectIsMatrix {
            try? FileManager.default.removeItem(at: fileURL)
            showDirectOutboundError("Matrix media upload is not yet available. Nothing was sent.")
            return
        }

        sending =
            true

        attachButton.isEnabled =
            false

        messageView.isEditable =
            false

        sendButton.isEnabled =
            false

        let threadFBID =
            summary.threadFBID

        let minUQSeqID =
            summary.minUQSeqID

        let path =
            fileURL.path

        let measured = voiceClip ? magnistraRecordedVoiceLevels : []
        let uploadWaveform: [Double]
        if measured.isEmpty {
            uploadWaveform = []
        } else {
            uploadWaveform = (0..<64).map { index -> Double in
                let position = Double(index) * Double(measured.count - 1) / 63.0
                let left = Int(position)
                let right = min(measured.count - 1, left + 1)
                let frac = position - Double(left)
                let level = measured[left] * (1.0 - frac) + measured[right] * frac
                return Double(Int(level * 100.0)) / 100.0
            }
        }

        loadQueue.addOperation {
            [weak self] in

            do {
                _ =
                    try MagnistraHomeService
                        .sendDirectAttachment(
                            threadFBID:
                                threadFBID,
                            minUQSeqID:
                                minUQSeqID,
                            filePath:
                                path,
                            fileName:
                                fileName,
                            mimeType:
                                mimeType,
                            voiceClip: voiceClip,
                            waveform: uploadWaveform
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.sending =
                            false

                        self.attachButton.isEnabled =
                            true

                        self.messageView.isEditable =
                            true

                        try?
                            FileManager.default
                                .removeItem(
                                    at:
                                        fileURL
                                )

                        if self.outgoingVoiceMode {
                            self
                                .cancelOutgoingVoiceMode(
                                    deleteFile:
                                        false
                                )
                        } else {
                            let clean =
                                self.messageView.text
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )

                            self.sendButton.isEnabled =
                                !clean.isEmpty
                        }

                        self.loadThread()
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.sending =
                            false

                        self.attachButton.isEnabled =
                            true

                        self.messageView.isEditable =
                            true

                        if self.outgoingVoiceMode {
                            self.sendButton.isEnabled =
                                self.outgoingVoiceReady
                        } else {
                            let clean =
                                self.messageView.text
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )

                            self.sendButton.isEnabled =
                                !clean.isEmpty
                        }

                        self
                            .showDirectOutboundError(
                                "Couldn’t send \(kindName): \(message)"
                            )
                    }
            }
        }
    }

    func sendMatrixPreparedMedia(
        fileURL: URL,
        fileName: String,
        mimeType: String,
        voiceClip: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard magnistraDirectIsMatrix, !sending else { completion?(false); return }
        let actualMIME = voiceClip ? "audio/mp4" : mimeType
        let actualName = voiceClip ? "voice.m4a" : fileName
        let allowedMIMEs: Set<String> = [
            "image/jpeg", "video/mp4", "video/quicktime", "audio/wav", "audio/mp4",
            "image/png", "image/gif", "image/webp"
        ]
        guard allowedMIMEs.contains(actualMIME) else {
            showDirectOutboundError("Unsupported Matrix attachment format.")
            completion?(false)
            return
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showDirectOutboundError("Couldn’t access the prepared attachment.")
            completion?(false)
            return
        }
        var mediaInfo: [String: Any] = ["mimetype": actualMIME]
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber {
            mediaInfo["size"] = size
        }
        if mimeType == "image/jpeg", let photo = UIImage(contentsOfFile: fileURL.path) {
            mediaInfo["w"] = Int(photo.size.width)
            mediaInfo["h"] = Int(photo.size.height)
        }
        if voiceClip {
            mediaInfo["duration"] = voiceDurationMS
        }
        sending = true
        attachButton.isEnabled = false
        sendButton.isEnabled = false
        messageView.isEditable = false
        let roomId = summary.threadFBID

        let isSticker = fileURL.path.hasPrefix(MagnistraDirectSavedMediaStore.directory("Matrix") + "/") &&
            (actualMIME == "image/webp" || actualMIME == "image/gif" || actualMIME == "image/png")
        let doUpload: (String?) -> Void = { thumbnailPath in
        MagnistraMatrixDirectBackend.shared.sendMedia(
            roomId: roomId,
            filePath: fileURL.path,
            fileName: actualName,
            mimeType: actualMIME,
            mediaInfo: mediaInfo,
            eventType: isSticker ? "m.sticker" : "m.room.message",
            thumbnailPath: thumbnailPath
        ) { [weak self] _, error in
            if let thumbnailPath = thumbnailPath {
                try? FileManager.default.removeItem(atPath: thumbnailPath)
            }
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.sending = false
                self.attachButton.isEnabled = true
                self.messageView.isEditable = true
                self.sendButton.isEnabled = !self.messageView.text
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if let error = error {
                    self.showDirectOutboundError("Matrix media send failed: " + error.localizedDescription)
                    completion?(false)
                    return
                }

                if !fileURL.path.hasPrefix(MagnistraDirectSavedMediaStore.directory("Matrix") + "/") {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                if voiceClip && self.outgoingVoiceMode {
                    self.cancelOutgoingVoiceMode(deleteFile: false)
                }
                self.loadMatrixThread()
                completion?(true)
            }
        }
        }
        if actualMIME.hasPrefix("video/") {

            loadQueue.addOperation {
                let imagePath = self.createVideoThumbnail(fileURL)
                OperationQueue.main.addOperation { doUpload(imagePath) }
            }
        } else {
            doUpload(nil)
        }
    }

    func createVideoThumbnail(_ videoURL: URL) -> String? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320.0, height: 320.0)
        guard let frame = try? generator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil) else {
            return nil
        }
        let image = UIImage(cgImage: frame)
        guard let data = image.jpegData(compressionQuality: 0.65) else { return nil }
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "magnistra-matrix-video-thumb-" + UUID().uuidString + ".jpg")
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return path
        } catch {
            return nil
        }
    }

    func showDirectOutboundError(
        _ message:
            String
    ) {
        let alert =
            UIAlertView(
                title:
                    "Direct",
                message:
                    message,
                delegate:
                    nil,
                cancelButtonTitle:
                    "OK"
            )

        alert.show()
    }

    @objc func refreshTapped() {
        if usesMatrixBackend { loadMatrixOlder(); return }
        guard !loading else { return }
        pullRefreshIndicator.begin(on: navigationItem, label: "Updating Direct messages")
        loadThread()
    }
}
