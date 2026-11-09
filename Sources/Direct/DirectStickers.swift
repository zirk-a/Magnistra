// Overview: Direct thread: saving, sending and browsing saved stickers.
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


    @objc func magnistraSaveDirectMedia(_ gesture: UILongPressGestureRecognizer) {
        guard magnistraDirectIsMatrix else { return }
        guard gesture.state == .began else { return }
        var candidate: UIView? = gesture.view
        while candidate != nil && !(candidate is UITableViewCell) {
            candidate = candidate?.superview
        }
        guard let cell = candidate as? UITableViewCell,
              let path = tableView.indexPath(for: cell) else { return }
        let index = magnistraDirectMessageIndex(path)
        guard index >= 0 && index < messages.count,
              messages[index].previewURL != nil else { return }
        magnistraPendingStickerSaveIndex = index
        let menu = UIActionSheet()
        menu.tag = 98532
        menu.delegate = self
        menu.title = "Sticker"
        menu.addButton(withTitle: "Save Sticker")
        let cancel = menu.addButton(withTitle: "Cancel")
        menu.cancelButtonIndex = cancel
        menu.show(in: view)
    }

    func magnistraConfirmSaveSticker() {
        guard magnistraDirectIsMatrix else { return }
        let index = magnistraPendingStickerSaveIndex
        magnistraPendingStickerSaveIndex = -1
        guard index >= 0 && index < messages.count,
              let url = messages[index].previewURL else { return }
        let msg = messages[index]
        let category = magnistraDirectIsMatrix ? "Matrix" : "Web"
        if magnistraDirectIsMatrix && url.hasPrefix("mxc://") {
            MagnistraMatrixMediaStore.shared.materialize(
                mxc: url, filename: "sticker", mimeType: "application/octet-stream") { [weak self] path in
                guard let path = path else {
                    self?.showDirectOutboundError("Could not save this sticker.")
                    return
                }
                MagnistraDirectSavedMediaStore.saveLocalMatrix(path: path) { [weak self] ok in
                    if !ok { self?.showDirectOutboundError("Could not save this sticker.") }
                }
            }
            return
        }
        MagnistraDirectSavedMediaStore.save(remote: url, key: msg.messageID,
                                           category: category) { [weak self] ok in
            guard let owner = self else { return }

            if !ok {
                owner.showDirectOutboundError("Could not save this sticker.")
            }
        }
    }

    func magnistraOpenSavedStickerLibrary() {
        guard magnistraDirectIsMatrix else { return }
        messageView.resignFirstResponder()
        let picker = MagnistraDirectSavedMediaLibraryVC(
            category: "Matrix")
        picker.onSelect = { [weak self] source, finish in
            guard let self = self else { finish(false); return }
            self.magnistraSendSavedSticker(source, completion: finish)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    func magnistraSendSavedSticker(_ path: String, completion: @escaping (Bool) -> Void) {
        guard !magnistraSavedStickerSending && !sending else { completion(false); return }
        guard magnistraDirectIsMatrix else {

            showDirectOutboundError("Web sticker sending needs a registered Instagram sticker ID.")
            completion(false)
            return
        }
        let suffix = (path as NSString).pathExtension.lowercased()
        guard suffix == "webp" || suffix == "gif" || suffix == "png" else {
            showDirectOutboundError("Unsupported sticker file.")
            completion(false)
            return
        }
        let folder = MagnistraDirectSavedMediaStore.directory("Matrix")
        guard path.hasPrefix(folder + "/") &&
              FileManager.default.fileExists(atPath: path) else { completion(false); return }
        let mime = suffix == "webp" ? "image/webp" :
                   (suffix == "gif" ? "image/gif" : "image/png")
        sendMatrixPreparedMedia(
            fileURL: URL(fileURLWithPath: path),
            fileName: (path as NSString).lastPathComponent,
            mimeType: mime,
            voiceClip: false,
            completion: completion
        )
    }
    func magnistraOpenInstagramCatalog() {
        guard !magnistraDirectIsMatrix else { return }
        let browser = MagnistraIGCatalogVC()
        browser.onChoose = { [weak self] media, finish in
            guard let owner = self else {
                finish(false, "The Direct thread was closed.")
                return
            }
            let destination = owner.summary.threadFBID
            owner.magnistraIGCatalogSendQueue.addOperation { [weak self] in
                do {
                    let _ = try MagnistraHomeService.magnistraIGSendCatalogEntry(
                        threadFBID: destination, media: media)
                    OperationQueue.main.addOperation { [weak self] in
                        self?.loadThread()
                        finish(true,nil)
                    }
                } catch {
                    let detail = error.localizedDescription
                    OperationQueue.main.addOperation {
                        finish(false,detail)
                    }
                }
            }
        }

        browser.view.backgroundColor = UIColor.white
        navigationController?.pushViewController(browser, animated: true)
    }
}
