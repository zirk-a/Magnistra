// Overview: Direct thread: checking for new messages while the thread is open and merging them in.
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


    @objc func magnistraDirectLiveDidBecomeActive(_ note: Notification) {

        magnistraDirectCheckNewMessages()
    }

    @objc func magnistraDirectCheckNewMessages() {
        if usesMatrixBackend { return }

        flushDeferredIncomingIfPossible()
        if loading || magnistraDirectLoadingOlder { return }
        if UIApplication.shared.applicationState != .active { return }
        if view.window == nil || navigationController?.topViewController !== self { return }
        if summary.threadFBID.hasPrefix("pending:") { return }
        silentPollRequested = true
        loadThread()
    }

    func magnistraDirectNearBottom() -> Bool {
        if messages.isEmpty { return true }
        let visibleBottom = tableView.contentOffset.y + tableView.bounds.height
        return tableView.contentSize.height - visibleBottom < 110.0
    }

    func magnistraDirectMerge(
        existing: [MagnistraDirectMessage], incoming: [MagnistraDirectMessage]
    ) -> [MagnistraDirectMessage] {
        var byID = [String: MagnistraDirectMessage]()
        for message in existing { byID[message.messageID] = message }
        for message in incoming { byID[message.messageID] = message }
        return byID.values.sorted {
            if $0.timestampMilliseconds == $1.timestampMilliseconds {
                return $0.messageID < $1.messageID
            }
            return $0.timestampMilliseconds < $1.timestampMilliseconds
        }
    }

    func magnistraDirectFetchOlder() {
        guard !usesMatrixBackend, !loading, !magnistraDirectLoadingOlder,
              magnistraDirectHasOlder,
              let cursor = magnistraDirectHistoryCursor, !cursor.isEmpty else { return }
        if Date().timeIntervalSince1970 < magnistraDirectOlderRetryAfter { return }
        magnistraDirectLoadingOlder = true
        let threadID = summary.threadFBID
        loadQueue.addOperation { [weak self] in
            do {
                let page = try MagnistraHomeService.loadDirectThread(
                    threadFBID: threadID, olderAfterCursor: cursor
                )
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.magnistraDirectLoadingOlder = false
                    guard self.magnistraDirectHistoryCursor == cursor else { return }
                    let oldHeight = self.tableView.contentSize.height
                    let oldOffset = self.tableView.contentOffset
                    let oldIDs = Set(self.messages.map { $0.messageID })
                    let additions = page.messages.filter { !oldIDs.contains($0.messageID) }
                    self.magnistraDirectHistoryCursor = page.startCursor
                    self.magnistraDirectHasOlder = page.hasPreviousPage &&
                        page.startCursor != cursor && !additions.isEmpty
                    if additions.isEmpty { return }
                    self.messages = self.magnistraDirectMerge(
                        existing: self.messages, incoming: additions
                    )
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                    let delta = self.tableView.contentSize.height - oldHeight
                    self.tableView.setContentOffset(
                        CGPoint(x: oldOffset.x, y: oldOffset.y + delta), animated: false
                    )
                }
            } catch {
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.magnistraDirectLoadingOlder = false
                    self.magnistraDirectOlderRetryAfter =
                        Date().timeIntervalSince1970 + 20.0

                }
            }
        }
    }

    func flushDeferredIncomingIfPossible() {
        if deferredIncomingMessages.isEmpty ||
           tableView.isTracking || tableView.isDragging ||
           tableView.isDecelerating { return }
        let incoming = deferredIncomingMessages
        let title = deferredThreadTitle ?? (self.title ?? "")
        deferredIncomingMessages = []
        deferredThreadTitle = nil
        applyLiveMessages(incoming: incoming, title: title)
    }

    func applyLiveMessages(
        incoming: [MagnistraDirectMessage],
        title: String
    ) {
        guard !incoming.isEmpty else { return }
        let previousIDs = Set(messages.map { $0.messageID })

        guard incoming.contains(where: { !previousIDs.contains($0.messageID) }) else {
            NSLog("MAGNISTRA_DIRECT_LIVE phase=UNCHANGED")
            return
        }
        let nearBottom = magnistraDirectNearBottom()
        let priorOffset = tableView.contentOffset
        let oldCount = messages.count
        let merged = magnistraDirectMerge(existing: messages, incoming: incoming)
        guard merged.count > oldCount else { return }
        messages = merged

        tableView.reloadData()
        NSLog("MAGNISTRA_DIRECT_LIVE phase=RELOAD_NEW count=%ld",
              merged.count - oldCount)
        if nearBottom && !messages.isEmpty {
            tableView.scrollToRow(
                at: magnistraDirectPath(forMessage: messages.count - 1),
                at: .bottom, animated: false
            )
        } else {
            tableView.setContentOffset(priorOffset, animated: false)
        }
        if self.title != title { self.title = title }
    }
}
