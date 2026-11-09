// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: sticker library and sending saved stickers.
import Foundation
import UIKit
import Security
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration



extension RoomTimelineVC {

    func presentStickerLibrary() {
        let controller = MagnistraStickerLibraryVC { [weak self] item in
            self?.sendSavedSticker(item)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    func sendSavedSticker(_ item: MagnistraSavedSticker) {
        guard !isSending else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: item.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            showAlert(title: "Sticker", message: "This saved sticker is missing.")
            return
        }

        endReply()
        setSending(true)
        setUploadProgress(0)

        MatrixE2EEManager.shared.prepareOutboundMedia(
            roomId: room.roomId,
            inputPath: item.path
        ) { [weak self] prepared, prepareError in
            guard let self = self else { return }

            guard let prepared = prepared else {
                self.setUploadProgress(nil)
                self.setSending(false)
                self.showSendError(
                    prepareError ?? MatrixAPIClient.MatrixError(
                        errcode: "M_UNKNOWN",
                        error: "Sticker preparation failed"
                    )
                )
                return
            }

            let originalExt = (item.filename.lowercased() as NSString).pathExtension
            let ext = originalExt.isEmpty
                ? ((item.path as NSString).pathExtension.isEmpty
                    ? "bin"
                    : (item.path as NSString).pathExtension)
                : originalExt
            let uploadFilename =
                "magnistra-sticker-\(Int64(Date().timeIntervalSince1970 * 1000)).\(ext)"
            let uploadMime = prepared.encrypted == nil
                ? item.mimeType
                : "application/octet-stream"

            self.client.uploadMediaFile(
                path: prepared.path,
                filename: uploadFilename,
                mimeType: uploadMime,
                progress: { [weak self] fraction in
                    self?.setUploadProgress(fraction)
                }
            ) { json, error in
                if prepared.removeWhenDone {
                    try? FileManager.default.removeItem(atPath: prepared.path)
                }

                self.setUploadProgress(nil)

                guard let mxc = json?["content_uri"] as? String else {
                    self.setSending(false)
                    self.showSendError(
                        error ?? MatrixAPIClient.MatrixError(
                            errcode: "M_UNKNOWN",
                            error: "Sticker upload returned no content_uri"
                        )
                    )
                    return
                }

                if let encrypted = prepared.encrypted {
                    MatrixE2EEManager.registerEncryptedMedia(encrypted, mxc: mxc)
                }

                var info: [String: Any] = [
                    "mimetype": item.mimeType,
                    "size": size
                ]
                if item.width > 0 { info["w"] = item.width }
                if item.height > 0 { info["h"] = item.height }

                let telegramSemanticGIFVideo = item.origin == "telegram"
                    && item.sourceKind == "semantic-gif-to-real-sticker"
                    && item.mimeType.lowercased() == "video/mp4"
                if telegramSemanticGIFVideo {
                    info["is_animated"] = true
                }
                var content: [String: Any] = [
                    "body": item.filename,
                    "info": info
                ]
                if telegramSemanticGIFVideo {
                    content["msgtype"] = "m.video"
                    content["filename"] = item.filename
                }
                if let encrypted = prepared.encrypted {
                    content["file"] = encrypted.descriptor(url: mxc)
                } else {
                    content["url"] = mxc
                }

                self.sendRoomEvent(
                    type: telegramSemanticGIFVideo ? "m.room.message" : "m.sticker",
                    content: content,
                    txnId: self.newTxnId(),
                    knownEncrypted: prepared.encrypted != nil
                ) { [weak self] _, sendError in
                    guard let self = self else { return }
                    self.setSending(false)
                    if let sendError = sendError {
                        self.showSendError(sendError)
                    }
                }
            }
        }
    }
}