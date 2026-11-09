// Overview: Direct thread: loading thread history, status line and day separators.
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


    func loadThread() {
        let silentPoll = silentPollRequested
        silentPollRequested = false

        if summary.threadFBID.hasPrefix("pending:") {
            pullRefreshIndicator.end(on: navigationItem)
            showStatus("Start a conversation.")
            attachButton.isEnabled = false
            return
        }
        if usesMatrixBackend {
            loadMatrixThread()
            return
        }

        if loading {
            return
        }

        loading =
            true
        if !silentPoll {

        navigationItem
            .rightBarButtonItem?
            .isEnabled =
                false
        }

        let threadFBID =
            summary.threadFBID

        loadQueue.addOperation {
            [weak self] in

            do {
                let payload =
                    try MagnistraHomeService
                        .loadDirectThread(
                            threadFBID:
                                threadFBID
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

                        if silentPoll {
                            self.loading = false
                            let ids = payload.messages.map { $0.messageID }
                            if ids == self.lastFetchedPageIDs {
                                NSLog("MAGNISTRA_DIRECT_LIVE phase=UNCHANGED")
                                 self.tryLoadOlderAfterPoll()
                                return
                            }
                            self.lastFetchedPageIDs = ids
                            if self.tableView.isTracking || self.tableView.isDragging ||
                               self.tableView.isDecelerating {

                                self.deferredIncomingMessages.append(contentsOf: payload.messages)
                                self.deferredThreadTitle = payload.title
                                NSLog("MAGNISTRA_DIRECT_LIVE phase=QUEUED count=%ld",
                                      self.deferredIncomingMessages.count)
                                return
                            }
                            let staged = self.deferredIncomingMessages
                            self.deferredIncomingMessages = []
                            self.deferredThreadTitle = nil
                            let incoming = staged.isEmpty ? payload.messages :
                                self.magnistraDirectMerge(existing: staged,
                                                         incoming: payload.messages)
                            self.applyLiveMessages(incoming: incoming, title: payload.title)
                             self.tryLoadOlderAfterPoll()
                            return
                        }
                        self.loading =
                            false
                        self.pullRefreshIndicator.end(on: self.navigationItem)

                        self.navigationItem
                            .rightBarButtonItem?
                            .isEnabled =
                                true

                        let wasEmpty = self.messages.isEmpty
                        let nearBottom = self.magnistraDirectNearBottom()
                        let priorOffset = self.tableView.contentOffset
                        if !self.magnistraDirectInitialPageReceived {
                            self.magnistraDirectHistoryCursor = payload.startCursor
                            self.magnistraDirectHasOlder = payload.hasPreviousPage
                            self.magnistraDirectInitialPageReceived = true
                        }
                        self.messages = self.magnistraDirectMerge(
                            existing: self.messages, incoming: payload.messages
                        )

                        self.title =
                            payload.title

                        self.tableView
                            .reloadData()

                        if self.messages.isEmpty {
                            self.showStatus(
                                "No displayable messages."
                            )
                        } else {
                            self.hideStatus()

                            self.tableView.layoutIfNeeded()
                            if wasEmpty || nearBottom {
                                self.tableView.scrollToRow(
                                    at: self.magnistraDirectPath(forMessage: self.messages.count - 1),
                                    at: .bottom, animated: false
                                )
                            } else {
                                self.tableView.setContentOffset(priorOffset, animated: false)
                            }

                            OperationQueue.main
                                .addOperation {
                                    [weak self] in

                                    self?
                                        .prewarmDirectPreviewWindow()
                                }
                        }
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        if silentPoll {
                        self?.loading = false
                        NSLog("MAGNISTRA_DIRECT_LIVE phase=NETWORK_ERROR")
                        return
                    }
                    self?.loading =
                            false
                        if let owner = self {
                            owner.pullRefreshIndicator.end(on: owner.navigationItem)
                        }

                        self?
                            .navigationItem
                            .rightBarButtonItem?
                            .isEnabled =
                                true

                        self?
                            .showStatus(
                                message
                            )
                    }
            }
        }
    }

    func showStatus(
        _ text:
            String
    ) {
        if NoConnectionBanner.showIfHTTPZero(text, on: view) {
            tableView.backgroundView = nil
            return
        }
        NoConnectionBanner.hide(on: view)
        let label =
            UILabel(
                frame:
                    tableView.bounds
            )

        label.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        label.backgroundColor =
            UIColor.clear

        label.textAlignment =
            .center

        label.textColor =
            UIColor(
                white:
                    0.48,
                alpha:
                    1.0
            )

        label.font =
            UIFont.systemFont(
                ofSize:
                    12.0
            )

        label.numberOfLines =
            0

        label.text =
            text

        tableView.backgroundView =
            label
    }

    func hideStatus() {
        NoConnectionBanner.hide(on: view)
        tableView.backgroundView =
            nil
    }

    func magnistraDirectDaySectionStarts() -> [Int] {
        return daySeparatorIndexes
    }

    func magnistraDirectDateRowMessageIndex(_ path: IndexPath) -> Int? {
        guard path.section == 0 else { return nil }
        for (group, start) in magnistraDirectDaySectionStarts().enumerated() {
            if path.row == start + group { return start }
        }
        return nil
    }

func magnistraDirectMessageIndex(_ path: IndexPath) -> Int {
        guard path.section == 0, path.row >= 0 else { return -1 }
        let starts = magnistraDirectDaySectionStarts()
        var daysBefore = 0
        for (group, start) in starts.enumerated() {
            let dateRow = start + group
            if path.row == dateRow { return -1 }
            if path.row < dateRow { break }
            daysBefore += 1
        }
        let message = path.row - daysBefore
        return message >= 0 && message < messages.count ? message : -1
    }

func magnistraDirectPath(forMessage index: Int) -> IndexPath {
        guard !messages.isEmpty else { return IndexPath(row: 0, section: 0) }
        let safe = max(0, min(index, messages.count - 1))
        var dayCount = 0
        for start in magnistraDirectDaySectionStarts() {
            if start > safe { break }
            dayCount += 1
        }
        return IndexPath(row: safe + dayCount, section: 0)
    }
}
