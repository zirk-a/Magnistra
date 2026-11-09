// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: send queue, pending events and retries.
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


    func sendRoomEvent(type: String, content: [String: Any], txnId: String,
                               knownEncrypted: Bool? = nil,
                               completion: @escaping ([String: Any]?, Error?) -> Void) {
        MatrixE2EEManager.shared.prepareOutboundRoomEvent(
            roomId: room.roomId, type: type, content: content,
            knownEncrypted: knownEncrypted) { [weak self] eventType, eventContent, error in
            guard let self = self else { return }
            if let error = error { completion(nil, error); return }
            guard let eventType = eventType, let eventContent = eventContent else {
                completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                            error: "E2EE send preparation returned no event"))
                return
            }
            let path = "/_matrix/client/v3/rooms/\(self.room.roomId)/send/\(eventType)/\(txnId)"
            self.client.put(path, body: eventContent, completion: completion)
        }
    }

    @objc func sendTapped() {
        if inputMode == .voice { sendVoiceMessage(); return }
        guard let text = messageField.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        guard !isSending else { return }
        messageField.text = ""

        placeholderLabel.isHidden = false
        adjustInputHeight()
        sendTypingStop()

        let replyTarget = replyingToEventId
        endReply()
        pending.append(PendingMessage(txnId: newTxnId(), body: text, replyTo: replyTarget,
                                      timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                                      state: .sending, eventId: nil))
        reloadTable()
        scrollToBottom(animated: true)
        pumpSendQueue()
    }

    func pumpSendQueue() {
        guard !isSendInFlight else { return }
        guard let index = pending.firstIndex(where: { $0.state == .sending && $0.eventId == nil }) else { return }
        let message = pending[index]
        isSendInFlight = true

        var body: [String: Any] = ["msgtype": "m.text", "body": message.body]
        if let replyTo = message.replyTo {
            body["m.relates_to"] = ["m.in_reply_to": ["event_id": replyTo]]
        }
        sendRoomEvent(type: "m.room.message", content: body, txnId: message.txnId) { [weak self] json, error in
            guard let self = self else { return }
            self.isSendInFlight = false
            if let current = self.pending.firstIndex(where: { $0.txnId == message.txnId }) {
                if let error = error {
                    self.pending[current].state = .failed
                    self.pending[current].errorText = "\(error)"
                } else if let eventId = json?["event_id"] as? String {
                    self.pending[current].eventId = eventId
                } else {
                    self.pending.remove(at: current)
                }
                self.reloadTable()
            }
            self.pumpSendQueue()
        }
    }

    func retirePending(matching newEvents: [RoomEvent]) {
        guard !pending.isEmpty else { return }
        var txnIds = Set<String>()
        var eventIds = Set<String>()
        for event in newEvents {
            if let txnId = event.transactionId { txnIds.insert(txnId) }
            eventIds.insert(event.eventId)
        }
        pending.removeAll { message in
            if txnIds.contains(message.txnId) { return true }
            if let eventId = message.eventId, eventIds.contains(eventId) { return true }
            return false
        }
    }

    func handlePendingTap(_ txnId: String) {
        guard let message = pending.first(where: { $0.txnId == txnId }), message.state == .failed else { return }
        pendingActionTxnId = txnId
        let reason = message.errorText
        #if LEGACY_TARGET
        let sheet = UIActionSheet()

        sheet.title = reason == nil ? "Message not sent" : "Message not sent\n\(reason!)"
        sheet.delegate = self
        sheet.tag = pendingSheetTag
        sheet.addButton(withTitle: "Try Again")
        sheet.destructiveButtonIndex = sheet.addButton(withTitle: "Delete")
        sheet.cancelButtonIndex = sheet.addButton(withTitle: "Cancel")
        sheet.show(in: view)
        #else
        let sheet = UIAlertController(title: "Message not sent", message: reason, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.retryPending()
        })
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.discardPending()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true, completion: nil)
        #endif
    }

    func retryPending() {
        guard let txnId = pendingActionTxnId,
              let index = pending.firstIndex(where: { $0.txnId == txnId }) else { return }
        pendingActionTxnId = nil
        pending[index].state = .sending
        pending[index].errorText = nil
        reloadTable()
        pumpSendQueue()
    }

    func discardPending() {
        guard let txnId = pendingActionTxnId else { return }
        pendingActionTxnId = nil
        pending.removeAll { $0.txnId == txnId }
        reloadTable()
    }

    func setSending(_ sending: Bool) {
        isSending = sending
        messageField.isEditable = !sending
        sendButton.isEnabled = !sending
        attachButton.isEnabled = !sending
        if voiceCancelButton != nil { voiceCancelButton.isEnabled = !sending }
        if voiceRecordButton != nil { voiceRecordButton.isEnabled = !sending }
        sendButton.setTitle(sending ? "\u{2026}" : "Send", for: .normal)
    }

    func newTxnId() -> String {
        return "magnistra-\(Int64(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 0..<1_000_000))"
    }

    func sendTypingIfNeeded(isEmpty: Bool) {
        guard let userId = MatrixSession.userId else { return }
        guard !isEmpty else { sendTypingStop(); return }
        let now = Date().timeIntervalSince1970
        guard now - lastTypingSent > 4 else { return }
        lastTypingSent = now
        let path = "/_matrix/client/v3/rooms/\(room.roomId)/typing/\(userId)"
        client.put(path, body: ["typing": true, "timeout": 8000]) { _, _ in }
    }

    func sendTypingStop() {
        guard lastTypingSent > 0, let userId = MatrixSession.userId else { return }
        lastTypingSent = 0
        let path = "/_matrix/client/v3/rooms/\(room.roomId)/typing/\(userId)"
        client.put(path, body: ["typing": false]) { _, _ in }
    }
}
