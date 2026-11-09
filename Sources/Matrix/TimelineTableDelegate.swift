// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: table view delegate and row heights.
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



extension RoomTimelineVC: UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard indexPath.row < rows.count, case .pending(let message) = rows[indexPath.row] else { return }
        handlePendingTap(message.txnId)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return rowHeight(rows[indexPath.row], width: tableView.bounds.width)
    }

    func rowHeight(_ row: Row, width: CGFloat) -> CGFloat {
        switch row {
        case .date:
            return EventCell.dateRowHeight
        case .receipt:
            return 18
        case .reactions(let reactionRow):
            return ReactionsCell.height(items: reactionRow.items, width: width)
        case .pending(let message):

            let maxBubbleWidth = width * EventCell.bubbleWidthFraction
            let bodyWidth = maxBubbleWidth - EventCell.innerPadding * 2
            let bodyHeight = textHeight(message.body, font: EventCell.bodyFont, width: bodyWidth)
            let quoteBlock: CGFloat = pendingQuote(for: message) != nil
                ? EventCell.quoteHeight + EventCell.quoteGap : 0
            let statusBlock = EventCell.statusHeight + EventCell.statusGap
            let bubbleHeight = quoteBlock + bodyHeight + statusBlock + EventCell.innerPadding * 2

            return EventCell.groupedTopMargin + bubbleHeight + EventCell.bottomMargin
        case .event(let eventRow):
            switch eventRow.event.kind {
            case .message:
                let text = bodyText(for: eventRow)
                let maxBubbleWidth = width * EventCell.bubbleWidthFraction
                let bodyWidth = maxBubbleWidth - EventCell.innerPadding * 2
                let bodyHeight = textHeight(text, font: EventCell.bodyFont, width: bodyWidth)
                let quoteBlock: CGFloat = replyPreview(for: eventRow.event) != nil
                    ? EventCell.quoteHeight + EventCell.quoteGap : 0
                let bubbleHeight = quoteBlock + bodyHeight + EventCell.innerPadding * 2
                let hasMeta = hasMetaHeader(eventRow)
                let metaBlock: CGFloat = hasMeta ? EventCell.metaHeight + EventCell.metaGap : 0
                let topMargin = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
                return topMargin + metaBlock + bubbleHeight + EventCell.bottomMargin
            case .image(_, _, _, let w, let h):
                let maxBubbleWidth = width * EventCell.bubbleWidthFraction
                let imageSize = ImageEventCell.displaySize(imageWidth: w, imageHeight: h, maxWidth: maxBubbleWidth)
                let hasMeta = hasMetaHeader(eventRow)
                let metaBlock: CGFloat = hasMeta ? EventCell.metaHeight + EventCell.metaGap : 0
                let topMargin = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
                return topMargin + metaBlock + imageSize.height + EventCell.bottomMargin
            case .audio:
                let hasMeta = hasMetaHeader(eventRow)
                let metaBlock: CGFloat = hasMeta ? EventCell.metaHeight + EventCell.metaGap : 0
                let topMargin = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
                return topMargin + metaBlock + AudioEventCell.bubbleHeight + EventCell.bottomMargin
            case .file:
                let hasMeta = hasMetaHeader(eventRow)
                let metaBlock: CGFloat = hasMeta ? EventCell.metaHeight + EventCell.metaGap : 0
                let topMargin = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
                return topMargin + metaBlock + FileEventCell.bubbleHeight + EventCell.bottomMargin
            case .video(_, let video):
                let maxBubbleWidth = width * EventCell.bubbleWidthFraction
                let posterSize = ImageEventCell.displaySize(imageWidth: video.width,
                                                            imageHeight: video.height,
                                                            maxWidth: maxBubbleWidth)
                let hasMeta = hasMetaHeader(eventRow)
                let metaBlock: CGFloat = hasMeta ? EventCell.metaHeight + EventCell.metaGap : 0
                let topMargin = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
                return topMargin + metaBlock + posterSize.height + EventCell.bottomMargin
            case .membership:
                return 30
            case .reaction, .redaction, .edit:

                return 0
            }
        }
    }

    func metaText(sender: String, isOwn: Bool, isEmote: Bool) -> String? {
        if isOwn || isEmote { return nil }

        return memberNames[sender] ?? shortName(sender)
    }

    func hasMetaHeader(_ eventRow: EventRow) -> Bool {
        guard eventRow.showMeta else { return false }
        switch eventRow.event.kind {
        case .message(let sender, _, let isEmote):
            return metaText(sender: sender, isOwn: sender == MatrixSession.userId,
                            isEmote: isEmote) != nil
        case .image(let sender, _, _, _, _),
             .audio(let sender, _, _, _),
             .file(let sender, _, _, _, _),
             .video(let sender, _):
            return metaText(sender: sender, isOwn: sender == MatrixSession.userId,
                            isEmote: false) != nil
        case .membership, .reaction, .redaction, .edit:
            return false
        }
    }

    func bodyText(for eventRow: EventRow) -> String {
        guard case .message(let sender, let body, let isEmote) = eventRow.event.kind else { return "" }
        var text = eventRow.editedBody ?? body
        if isEmote { text = "* \(memberNames[sender] ?? shortName(sender)) \(text)" }
        if eventRow.editedBody != nil { text += " (edited)" }
        return text
    }

    func replyPreview(for event: RoomEvent) -> String? {
        guard let target = event.replyTo else { return nil }
        if let source = eventsById[target], let sender = RoomTimelineVC.senderOf(source),
           let text = RoomTimelineVC.previewText(for: source) {
            let name = memberNames[sender] ?? shortName(sender)
            return "\(name): \(text)"
        }
        guard let quote = event.replyQuote else { return nil }
        if let author = event.replyAuthor {
            return "\(memberNames[author] ?? shortName(author)): \(quote)"
        }
        return quote
    }

    func pendingQuote(for message: PendingMessage) -> String? {
        guard let target = message.replyTo, let source = eventsById[target],
              let sender = RoomTimelineVC.senderOf(source),
              let text = RoomTimelineVC.previewText(for: source) else { return nil }
        return "\(memberNames[sender] ?? shortName(sender)): \(text)"
    }

    static func previewText(for event: RoomEvent) -> String? {
        switch event.kind {
        case .message(_, let body, _): return body
        case .image(_, let caption, _, _, _):
            if caption == "__magnistra_sticker__" { return "Sticker" }
            if caption == "__magnistra_gif__"
                || caption == "__magnistra_whatsapp_webp__" { return "GIF" }
            return "Photo"
        case .audio: return "Voice message"
        case .file(_, _, let filename, _, _): return filename
        case .video: return "Video"
        default: return nil
        }
    }

    func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        return ceil(EventCell.measureBody(text, font: font, width: width).height)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case .date(let text):
            let cell = tableView.dequeueReusableCell(withIdentifier: dateCellId) ??
                UITableViewCell(style: .default, reuseIdentifier: dateCellId)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.textLabel?.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 12)
            cell.textLabel?.textColor = .gray
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.text = text
            return cell

        case .receipt(let text):
            let cell = tableView.dequeueReusableCell(withIdentifier: "ReceiptCell") ??
                UITableViewCell(style: .default, reuseIdentifier: "ReceiptCell")
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.textLabel?.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.textLabel?.font = UIFont.systemFont(ofSize: 11)
            cell.textLabel?.textColor = .gray
            cell.textLabel?.textAlignment = .right

            cell.textLabel?.text = text + "   "
            return cell

        case .reactions(let reactionRow):
            let cell = (tableView.dequeueReusableCell(withIdentifier: reactionsCellId) as? ReactionsCell) ??
                ReactionsCell(style: .default, reuseIdentifier: reactionsCellId)
            cell.configure(items: reactionRow.items, isOwn: reactionRow.isOwn)
            cell.setRevealOffset(revealOffset)
            let target = reactionRow.targetEventId
            cell.onTapKey = { [weak self] key in self?.toggleReaction(target: target, key: key) }
            return cell

        case .pending(let message):
            let cell = (tableView.dequeueReusableCell(withIdentifier: cellId) as? EventCell) ??
                EventCell(style: .default, reuseIdentifier: cellId)
            let failed = message.state == .failed
            cell.configure(meta: nil, quote: pendingQuote(for: message), body: message.body,
                           time: TimeFormat.shortTime(msSinceEpoch: Double(message.timestamp)),
                           isOwn: true, avatarMxc: nil, senderName: "",
                           status: failed ? "Not sent \u{2014} tap to retry" : "Sending\u{2026}",
                           statusIsError: failed)
            cell.setRevealOffset(revealOffset)
            return cell

        case .event(let eventRow):
            switch eventRow.event.kind {
            case .message(let sender, _, let isEmote):
                let cell = (tableView.dequeueReusableCell(withIdentifier: cellId) as? EventCell) ??
                    EventCell(style: .default, reuseIdentifier: cellId)
                let isOwn = sender == MatrixSession.userId
                let time = TimeFormat.shortTime(msSinceEpoch: eventRow.event.timestamp)
                let meta = eventRow.showMeta
                    ? metaText(sender: sender, isOwn: isOwn, isEmote: isEmote)
                    : nil
                cell.configure(meta: meta, quote: replyPreview(for: eventRow.event),
                               body: bodyText(for: eventRow), time: time, isOwn: isOwn,
                               avatarMxc: memberAvatars[sender], senderName: memberNames[sender] ?? sender)
                cell.setRevealOffset(revealOffset)
                return cell

            case .image(let sender, let caption, let mxc, let w, let h):
                let cell = (tableView.dequeueReusableCell(withIdentifier: imageCellId) as? ImageEventCell) ??
                    ImageEventCell(style: .default, reuseIdentifier: imageCellId)
                let isOwn = sender == MatrixSession.userId
                let isCompactSticker = caption == "__magnistra_sticker__"
                let isVideoBackedAnimated = caption == "__magnistra_whatsapp_webp__"

                let usesStickerRenderer = isCompactSticker || isVideoBackedAnimated
                let inlineAnimated = usesStickerRenderer || caption == "__magnistra_gif__"
                let time = TimeFormat.shortTime(msSinceEpoch: eventRow.event.timestamp)
                let meta = eventRow.showMeta ? metaText(sender: sender, isOwn: isOwn, isEmote: false) : nil
                cell.configure(meta: meta, mxc: mxc, imageWidth: w, imageHeight: h,
                               isSticker: usesStickerRenderer, isTrueSticker: isCompactSticker,
                               inlineAnimated: inlineAnimated,
                               time: time, isOwn: isOwn,
                               avatarMxc: memberAvatars[sender], senderName: memberNames[sender] ?? sender)
                cell.setRevealOffset(revealOffset)
                cell.onMediaVisualReady = inlineAnimated ? makeMediaBottomAnchorCallback() : nil
                cell.onTap = { [weak self, weak cell] in
                    if isCompactSticker {

                        self?.openStickerViewer(
                            mxc: mxc,
                            placeholder: cell?.displayedImage,
                            saveWidth: w,
                            saveHeight: h,
                            saveSemanticGIF: false
                        )
                    } else if isVideoBackedAnimated {
                        self?.openStickerViewer(
                            mxc: mxc,
                            placeholder: cell?.displayedImage,
                            saveWidth: w,
                            saveHeight: h,
                            saveSemanticGIF: true
                        )
                    } else {
                        self?.openImageViewer(mxc: mxc, placeholder: cell?.displayedImage)
                    }
                }
                return cell

            case .audio(let sender, let mxc, let durationMs, _):
                let cell = (tableView.dequeueReusableCell(withIdentifier: audioCellId) as? AudioEventCell) ??
                    AudioEventCell(style: .default, reuseIdentifier: audioCellId)
                let isOwn = sender == MatrixSession.userId
                let time = TimeFormat.shortTime(msSinceEpoch: eventRow.event.timestamp)
                let meta = eventRow.showMeta ? metaText(sender: sender, isOwn: isOwn, isEmote: false) : nil
                cell.configure(meta: meta, mxc: mxc, durationMs: durationMs, time: time, isOwn: isOwn,
                               avatarMxc: memberAvatars[sender], senderName: memberNames[sender] ?? sender)
                cell.setRevealOffset(revealOffset)
                cell.onPlayTap = { [weak self] in self?.toggleAudio(mxc: mxc, durationMs: durationMs) }

                let playing = (playingAudioMxc == mxc) && (audioPlayer?.isPlaying ?? false)
                cell.setPlaybackState(playing: playing,
                                      currentTime: playing ? (audioPlayer?.currentTime ?? 0) : 0,
                                      duration: audioPlayer?.duration ?? (Double(durationMs) / 1000.0))
                return cell

            case .file(let sender, let mxc, let filename, let mimeType, let sizeBytes):
                let cell = (tableView.dequeueReusableCell(withIdentifier: fileCellId) as? FileEventCell) ??
                    FileEventCell(style: .default, reuseIdentifier: fileCellId)
                let isOwn = sender == MatrixSession.userId
                let time = TimeFormat.shortTime(msSinceEpoch: eventRow.event.timestamp)
                let meta = eventRow.showMeta ? metaText(sender: sender, isOwn: isOwn, isEmote: false) : nil
                let downloaded = MediaCache.shared.downloadedFilePath(mxc: mxc, filename: filename,
                                                                      mimeType: mimeType) != nil
                cell.configure(meta: meta, mxc: mxc, filename: filename, mimeType: mimeType,
                               sizeBytes: sizeBytes, downloaded: downloaded, time: time, isOwn: isOwn,
                               avatarMxc: memberAvatars[sender], senderName: memberNames[sender] ?? sender)

                cell.setProgress(fileProgress[mxc])
                cell.setRevealOffset(revealOffset)
                cell.onTap = { [weak self] in
                    self?.handleFileTap(mxc: mxc, filename: filename, mimeType: mimeType)
                }
                return cell

            case .video(let sender, let video):
                let cell = (tableView.dequeueReusableCell(withIdentifier: videoCellId) as? VideoEventCell) ??
                    VideoEventCell(style: .default, reuseIdentifier: videoCellId)
                let isOwn = sender == MatrixSession.userId
                let time = TimeFormat.shortTime(msSinceEpoch: eventRow.event.timestamp)
                let meta = eventRow.showMeta ? metaText(sender: sender, isOwn: isOwn, isEmote: false) : nil
                let downloaded = MediaCache.shared.downloadedFilePath(mxc: video.mxc, filename: video.filename,
                                                                      mimeType: video.mimeType) != nil
                cell.configure(meta: meta, video: video, downloaded: downloaded, time: time, isOwn: isOwn,
                               avatarMxc: memberAvatars[sender], senderName: memberNames[sender] ?? sender)

                cell.setProgress(fileProgress[video.mxc])
                cell.setRevealOffset(revealOffset)
                cell.onTap = { [weak self] in
                    self?.handleFileTap(mxc: video.mxc, filename: video.filename,
                                        mimeType: video.mimeType, animatedVideo: video.isAnimated)
                }
                return cell

            case .membership(let description):
                let cell = tableView.dequeueReusableCell(withIdentifier: membershipCellId) ??
                    UITableViewCell(style: .default, reuseIdentifier: membershipCellId)
                cell.backgroundColor = .clear
                cell.contentView.backgroundColor = .clear
                cell.textLabel?.backgroundColor = .clear
                cell.selectionStyle = .none
                cell.textLabel?.font = UIFont.italicSystemFont(ofSize: 13)
                cell.textLabel?.textColor = .gray
                cell.textLabel?.textAlignment = .center
                cell.textLabel?.text = description
                return cell

            case .reaction, .redaction, .edit:

                return UITableViewCell(style: .default, reuseIdentifier: nil)
            }
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            loadBackfill()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }
}