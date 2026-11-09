// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: backfill, sync handling, members and read receipts.
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


    func loadBackfill() {
        guard !reachedHistoryStart, !isLoadingBackfill else {
            keepInitialBackfillAtBottom = false
            markInitialLoadDone()
            return
        }

        let from = backfillFrom ?? room.prevBatch
        isLoadingBackfill = true
        setBackfillSpinner(active: true)
        var path = "/_matrix/client/v3/rooms/\(room.roomId)/messages?dir=b&limit=30"
        if let from = from { path += "&from=\(from)" }
        client.get(path) { [weak self] json, error in
            guard let self = self else { return }

            MatrixE2EEManager.shared.beginRoomContext(self.room.roomId)
            defer { MatrixE2EEManager.shared.endRoomContext(self.room.roomId) }
            self.isLoadingBackfill = false
            let keepBottomAfterInitialPrepend = self.keepInitialBackfillAtBottom
            self.keepInitialBackfillAtBottom = false
            defer { self.setBackfillSpinner(active: false) }
            defer { self.markInitialLoadDone() }
            guard let json = json else { return }

            if let end = json["end"] as? String {
                self.backfillFrom = end
            } else {
                self.reachedHistoryStart = true
            }
            guard let chunk = json["chunk"] as? [[String: Any]] else { return }
            if chunk.isEmpty { self.reachedHistoryStart = true; return }

            let parsed = chunk.reversed().compactMap { RoomEvent.parse($0) }
            let newOnes = parsed.filter { !self.seenEventIds.contains($0.eventId) }
            guard !newOnes.isEmpty else { return }
            newOnes.forEach { self.seenEventIds.insert($0.eventId) }
            let wasEmpty = self.events.isEmpty
            self.events.insert(contentsOf: newOnes, at: 0)
            DispatchQueue.main.async {
                if wasEmpty || keepBottomAfterInitialPrepend {
                    self.reloadTable()
                    self.scrollToBottom(animated: false)
                } else {

                    let oldContentHeight = self.tableView.contentSize.height
                    let oldOffsetY = self.tableView.contentOffset.y
                    self.reloadTable()
                    self.tableView.layoutIfNeeded()
                    let newContentHeight = self.tableView.contentSize.height
                    self.tableView.contentOffset = CGPoint(x: 0, y: oldOffsetY + (newContentHeight - oldContentHeight))
                }
            }
        }
    }

    func markInitialLoadDone() {
        guard !hasLoadedInitial else { return }
        hasLoadedInitial = true
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusLabel()
        }
    }

    func updateStatusLabel() {
        statusLabel.isHidden = !(events.isEmpty && hasLoadedInitial)
    }

    func handleSync(_ json: [String: Any]) {

        guard let rooms = json["rooms"] as? [String: Any],
              let join = rooms["join"] as? [String: Any],
              let roomJSON = join[room.roomId] as? [String: Any] else { return }

        if let state = roomJSON["state"] as? [String: Any],
           let stateEvents = state["events"] as? [[String: Any]] {
            updateMembers(from: stateEvents)
        }

        var newOnes: [RoomEvent] = []
        if let timeline = roomJSON["timeline"] as? [String: Any],
           let rawEvents = timeline["events"] as? [[String: Any]] {
            updateMembers(from: rawEvents)
            let parsed = rawEvents.compactMap { RoomEvent.parse($0) }
            newOnes = parsed.filter { !seenEventIds.contains($0.eventId) }
            newOnes.forEach { seenEventIds.insert($0.eventId) }
            events.append(contentsOf: newOnes)
        }

        var typingChanged = false
        var receiptsChanged = false
        if let ephemeral = roomJSON["ephemeral"] as? [String: Any],
           let ephEvents = ephemeral["events"] as? [[String: Any]] {
            for ev in ephEvents {
                guard let type = ev["type"] as? String,
                      let content = ev["content"] as? [String: Any] else { continue }
                if type == "m.typing" {
                    let ids = (content["user_ids"] as? [String]) ?? []
                    let others = ids.filter { $0 != MatrixSession.userId }
                    if others != typingUsers { typingUsers = others; typingChanged = true }
                } else if type == "m.receipt" {
                    if applyReceipts(content) { receiptsChanged = true }
                }
            }
        }

        let tableChanged = !newOnes.isEmpty || receiptsChanged

        let hasNewMessages = newOnes.contains { event in
            switch event.kind {
            case .reaction, .redaction, .edit: return false
            default: return true
            }
        }
        if tableChanged || typingChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if !newOnes.isEmpty { self.retirePending(matching: newOnes) }
                if tableChanged {
                    self.reloadTable()
                    self.updateStatusLabel()
                    if hasNewMessages { self.scrollToBottom(animated: true) }
                }
                if typingChanged { self.updateTypingIndicator() }
            }
        }
        if hasNewMessages, let latest = events.last(where: { event in
            switch event.kind {
            case .reaction, .redaction, .edit: return false
            default: return true
            }
        }) {
            sendReadReceipt(for: latest.eventId)
        }
    }

    func updateMembers(from events: [[String: Any]]) {
        for ev in events where ev["type"] as? String == "m.room.member" {
            guard let content = ev["content"] as? [String: Any],
                  content["membership"] as? String == "join" else { continue }
            let userId = (ev["state_key"] as? String) ?? (ev["sender"] as? String)
            guard let userId = userId else { continue }
            if let dn = content["displayname"] as? String, !dn.isEmpty {
                memberNames[userId] = dn
            }
            if let av = content["avatar_url"] as? String, av.hasPrefix("mxc://") {
                memberAvatars[userId] = av
            }
        }
    }

    func applyReceipts(_ content: [String: Any]) -> Bool {
        var changed = false
        for (eventId, raw) in content {
            guard let data = raw as? [String: Any],
                  let read = data["m.read"] as? [String: Any] else { continue }
            for userId in read.keys where userId != MatrixSession.userId {
                if othersReadEventIds.insert(eventId).inserted { changed = true }
            }
        }
        return changed
    }

    func rebuildRows() {
        var result: [Row] = []
        var lastDayKey: String?
        var prevEvent: RoomEvent?

        let selfUserId = MatrixSession.userId

        var redacted = Set<String>()
        var byId: [String: RoomEvent] = [:]
        var editEvents: [RoomEvent] = []
        var reactionEvents: [RoomEvent] = []
        var bundledEvents: [RoomEvent] = []

        var seenEventId: String?
        var mediaToPrefetch: [(mxc: String, w: Int, h: Int)] = []
        for event in events {
            byId[event.eventId] = event
            if !event.bundledReactions.isEmpty { bundledEvents.append(event) }
            switch event.kind {
            case .redaction(let target):
                redacted.insert(target)
            case .edit:
                editEvents.append(event)
            case .reaction:
                reactionEvents.append(event)
            case .image(let sender, _, let mxc, let w, let h):
                mediaToPrefetch.append((mxc, w, h))
                if sender == selfUserId && othersReadEventIds.contains(event.eventId) {
                    seenEventId = event.eventId
                }
            case .video(let sender, let video):

                if let thumb = video.thumbnailMxc {
                    mediaToPrefetch.append((thumb, video.width, video.height))
                }
                if sender == selfUserId && othersReadEventIds.contains(event.eventId) {
                    seenEventId = event.eventId
                }
            case .message(let sender, _, _), .audio(let sender, _, _, _),
                 .file(let sender, _, _, _, _):
                if sender == selfUserId && othersReadEventIds.contains(event.eventId) {
                    seenEventId = event.eventId
                }
            case .membership:
                break
            }
        }
        eventsById = byId
        prefetchRequests = mediaToPrefetch

        var edits: [String: (timestamp: Double, body: String)] = [:]
        for event in editEvents {
            guard case .edit(let sender, let target, let body) = event.kind,
                  !redacted.contains(event.eventId),
                  let original = byId[target],
                  RoomTimelineVC.senderOf(original) == sender else { continue }
            if let existing = edits[target], existing.timestamp >= event.timestamp { continue }
            edits[target] = (event.timestamp, body)
        }

        var keyOrder: [String: [String]] = [:]
        var keyCounts: [String: [String: Int]] = [:]
        var mine: [String: [String: String]] = [:]

        var redactedCounts: [String: [String: Int]] = [:]
        for event in reactionEvents {
            guard case .reaction(let sender, let target, let key) = event.kind else { continue }
            if redacted.contains(event.eventId) {
                redactedCounts[target, default: [:]][key, default: 0] += 1
                continue
            }
            if keyCounts[target]?[key] == nil {
                keyOrder[target] = (keyOrder[target] ?? []) + [key]
            }
            keyCounts[target, default: [:]][key, default: 0] += 1
            if sender == selfUserId {
                mine[target, default: [:]][key] = event.eventId
            }
        }
        myReactions = mine

        for event in bundledEvents {
            let target = event.eventId
            for bundled in event.bundledReactions {
                let live = keyCounts[target]?[bundled.key] ?? 0
                let adjusted = max(0, bundled.count - (redactedCounts[target]?[bundled.key] ?? 0))
                let merged = max(live, adjusted)
                guard merged > 0 else { continue }
                if keyCounts[target]?[bundled.key] == nil {
                    keyOrder[target] = (keyOrder[target] ?? []) + [bundled.key]
                }
                keyCounts[target, default: [:]][bundled.key] = merged
            }
        }

        for event in events {

            switch event.kind {
            case .reaction, .redaction, .edit: continue
            default: break
            }

            if redacted.contains(event.eventId) { continue }
            var dayChanged = false
            if event.timestamp > 0 {
                let key = TimeFormat.dayKey(msSinceEpoch: event.timestamp)
                if key != lastDayKey {
                    result.append(.date(TimeFormat.dateHeader(msSinceEpoch: event.timestamp)))
                    lastDayKey = key
                    dayChanged = true
                }
            }
            var showMeta = false
            if let sender = RoomTimelineVC.senderOf(event) {
                if dayChanged {
                    showMeta = true
                } else if let prev = prevEvent, let prevSender = RoomTimelineVC.senderOf(prev) {
                    showMeta = sender != prevSender
                        || (event.timestamp - prev.timestamp) > EventCell.groupingWindowMs
                } else {
                    showMeta = true
                }
            }
            result.append(.event(EventRow(event: event, showMeta: showMeta,
                                          editedBody: edits[event.eventId]?.body)))
            if let keys = keyOrder[event.eventId] {
                let items = keys.map {
                    ReactionItem(key: $0,
                                 count: keyCounts[event.eventId]?[$0] ?? 0,
                                 mineEventId: mine[event.eventId]?[$0])
                }
                result.append(.reactions(ReactionRow(targetEventId: event.eventId, items: items,
                                                     isOwn: RoomTimelineVC.senderOf(event) == MatrixSession.userId)))
            }
            if event.eventId == seenEventId {
                result.append(.receipt("Seen"))
            }
            prevEvent = event
        }

        for message in pending {
            let ts = Double(message.timestamp)
            let key = TimeFormat.dayKey(msSinceEpoch: ts)
            if key != lastDayKey {
                result.append(.date(TimeFormat.dateHeader(msSinceEpoch: ts)))
                lastDayKey = key
            }
            result.append(.pending(message))
        }
        rows = result
    }

    static func senderOf(_ event: RoomEvent) -> String? {
        switch event.kind {
        case .message(let sender, _, _): return sender
        case .image(let sender, _, _, _, _): return sender
        case .audio(let sender, _, _, _): return sender
        case .file(let sender, _, _, _, _): return sender
        case .video(let sender, _): return sender

        case .membership, .reaction, .redaction, .edit: return nil
        }
    }

    func reloadTable() {
        rebuildRows()
        tableView.reloadData()
        prefetchImageThumbnails()
    }

    func updateTypingIndicator() {
        typingLabel.text = typingText()
        UIView.animate(withDuration: 0.2) { self.layoutInputBar() }
    }

    func typingText() -> String {
        let names = typingUsers.map { memberNames[$0] ?? shortName($0) }
        switch names.count {
        case 0: return ""
        case 1: return "\(names[0]) is typing\u{2026}"
        case 2: return "\(names[0]) and \(names[1]) are typing\u{2026}"
        default: return "Several people are typing\u{2026}"
        }
    }

    func shortName(_ userId: String) -> String {
        var s = userId
        if s.hasPrefix("@") { s = String(s.dropFirst()) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return s.isEmpty ? userId : s
    }

    func prefetchImageThumbnails() {
        for req in prefetchRequests {
            guard !prefetchedMxcs.contains(req.mxc) else { continue }
            prefetchedMxcs.insert(req.mxc)
            let (reqW, reqH) = ImageEventCell.thumbnailRequestSize(imageWidth: req.w, imageHeight: req.h)
            MediaCache.shared.loadThumbnail(mxc: req.mxc, width: reqW, height: reqH) { _ in }
        }
    }

    func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else { return }

        tableView.layoutIfNeeded()
        let maxOffsetY = tableView.contentSize.height - tableView.bounds.height + tableView.contentInset.bottom
        let y = max(-tableView.contentInset.top, maxOffsetY)
        tableView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    func makeMediaBottomAnchorCallback() -> (() -> Void)? {
        tableView.layoutIfNeeded()
        let capturedOffsetY = tableView.contentOffset.y
        let capturedMaxY = tableView.contentSize.height - tableView.bounds.height
            + tableView.contentInset.bottom
        let bottomDistance = max(0, capturedMaxY - capturedOffsetY)
        guard bottomDistance <= 120 else { return nil }

        return { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.tableView.isDragging || self.tableView.isDecelerating || self.tableView.isTracking {
                    return
                }
                let movement = abs(self.tableView.contentOffset.y - capturedOffsetY)
                guard movement <= 32 else { return }
                self.tableView.layoutIfNeeded()
                self.scrollToBottom(animated: false)
            }
        }
    }
}
