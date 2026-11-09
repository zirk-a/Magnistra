// Overview: Direct thread (Matrix): sync and key updates, loading threads and older messages, sending text.
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


    @objc func matrixSyncUpdate(_ notification: Notification) {
        guard usesMatrixBackend, isViewLoaded, view.window != nil,
              let roomIds = notification.userInfo?["roomIds"] as? [String],
              roomIds.contains(summary.threadFBID) else { return }
        if loading {
            matrixRefreshQueued = true
        } else {
            matrixSilentRefresh = true
            loadMatrixThread()
        }
    }

    @objc func matrixKeyUpdate(_ notification: Notification) {
        guard usesMatrixBackend, isViewLoaded, view.window != nil,
              let roomId = notification.userInfo?["room_id"] as? String,
              roomId == summary.threadFBID else { return }
        if loading {
            matrixRefreshQueued = true
        } else {
            matrixSilentRefresh = true
            loadMatrixThread()
        }
    }

    func loadMatrixThread() {
        guard !loading else {
            return
        }

        let refreshWasSilent = matrixSilentRefresh
        let refreshWasNearBottom = directThreadIsNearBottom()
        loadWasSilent = refreshWasSilent
        loadWasNearBottom = refreshWasNearBottom
        matrixSilentRefresh = false
        loading = true
        if !refreshWasSilent {
            navigationItem.rightBarButtonItem?.isEnabled = false
            showStatus("Loading messages...")
        }

        let roomId = summary.threadFBID

        loadQueue.addOperation {
            [weak self] in

            guard let self = self else {
                return
            }

            do {
                let page = try MagnistraMatrixDirectService.loadTimelinePage(
                    roomId: roomId, before: nil)
                let direct = page.messages.map { self.matrixDirectMessage($0) }

                OperationQueue.main.addOperation {
                    [weak self] in

                    guard let self = self else {
                        return
                    }

                    self.loading = false
                    if self.matrixRefreshQueued {
                        self.matrixRefreshQueued = false
                        self.matrixSilentRefresh = true
                        OperationQueue.main.addOperation { [weak self] in self?.loadMatrixThread() }
                    }
                    self.pullRefreshIndicator.end(on: self.navigationItem)
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    let wasEmpty = self.messages.isEmpty
                    let nearBottom = self.magnistraDirectNearBottom()
                    let offset = self.tableView.contentOffset
                    if !self.matrixTimelineInitialized {
                        self.matrixTimelineCursor = page.nextCursor
                        self.matrixTimelineHasOlder = page.hasOlder
                        self.matrixTimelineInitialized = true
                    }
                    self.messages = self.magnistraDirectMerge(
                        existing: self.messages, incoming: direct)
                    do {
                        let refreshWasSilent = self.loadWasSilent
                        let refreshWasNearBottom = self.loadWasNearBottom
                        let preservedScrollOffset = self.tableView.contentOffset
                        self.tableView.reloadData()

                    if self.usesMatrixBackend && !refreshWasSilent &&
                       !self.firstOpenReconciled {
                        self.firstOpenReconciled = true
                        let firstRoom = self.summary.threadFBID
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
                            guard let self = self, self.isViewLoaded,
                                  self.view.window != nil,
                                  self.usesMatrixBackend,
                                  self.summary.threadFBID == firstRoom else { return }
                            if self.loading {
                                self.matrixRefreshQueued = true
                            } else {
                                self.matrixSilentRefresh = true
                                self.loadMatrixThread()
                            }
                        }
                    }
                        if refreshWasSilent && !refreshWasNearBottom {
                            self.tableView.setContentOffset(preservedScrollOffset, animated: false)
                        }
                    }

                    if self.messages.isEmpty {
                        self.showStatus("No messages.")
                    } else {
                        self.hideStatus()
                        self.primeMatrixMedia()
                        if wasEmpty || nearBottom {
                            if !refreshWasSilent || refreshWasNearBottom {
                                self.tableView.scrollToRow(
                                    at: self.magnistraDirectPath(forMessage: self.messages.count-1),
                                    at: .bottom, animated: false)
                            }
                        } else {
                            self.tableView.setContentOffset(offset, animated: false)
                        }
                    }
                }
            } catch {
                let message = error.localizedDescription

                OperationQueue.main.addOperation {
                    [weak self] in

                    self?.loading = false
                    if let owner = self, owner.matrixRefreshQueued {
                        owner.matrixRefreshQueued = false
                        owner.matrixSilentRefresh = true
                        OperationQueue.main.addOperation { [weak owner] in owner?.loadMatrixThread() }
                    }
                    if let owner = self {
                        owner.pullRefreshIndicator.end(on: owner.navigationItem)
                    }
                    self?.navigationItem.rightBarButtonItem?.isEnabled = true
                    self?.showStatus(message)
                }
            }
        }
    }

    func loadMatrixOlder() {
        guard usesMatrixBackend, matrixTimelineInitialized,
              matrixTimelineHasOlder, !loading, !matrixOlderLoading,
              let cursor = matrixTimelineCursor, !cursor.isEmpty else { return }
        if Date().timeIntervalSince1970 < matrixOlderRetryAfter { return }
        matrixOlderLoading = true
        let room = summary.threadFBID
        pullRefreshIndicator.begin(on: navigationItem, label: "Loading earlier messages")
        loadQueue.addOperation { [weak self] in
            guard let self = self else { return }
            do {
                let page = try MagnistraMatrixDirectService.loadTimelinePage(
                    roomId: room, before: cursor)
                let direct = page.messages.map { self.matrixDirectMessage($0) }
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.matrixOlderLoading = false
                    self.pullRefreshIndicator.end(on: self.navigationItem)
                    guard self.matrixTimelineCursor == cursor else { return }
                    let known = Set(self.messages.map { $0.messageID })
                    let added = direct.filter { !known.contains($0.messageID) }
                    self.matrixTimelineCursor = page.nextCursor
                    self.matrixTimelineHasOlder = page.hasOlder &&
                        page.nextCursor != cursor && !added.isEmpty
                    if added.isEmpty { return }
                    let height = self.tableView.contentSize.height
                    let offset = self.tableView.contentOffset
                    self.messages = self.magnistraDirectMerge(
                        existing: self.messages, incoming: added)
                    do {
                        let refreshWasSilent = self.loadWasSilent
                        let refreshWasNearBottom = self.loadWasNearBottom
                        let preservedScrollOffset = self.tableView.contentOffset
                        self.tableView.reloadData()
                        if refreshWasSilent && !refreshWasNearBottom {
                            self.tableView.setContentOffset(preservedScrollOffset, animated: false)
                        }
                    }
                    self.tableView.layoutIfNeeded()
                    self.tableView.setContentOffset(
                        CGPoint(x: offset.x,
                                y: offset.y + self.tableView.contentSize.height - height),
                        animated: false)
                    self.primeMatrixMedia()
                }
            } catch {
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.matrixOlderLoading = false
                    self.pullRefreshIndicator.end(on: self.navigationItem)
                    self.matrixOlderRetryAfter = Date().timeIntervalSince1970 + 12.0
                }
            }
        }
    }

    func sendMatrixText() {
        let text =
            messageView.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !text.isEmpty else {
            return
        }

        sendButton.isEnabled = false
        messageView.isEditable = false

        MagnistraMatrixDirectBackend.shared.sendText(
            roomId: summary.threadFBID,
            text: text
        ) {
            [weak self]
            _, error in

            OperationQueue.main.addOperation {
                guard let self = self else {
                    return
                }

                self.sendButton.isEnabled = true
                self.messageView.isEditable = true

                if let error = error {
                    self.showStatus(error.localizedDescription)
                    return
                }

                self.messageView.text = ""
                self.messagePlaceholder.isHidden = false
                self.composerHeight = self.composerMinHeight
                self.messageView.isScrollEnabled = false
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.loadMatrixThread()
            }
        }
    }

    func primeMatrixMedia() {
        for (index, message) in messages.enumerated() {
            guard
                message.mediaKind == "photo" ||
                message.mediaKind == "video",
                let mxc = message.previewURL,
                mxc.hasPrefix("mxc://")
            else {
                continue
            }

            MagnistraMatrixMediaStore.shared.loadImage(
                mxc: mxc
            ) {
                [weak self]
                image in

                guard
                    let self = self,
                    let image = image,
                    index < self.messages.count,
                    self.messages[index].messageID == message.messageID
                else {
                    return
                }

                MagnistraDirectMessageCell.seedPreview(
                    image,
                    messageID: message.messageID
                )

                self.tableView.reloadRows(
                    at: [self.magnistraDirectPath(forMessage: index)],
                    with: .none
                )
            }
        }
    }

    func matrixDirectMessage(
        _ timeline:
            MagnistraMatrixTimelineMessage
    ) -> MagnistraDirectMessage {
        let content =
            timeline.content

        let msgtype =
            (
                content[
                    "msgtype"
                ] as? String ??
                ""
            )
            .lowercased()

        let info =
            content[
                "info"
            ] as? [String: Any] ??
            [:]

        let url =
            (content["url"] as? String) ??
            ((content["file"] as? [String: Any])?["url"] as? String)

        let thumbnail =
            (info["thumbnail_url"] as? String) ??
            ((info["thumbnail_file"] as? [String: Any])?["url"] as? String)

        var mediaKind =
            ""

        var previewURL:
            String? =
                nil

        var mediaURL:
            String? =
                nil

        var audioURL:
            String? =
                nil

        let mime = (info["mimetype"] as? String ?? "").lowercased()
        let filename = (content["filename"] as? String ??
                        content["body"] as? String ?? "").lowercased()
        let isSticker = timeline.eventType == "m.sticker" || msgtype == "m.sticker"
        let isGIF = mime.contains("gif") || mime.contains("webp") ||
                    filename.hasSuffix(".gif") || filename.hasSuffix(".webp")

        if msgtype == "m.image" || isSticker || (isGIF && msgtype == "m.file") {
            mediaKind = "photo"
            previewURL = url
            mediaURL = url
        } else if
            msgtype ==
                "m.video"
        {
            mediaKind =
                "video"

            previewURL =
                thumbnail

            mediaURL =
                url
        } else if
            msgtype ==
                "m.audio"
        {
            mediaKind =
                "voice"

            audioURL =
                url

            mediaURL =
                url
        }

        let width =
            (
                info[
                    "w"
                ] as? NSNumber
            )?
            .doubleValue ??
            0.0

        let height =
            (
                info[
                    "h"
                ] as? NSNumber
            )?
            .doubleValue ??
            0.0

        let aspect =
            (
                width >
                    0.0 &&
                height >
                    0.0
            )
                ? width /
                    height
                : 1.0

        let duration =
            (
                info[
                    "duration"
                ] as? NSNumber
            )?
            .doubleValue ??
            0.0

        var waveform:
            [Double] =
                []

        if
            let audioInfo =
                content[
                    "org.matrix.msc1767.audio"
                ] as? [String: Any],
            let values =
                audioInfo[
                    "waveform"
                ] as? [NSNumber]
        {
            waveform =
                values.map {
                    $0.doubleValue
                }
        }

        return
            MagnistraDirectMessage(
                messageID:
                    timeline.eventId,
                text:
                    timeline.text,
                detailText:
                    timeline.detailText,
                previewURL:
                    previewURL,
                contentType:
                    isSticker ? "sticker" :
                        (isGIF && mediaKind == "photo" ? "gif" :
                         (msgtype.isEmpty ? timeline.eventType : msgtype)),
                timestampMilliseconds:
                    timeline.timestampMilliseconds,
                isOutgoing:
                    timeline.isOutgoing,
                audioURL:
                    audioURL,
                audioDurationMilliseconds:
                    duration,
                mediaURL:
                    mediaURL,
                targetURL:
                    nil,
                mediaKind:
                    mediaKind,
                audioWaveform:
                    waveform,
                mediaAspectRatio:
                    aspect,
                senderID:
                    timeline.senderUserId
            )
    }
}
