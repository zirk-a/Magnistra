// Overview: Direct thread: keyboard handling, scrolling to the bottom and sending text.
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


    func directThreadIsNearBottom() -> Bool {
        guard
            !messages.isEmpty
        else {
            return
                true
        }

        if
            let visible =
                tableView.indexPathsForVisibleRows,
            visible.contains(
                self.magnistraDirectPath(forMessage: messages.count -
                        1)
            )
        {
            return
                true
        }

        let remaining =
            tableView.contentSize.height -
            (
                tableView.contentOffset.y +
                tableView.bounds.size.height
            )

        return
            remaining <
            72.0
    }

    func directScrollToBottom(
        animated:
            Bool
    ) {
        guard
            !messages.isEmpty
        else {
            return
        }

        tableView.scrollToRow(
            at:
                self.magnistraDirectPath(forMessage: messages.count -
                        1),
            at:
                .bottom,
            animated:
                animated
        )
    }
    func animateKeyboardViewport(pinBottom: Bool, resetPin: Bool) {
        let top = max(0.0, view.bounds.size.height - keyboardHeight - composerHeight)
        UIView.animate(withDuration: 0.22, animations: {
            var composerFrame = self.composerBar.frame
            composerFrame.origin.y = top
            self.composerBar.frame = composerFrame
            self.layoutComposerFade()
            var tableFrame = self.tableView.frame
            tableFrame.size.height = top + self.composerHeight
            self.tableView.frame = tableFrame
        }, completion: { _ in
            if pinBottom { self.directScrollToBottom(animated: false) }
            if resetPin { self.keyboardKeepsBottomPinned = false }
        })
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        keyboardKeepsBottomPinned = directThreadIsNearBottom()
        guard let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let frame = view.convert(value.cgRectValue, from: nil)
        keyboardHeight = max(0.0, view.bounds.maxY - frame.minY)
        animateKeyboardViewport(pinBottom: keyboardKeepsBottomPinned, resetPin: false)
    }
    @objc func keyboardWillHide(_ notification: Notification) {
        let pin = directThreadIsNearBottom() || keyboardKeepsBottomPinned
        keyboardHeight = 0.0
        animateKeyboardViewport(pinBottom: pin, resetPin: true)
    }

    func textViewDidChange(
        _ textView:
            UITextView
    ) {
        let text =
            textView.text
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        sendButton.isEnabled =
            !text.isEmpty

        sendButton.alpha =
            1.0

        messagePlaceholder.isHidden =
            !textView.text.isEmpty
        layoutComposer()

        let availableWidth =
            max(
                1.0,
                messageView.bounds.size.width
            )

        let fit =
            textView.sizeThatFits(
                CGSize(
                    width:
                        availableWidth,
                    height:
                        1000.0
                )
            )

        let desiredHeight =
            min(
                composerMaxHeight,
                max(
                    composerMinHeight,
                    fit.height +
                        12.0
                )
            )

        if
            abs(
                desiredHeight -
                composerHeight
            ) >
                0.5
        {
            composerHeight =
                desiredHeight

            textView.isScrollEnabled =
                composerHeight >=
                composerMaxHeight -
                0.5

            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    @objc func dismissKeyboardFromChat() {
        messageView
            .resignFirstResponder()
    }

    @objc func sendTapped() {
        if outgoingVoiceMode {
            outgoingVoiceSendTapped()
            return
        }

        if usesMatrixBackend {
            sendMatrixText()
            return
        }

        let text =
            messageView.text
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard
            !sending,
            !text.isEmpty
        else {
            return
        }

        sending =
            true

        sendButton.isEnabled =
            false

        messageView.isEditable =
            false

        let threadFBID =
            summary.threadFBID

        let minUQSeqID =
            summary.minUQSeqID
        let isFirstMessage = threadFBID.hasPrefix("pending:")
        let pendingRecipient = isFirstMessage ? String(threadFBID.dropFirst(8)) : ""

        let localMessageID =
            "local-send-" +
            String(
                Int64(
                    Date()
                        .timeIntervalSince1970 *
                    1000.0
                )
            ) +
            "-" +
            String(
                arc4random_uniform(
                    1000000
                )
            )

        let localTimestamp =
            Date()
                .timeIntervalSince1970 *
            1000.0

        let pending =
            MagnistraDirectMessage(
                messageID:
                    localMessageID,
                text:
                    text,
                detailText:
                    nil,
                previewURL:
                    nil,
                contentType:
                    "TEXT",
                timestampMilliseconds:
                    localTimestamp,
                isOutgoing:
                    true
            )

        messages.append(
            pending
        )

        messages.sort {
            if
                $0.timestampMilliseconds ==
                $1.timestampMilliseconds
            {
                return
                    $0.messageID <
                    $1.messageID
            }

            return
                $0.timestampMilliseconds <
                $1.timestampMilliseconds
        }

        messageView.text =
            ""

        messagePlaceholder.isHidden =
            false

        composerHeight =
            composerMinHeight

        messageView.isScrollEnabled =
            false

        view.setNeedsLayout()
        view.layoutIfNeeded()

        tableView.reloadData()
        hideStatus()

        if
            let pendingIndex =
                messages.firstIndex(
                    where: {
                        $0.messageID ==
                        localMessageID
                    }
                )
        {
            tableView.scrollToRow(
                at:
                    self.magnistraDirectPath(forMessage: pendingIndex),
                at:
                    .bottom,
                animated:
                    true
            )
        }

        loadQueue.addOperation {
            [weak self] in

            do {
                let result =
                    try MagnistraHomeService
                        .sendDirectText(
                            threadFBID:
                                threadFBID,
                            minUQSeqID:
                                minUQSeqID,
                            text:
                                text
                        )

                var actualThread: MagnistraDirectThreadSummary? = nil
                if isFirstMessage {
                    if let page = try? MagnistraHomeService.loadDirectInbox() {
                        actualThread = page.threads.first(where: {
                            !$0.isGroupConversation &&
                            $0.participantUserIDs.contains(pendingRecipient)
                        })
                    }
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        if
                            let index =
                                self.messages.firstIndex(
                                    where: {
                                        $0.messageID ==
                                        localMessageID
                                    }
                                )
                        {
                            self.messages[index] =
                                MagnistraDirectMessage(
                                    messageID:
                                        result.messageID,
                                    text:
                                        text,
                                    detailText:
                                        nil,
                                    previewURL:
                                        nil,
                                    contentType:
                                        "TEXT",
                                    timestampMilliseconds:
                                        result.timestampMilliseconds,
                                    isOutgoing:
                                        true
                                )
                        }

                        self.messages.sort {
                            if
                                $0.timestampMilliseconds ==
                                $1.timestampMilliseconds
                            {
                                return
                                    $0.messageID <
                                    $1.messageID
                            }

                            return
                                $0.timestampMilliseconds <
                                $1.timestampMilliseconds
                        }

                        if let confirmedThread = actualThread {
                            self.summary = confirmedThread
                            self.attachButton.isEnabled = true
                        }
                        self.sending =
                            false

                        self.messageView.isEditable =
                            true

                        let current =
                            self.messageView.text
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )

                        self.sendButton.isEnabled =
                            !current.isEmpty

                        self.sendButton.alpha =
                            1.0

                        self.tableView.reloadData()
                        if actualThread != nil { self.loadThread() }
                    }
            } catch {
                let failure =
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

                        if
                            let index =
                                self.messages.firstIndex(
                                    where: {
                                        $0.messageID ==
                                        localMessageID
                                    }
                                )
                        {
                            self.messages.remove(
                                at:
                                    index
                            )
                        }

                        self.sending =
                            false

                        self.messageView.isEditable =
                            true

                        self.messageView.text =
                            text

                        self.messagePlaceholder.isHidden =
                            text.isEmpty

                        self.composerHeight =
                            self.composerMinHeight

                        self.messageView.isScrollEnabled =
                            false

                        self.sendButton.isEnabled =
                            !text.isEmpty

                        self.sendButton.alpha =
                            1.0

                        self.view.setNeedsLayout()
                        self.view.layoutIfNeeded()

                        self.tableView.reloadData()

                        let alert =
                            UIAlertView(
                                title:
                                    "Direct",
                                message:
                                    failure,
                                delegate:
                                    nil,
                                cancelButtonTitle:
                                    "OK"
                            )

                        alert.show()
                    }
            }
        }
    }
}
