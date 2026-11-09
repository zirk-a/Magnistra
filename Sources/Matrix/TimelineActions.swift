// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: initial events, live decrypts, read receipts and table setup.
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


    func seedInitialEvents() {
        guard !room.timelineEvents.isEmpty else { return }
        for event in room.timelineEvents where !seenEventIds.contains(event.eventId) {
            seenEventIds.insert(event.eventId)
            events.append(event)
        }
        applyCachedLiveDecrypts()
        reloadTable()
        updateStatusLabel()
        scrollToBottom(animated: false)
        if let latest = events.last {
            sendReadReceipt(for: latest.eventId)
        }
    }

    func applyCachedLiveDecrypts() {
        var i = 0
        while i < events.count {
            let eventId = events[i].eventId
            if let raw = MatrixE2EEManager.shared.cachedDecryptedRoomEvent(eventId: eventId),
               let replacement = RoomEvent.parse(raw),
               replacement.eventId == eventId {
                events[i] = replacement
            }
            i += 1
        }
    }

    @objc func e2eeLiveDecrypted(_ notification: Notification) {
        guard let info = notification.userInfo,
              let roomId = info["room_id"] as? String, roomId == room.roomId,
              let raw = info["event"] as? [String: Any] else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let replacement = RoomEvent.parse(raw),
                  let index = self.events.firstIndex(where: { $0.eventId == replacement.eventId }) else {
                return
            }

            self.tableView.layoutIfNeeded()
            let oldOffset = self.tableView.contentOffset
            let oldMax = self.tableView.contentSize.height - self.tableView.bounds.height
                + self.tableView.contentInset.bottom
            let wasNearBottom = oldMax - oldOffset.y <= 120

            self.events[index] = replacement
            self.reloadTable()
            self.tableView.layoutIfNeeded()

            if wasNearBottom {
                self.scrollToBottom(animated: false)
            } else {
                let newMax = self.tableView.contentSize.height - self.tableView.bounds.height
                    + self.tableView.contentInset.bottom
                let minY = -self.tableView.contentInset.top
                let maxY = max(minY, newMax)
                let y = min(maxY, max(minY, oldOffset.y))
                self.tableView.setContentOffset(CGPoint(x: oldOffset.x, y: y), animated: false)
            }
            print("[MagnistraE2EE] timeline event updated")
        }
    }

    func sendReadReceipt(for eventId: String) {
        let path = "/_matrix/client/v3/rooms/\(room.roomId)/receipt/m.read/\(eventId)"
        client.post(path, body: [:]) { _, _ in }
    }

    func buildTableView() {
        let frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - inputBar.frame.height)
        tableView = UITableView(frame: frame, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none

        tableView.backgroundColor = .clear

        let reveal = UIPanGestureRecognizer(target: self, action: #selector(handleReveal(_:)))
        reveal.delegate = self
        tableView.addGestureRecognizer(reveal)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)

        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        header.autoresizingMask = [.flexibleWidth]
        let spinner = UIActivityIndicatorView(style: .gray)
        spinner.hidesWhenStopped = true
        spinner.center = CGPoint(x: header.bounds.midX, y: header.bounds.midY)
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        header.addSubview(spinner)
        backfillSpinner = spinner
        backfillHeader = header

        view.insertSubview(tableView, belowSubview: inputBar)
    }

    func setBackfillSpinner(active: Bool) {
        guard let header = backfillHeader, let spinner = backfillSpinner else { return }
        if reachedHistoryStart {
            spinner.stopAnimating()
            if tableView.tableHeaderView != nil { tableView.tableHeaderView = nil }
            return
        }
        if active {
            spinner.startAnimating()
            if tableView.tableHeaderView == nil { tableView.tableHeaderView = header }
        } else {
            spinner.stopAnimating()
        }
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point) else { return }
        guard indexPath.row < rows.count else { return }
        let row = rows[indexPath.row]
        pendingCopyText = copyText(for: row)
        pendingReactionEventId = reactableEventId(for: row)
        pendingDeleteEventId = deletableEventId(for: row)
        pendingReplyTargetId = replyableEventId(for: row)

        guard pendingCopyText != nil || pendingReactionEventId != nil else { return }

        pendingSaveSticker = saveableSticker(for: rows[indexPath.row])

        becomeFirstResponder()
        let menu = UIMenuController.shared

        var items: [UIMenuItem] = []
        if pendingReplyTargetId != nil {
            items.append(UIMenuItem(title: "Reply", action: #selector(replyMenuTapped(_:))))
        }
        if pendingReactionEventId != nil {
            items.append(UIMenuItem(title: "React", action: #selector(reactMenuTapped(_:))))
        }
        if pendingDeleteEventId != nil {
            items.append(UIMenuItem(title: "Delete", action: #selector(deleteMenuTapped(_:))))
        }
        if let pendingSaveSticker = pendingSaveSticker {
            let saveTitle = pendingSaveSticker.semanticGIF
                ? "Save as…"
                : "Save Sticker"
            items.append(UIMenuItem(
                title: saveTitle,
                action: #selector(saveStickerMenuTapped(_:))
            ))
        }
        menu.menuItems = items.isEmpty ? nil : items
        let cellRect = tableView.rectForRow(at: indexPath)
        menu.setTargetRect(tableView.convert(cellRect, to: view), in: view)
        menu.setMenuVisible(true, animated: true)
    }

    func reactableEventId(for row: Row) -> String? {
        guard case .event(let eventRow) = row else { return nil }
        switch eventRow.event.kind {
        case .message, .image, .audio, .file, .video: return eventRow.event.eventId
        case .membership, .reaction, .redaction, .edit: return nil
        }
    }

    func presentSemanticGIFSaveOptions(
        mxc: String,
        width: Int,
        height: Int
    ) {
        pendingSaveSticker = (
            mxc: mxc,
            width: width,
            height: height,
            semanticGIF: true
        )

        let sheet = UIActionSheet()
        sheet.delegate = self
        sheet.title = "Save as…"
        sheet.addButton(withTitle: "Save Video")
        sheet.addButton(withTitle: "WhatsApp Sticker")
        sheet.addButton(withTitle: "Telegram Sticker")
        let cancel = sheet.addButton(withTitle: "Cancel")
        sheet.cancelButtonIndex = cancel
        sheet.show(in: view)
    }

    func saveSemanticGIFVideoToPhotos(mxc: String) {
        guard let info = MediaCache.shared.videoBackedAnimatedInfo(for: mxc) else {
            showAlert(title: "Save Video", message: "The original GIF video is not available yet.")
            return
        }

        MediaCache.shared.downloadFile(
            mxc: mxc,
            filename: info.filename,
            mimeType: info.mimeType,
            progress: nil
        ) { [weak self] path in
            guard let self = self, let path = path else {
                self?.showAlert(title: "Save Video", message: "The original video could not be downloaded.")
                return
            }

            let savePath = MediaCache.legacyVideoPlaybackPath(
                path: path,
                mimeType: info.mimeType,
                animated: false
            )
            guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(savePath) else {
                self.showAlert(title: "Save Video", message: "This video format cannot be saved by iOS Photos.")
                return
            }
            UISaveVideoAtPathToSavedPhotosAlbum(savePath, nil, nil, nil)
        }
    }

    @objc func saveStickerMenuTapped(_ sender: Any?) {
        guard let sticker = pendingSaveSticker else { return }
        UIMenuController.shared.setMenuVisible(false, animated: true)

        if sticker.semanticGIF {
            presentSemanticGIFSaveOptions(
                mxc: sticker.mxc,
                width: sticker.width,
                height: sticker.height
            )
            return
        }

        MagnistraStickerLibrary.shared.save(
            mxc: sticker.mxc,
            bridgeNetwork: room.bridgeNetwork,
            width: sticker.width,
            height: sticker.height
        )
        pendingSaveSticker = nil
    }

    func deletableEventId(for row: Row) -> String? {
        guard case .event(let eventRow) = row,
              RoomTimelineVC.senderOf(eventRow.event) == MatrixSession.userId else { return nil }
        return eventRow.event.eventId
    }

    func replyableEventId(for row: Row) -> String? {
        guard case .event(let eventRow) = row else { return nil }
        switch eventRow.event.kind {
        case .message, .image, .audio, .file, .video: return eventRow.event.eventId
        case .membership, .reaction, .redaction, .edit: return nil
        }
    }

    func copyText(for row: Row) -> String? {

        if case .pending(let message) = row { return message.body }
        guard case .event(let eventRow) = row else { return nil }
        switch eventRow.event.kind {

        case .message(_, let body, _): return eventRow.editedBody ?? body
        case .image(_, let caption, _, _, _):
            if caption == "__magnistra_sticker__" { return "Sticker" }
            if caption == "__magnistra_gif__"
                || caption == "__magnistra_whatsapp_webp__" { return "GIF" }
            return caption.isEmpty ? nil : caption
        case .audio(_, _, _, let caption): return caption.isEmpty ? nil : caption
        case .file(_, _, let filename, _, _): return filename
        case .video(_, let video): return video.filename
        case .membership(let description): return description
        case .reaction, .redaction, .edit: return nil
        }
    }

    func saveableSticker(
        for row: Row
    ) -> (mxc: String, width: Int, height: Int, semanticGIF: Bool)? {
        guard case .event(let eventRow) = row else { return nil }
        guard case .image(_, let caption, let mxc, let width, let height) = eventRow.event.kind else {
            return nil
        }

        if caption == "__magnistra_whatsapp_webp__" {
            return (mxc: mxc, width: width, height: height, semanticGIF: true)
        }

        guard caption == "__magnistra_sticker__"
            || MediaCache.shared.stickerInfo(for: mxc) != nil else { return nil }
        return (mxc: mxc, width: width, height: height, semanticGIF: false)
    }

    @objc func replyMenuTapped(_ sender: Any?) {
        guard let eventId = pendingReplyTargetId else { return }
        UIMenuController.shared.setMenuVisible(false, animated: true)
        beginReply(to: eventId)
    }

    func beginReply(to eventId: String) {

        if inputMode == .voice { exitVoiceMode() }
        replyingToEventId = eventId

        let source = eventsById[eventId]
        replyingToSender = source.flatMap { RoomTimelineVC.senderOf($0) }
        replyingToPreview = source.flatMap { RoomTimelineVC.previewText(for: $0) }
        if let sender = replyingToSender {
            let name = memberNames[sender] ?? shortName(sender)
            let quote = RoomTimelineVC.oneLine(replyingToPreview ?? "", limit: 80)
            replyLabel.text = "Replying to \(name): \(quote)"
        } else {
            replyLabel.text = "Replying to a message"
        }
        replyBar.isHidden = false
        layoutInputBar()
        messageField.becomeFirstResponder()
    }

    func endReply() {
        guard replyingToEventId != nil else { return }
        replyingToEventId = nil
        replyingToSender = nil
        replyingToPreview = nil
        replyBar.isHidden = true
        layoutInputBar()
    }

    @objc func replyCancelTapped() { endReply() }

    static func oneLine(_ text: String, limit: Int) -> String {
        var out = ""
        var lastWasSpace = true
        for scalar in text.unicodeScalars {
            if out.count >= limit { return out + "\u{2026}" }
            if scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return out
    }

    @objc func deleteMenuTapped(_ sender: Any?) {
        guard pendingDeleteEventId != nil else { return }
        UIMenuController.shared.setMenuVisible(false, animated: true)
        #if LEGACY_TARGET
        let sheet = UIActionSheet()
        sheet.title = "Delete this message?"
        sheet.delegate = self
        sheet.tag = deleteSheetTag
        sheet.destructiveButtonIndex = sheet.addButton(withTitle: "Delete")
        sheet.cancelButtonIndex = sheet.addButton(withTitle: "Cancel")
        sheet.show(in: view)
        #else
        let sheet = UIAlertController(title: "Delete this message?", message: nil,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteConfirmed()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true, completion: nil)
        #endif
    }

    func deleteConfirmed() {
        guard let eventId = pendingDeleteEventId else { return }
        let path = "/_matrix/client/v3/rooms/\(room.roomId)/redact/\(eventId)/\(newTxnId())"
        client.put(path, body: [:]) { [weak self] _, error in
            if let error = error {
                self?.showAlert(title: "Delete failed", message: "\(error)")
            }
        }
    }

    @objc func reactMenuTapped(_ sender: Any?) {
        guard let target = pendingReactionEventId else { return }
        UIMenuController.shared.setMenuVisible(false, animated: true)
        #if LEGACY_TARGET
        let sheet = UIActionSheet()
        sheet.title = "React"
        sheet.delegate = self
        sheet.tag = reactionSheetTag
        for key in RoomTimelineVC.quickReactions { sheet.addButton(withTitle: key) }
        sheet.cancelButtonIndex = sheet.addButton(withTitle: "Cancel")
        sheet.show(in: view)
        #else
        let sheet = UIAlertController(title: "React", message: nil, preferredStyle: .actionSheet)
        for key in RoomTimelineVC.quickReactions {
            sheet.addAction(UIAlertAction(title: key, style: .default) { [weak self] _ in
                self?.toggleReaction(target: target, key: key)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true, completion: nil)
        #endif
    }

    func toggleReaction(target: String, key: String) {
        if let mine = myReactions[target]?[key] {
            let path = "/_matrix/client/v3/rooms/\(room.roomId)/redact/\(mine)/\(newTxnId())"
            client.put(path, body: [:]) { _, _ in }
        } else {
            let path = "/_matrix/client/v3/rooms/\(room.roomId)/send/m.reaction/\(newTxnId())"
            let body: [String: Any] = ["m.relates_to": ["rel_type": "m.annotation",
                                                        "event_id": target,
                                                        "key": key]]
            client.put(path, body: body) { _, _ in }
        }
    }

    @objc func handleReveal(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:

            let point = gesture.location(in: tableView)
            if let indexPath = tableView.indexPathForRow(at: point), indexPath.row < rows.count {
                replySwipeEventId = replyableEventId(for: rows[indexPath.row])
            } else {
                replySwipeEventId = nil
            }
            replySwipeArmed = false
        case .changed:
            let t = gesture.translation(in: tableView)

            guard abs(t.x) > abs(t.y) else { return }
            if t.x > 0 {

                guard replySwipeEventId != nil else { return }
                setRevealOffset(-min(RoomTimelineVC.maxReplyPull, t.x))

                replySwipeArmed = t.x >= RoomTimelineVC.replyTriggerDistance
            } else {
                replySwipeArmed = false
                setRevealOffset(min(EventCell.maxReveal, -t.x))
            }
        case .ended, .cancelled, .failed:
            let target = (gesture.state == .ended && replySwipeArmed) ? replySwipeEventId : nil
            replySwipeArmed = false
            replySwipeEventId = nil
            UIView.animate(withDuration: 0.2) { self.setRevealOffset(0) }
            if let target = target { beginReply(to: target) }
        default:
            break
        }
    }

    func setRevealOffset(_ offset: CGFloat) {
        revealOffset = offset
        for cell in tableView.visibleCells {
            (cell as? EventCell)?.setRevealOffset(offset)
            (cell as? ImageEventCell)?.setRevealOffset(offset)
            (cell as? AudioEventCell)?.setRevealOffset(offset)
            (cell as? FileEventCell)?.setRevealOffset(offset)
            (cell as? VideoEventCell)?.setRevealOffset(offset)
            (cell as? ReactionsCell)?.setRevealOffset(offset)
        }
    }
}
