// Overview: Direct thread: table view data source and delegate (rows, heights, relative day titles).
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


func numberOfSections(in tableView: UITableView) -> Int {
        return messages.isEmpty ? 0 : 1
    }

func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section == 0 && !messages.isEmpty else { return 0 }
        return messages.count + magnistraDirectDaySectionStarts().count
    }

    func tableView(
        _ tableView:
            UITableView,
        cellForRowAt
            indexPath:
                IndexPath
    ) -> UITableViewCell {

        tableView.separatorStyle = .none
        tableView.separatorColor = UIColor.clear

        if let dateMessageIndex = magnistraDirectDateRowMessageIndex(indexPath) {
            let identifier = "MagnistraDirectDateInlineRow"
            let dateCell = tableView.dequeueReusableCell(withIdentifier: identifier)
                ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
            dateCell.selectionStyle = .none
            dateCell.backgroundColor = tableView.backgroundColor
            dateCell.contentView.backgroundColor = tableView.backgroundColor
            dateCell.transform = CGAffineTransform.identity
            let dateLabel: UILabel
            if let existing = dateCell.contentView.viewWithTag(915807) as? UILabel {
                dateLabel = existing
            } else {
                let label = UILabel(frame: CGRect.zero)
                label.tag = 915807
                label.backgroundColor = UIColor.clear
                label.textColor = UIColor(white: 0.48, alpha: 1.0)
                label.font = UIFont.systemFont(ofSize: 11.0)
                label.textAlignment = .center
                label.isUserInteractionEnabled = false
                dateCell.contentView.addSubview(label)
                dateLabel = label
            }
            dateLabel.frame = CGRect(x: 8, y: 4,
                width: max(1, tableView.bounds.size.width - 16), height: 24)
            let firstMessage = messages[dateMessageIndex]
            dateLabel.text = magnistraDirectRelativeDayTitle(
                magnistraDirectDate(firstMessage.timestampMilliseconds))
            return dateCell
        }

        let message =
            messages[
                self.magnistraDirectMessageIndex(indexPath)
            ]

        let kind =
            magnistraDirectRenderKind(
                message
            )
        if !magnistraDirectIsMatrix {
            MagnistraDirectMediaTrace.record("CELL_RENDER", id: message.messageID,
                info: "render=" + String(describing: kind) +
                      ";preview=" + MagnistraDirectMediaTrace.urlTag(message.previewURL))
        }

        let cell:
            MagnistraDirectMessageCell

        switch kind {
        case .text:
            let id = "MagnistraDirectTextCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectTextCell
                ) ??
                MagnistraDirectTextCell(
                    style: .default,
                    reuseIdentifier: id
                )

        case .unsupported:
            let id = "MagnistraDirectUnsupportedCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectUnsupportedCell
                ) ??
                MagnistraDirectUnsupportedCell(
                    style: .default,
                    reuseIdentifier: id
                )

        case .photo:
            let isAnimatedWebMedia = message.previewURL != nil &&
                (message.contentType.lowercased().contains("animated") ||
                 message.contentType.lowercased() == "sticker" ||
                 message.contentType.lowercased() == "gif")

            let id = isAnimatedWebMedia
                ? "MagnistraDirectAnimatedMediaCell" : "MagnistraDirectPhotoCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectPhotoCell
                ) ??
                MagnistraDirectPhotoCell(
                    style: .default,
                    reuseIdentifier: id
                )

        case .video:
            let id = "MagnistraDirectVideoCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectVideoCell
                ) ??
                MagnistraDirectVideoCell(
                    style: .default,
                    reuseIdentifier: id
                )

        case .voice:
            let id = "MagnistraDirectVoiceCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectVoiceCell
                ) ??
                MagnistraDirectVoiceCell(
                    style: .default,
                    reuseIdentifier: id
                )

        case .sharedPost:
            let id = "MagnistraDirectSharedPostCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectSharedPostCell
                ) ??
                MagnistraDirectSharedPostCell(
                    style: .default,
                    reuseIdentifier: id
                )

        case .sharedReel:
            let id = "MagnistraDirectSharedReelCell"
            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier: id
                        ) as?
                        MagnistraDirectSharedReelCell
                ) ??
                MagnistraDirectSharedReelCell(
                    style: .default,
                    reuseIdentifier: id
                )
        }

        if let previewCell = cell as? MagnistraDirectPreviewCell {
            previewCell.chatThumbnailCache = chatThumbnailCache
        }
        cell.configure(message)
        cell.setSenderHeader(matrixSenderNameForMessage(
            self.magnistraDirectMessageIndex(indexPath)))

        cell.backgroundColor = tableView.backgroundColor
        cell.contentView.backgroundColor = UIColor.clear
        cell.layer.borderWidth = 0.0

        if
            message.messageID ==
                directAudioMessageID,
            let player =
                directAudioPlayer,
            let voiceCell =
                cell as?
                    MagnistraDirectVoiceCell
        {
            let duration =
                max(
                    0.001,
                    player.duration
                )

            voiceCell.setPlayback(
                progress:
                    max(
                        0.0,
                        min(
                            1.0,
                            player.currentTime /
                            duration
                        )
                    ),
                elapsedMilliseconds:
                    player.currentTime *
                    1000.0,
                playing:
                    player.isPlaying
            )
        }

        return cell
    }

    func tableView(
        _ tableView:
            UITableView,
        didSelectRowAt
            indexPath:
                IndexPath
    ) {
        if magnistraDirectDateRowMessageIndex(indexPath) != nil {
            tableView.deselectRow(at: indexPath, animated: false)
            return
        }

        if
            usesMatrixBackend,
            self.magnistraDirectMessageIndex(indexPath) >= 0,
            self.magnistraDirectMessageIndex(indexPath) < messages.count
        {
            let message = messages[self.magnistraDirectMessageIndex(indexPath)]

            if message.audioURL != nil || message.mediaKind == "voice" {
                tableView.deselectRow(at: indexPath, animated: true)
                playMatrixVoice(message)
                return
            }

            if message.mediaKind == "video" {
                tableView.deselectRow(at: indexPath, animated: true)
                openMatrixVideo(message)
                return
            }

            if message.mediaKind == "photo" {
                tableView.deselectRow(at: indexPath, animated: true)
                openMatrixPhoto(message)
                return
            }
        }

        tableView.deselectRow(
            at: indexPath,
            animated: true
        )

        guard
            self.magnistraDirectMessageIndex(indexPath) >= 0,
            self.magnistraDirectMessageIndex(indexPath) <
                messages.count
        else {
            return
        }

        let message =
            messages[
                self.magnistraDirectMessageIndex(indexPath)
            ]

        switch
            magnistraDirectRenderKind(
                message
            )
        {
        case .voice:
            playDirectVoiceMessage(
                message
            )

        case .photo:
            if !magnistraDirectIsMatrix && message.previewURL != nil &&
               (message.contentType.lowercased().contains("animated") ||
                message.contentType.lowercased() == "sticker" ||
                message.contentType.lowercased() == "gif") {

                break
            }
            openDirectPhoto(
                message
            )

        case .video:
            openDirectVideo(
                message
            )

        case .sharedPost,
             .sharedReel:
            openDirectSharedTarget(
                message
            )

        case .text:
            if let link = matrixInstagramLink(in: message.text) {
                openDirectSharedLink(link)
            }
        case .unsupported:
            break
        }
    }

    func tableView(
        _ tableView:
            UITableView,
        magnistraDirectBaseHeightForRowAt
            indexPath:
                IndexPath
    ) -> CGFloat {
        let message =
            messages[
                self.magnistraDirectMessageIndex(indexPath)
            ]

        switch
            magnistraDirectRenderKind(
                message
            )
        {
        case .text,
             .unsupported:
            return
                MagnistraDirectTextCell
                    .rowHeight(
                        for: message,
                        width:
                            tableView.bounds.size.width
                    )

        case .photo,
             .video:
            return
                MagnistraDirectMediaCell
                    .rowHeight(
                        for: message,
                        width:
                            tableView.bounds.size.width
                    )

        case .voice:
            return
                MagnistraDirectVoiceCell
                    .rowHeight()

        case .sharedPost,
             .sharedReel:
            return
                MagnistraDirectSharedCell
                    .rowHeight(
                        for: message,
                        width:
                            tableView.bounds.size.width
                    )
        }
    }

func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.0
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let empty = UIView(frame: CGRect.zero)
        empty.backgroundColor = tableView.backgroundColor
        return empty
    }

func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.0
    }

    func magnistraDirectRelativeDayTitle(_ date: Date) -> String {
        let now = Date()
        let formatter = magnistraDirectDayKeyFormatter
        let day = formatter.date(from: formatter.string(from: date)) ?? date
        let today = formatter.date(from: formatter.string(from: now)) ?? now
        let elapsed = max(0.0, today.timeIntervalSince1970 - day.timeIntervalSince1970)
        let days = Int((elapsed / 86400.0).rounded())
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        let weeks = max(1, days / 7)
        return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
    }

func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let width = tableView.bounds.size.width
        let gifVersion = MagnistraDirectMediaCell.magnistraDirectGIFGeometryVersion
        if observedGIFGeometryVersion != gifVersion {
            observedGIFGeometryVersion = gifVersion
            cachedRowHeights.removeAll(keepingCapacity: true)
        }
        if cachedRowWidth != width {
            cachedRowWidth = width
            cachedRowHeights.removeAll(keepingCapacity: true)
        }
        if let height = cachedRowHeights[indexPath] {
            return height
        }
        let height = uncachedRowHeight(tableView, at: indexPath)
        cachedRowHeights[indexPath] = height
        return height
    }

    func uncachedRowHeight(_ tableView: UITableView, at indexPath: IndexPath) -> CGFloat {
        if magnistraDirectDateRowMessageIndex(indexPath) != nil { return 32.0 }

        let originalHeight = self.tableView(tableView, magnistraDirectBaseHeightForRowAt: indexPath)
        let messageIndex = magnistraDirectMessageIndex(indexPath)
        let nameInset: CGFloat = matrixSenderNameForMessage(messageIndex) == nil ? 0.0 : 18.0
        return max(1.0, originalHeight - 4.0) + nameInset

    }
}
