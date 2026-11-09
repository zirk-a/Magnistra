// Overview: Direct thread: message date headers and profile/member taps.
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


    func magnistraDirectDate(_ milliseconds: Double) -> Date {
        return Date(timeIntervalSince1970: milliseconds / 1000.0)
    }

    func magnistraDirectShowsDate(at index: Int) -> Bool {
        guard index >= 0 && index < messages.count else { return false }
        if index == 0 { return true }
        let current = magnistraDirectDayKeyFormatter.string(from: magnistraDirectDate(messages[index].timestampMilliseconds))
        let previous = magnistraDirectDayKeyFormatter.string(from: magnistraDirectDate(messages[index - 1].timestampMilliseconds))
        return current != previous
    }

func magnistraDirectDecorateVisibleCell(_ cell: UITableViewCell, row: Int) {
        guard row >= 0 && row < messages.count else { return }
        let item = messages[row]
        let text = item.text.lowercased()
        let type = item.contentType.lowercased()
        if magnistraDirectIsMatrix && cell is MagnistraDirectMediaCell &&
           (text == "sticker" || text == "gif" ||
            type.contains("sticker") || type.contains("animated") || type.contains("gif")) {
            if let media = cell as? MagnistraDirectMediaCell {
                media.previewView.isUserInteractionEnabled = true
                let already = (media.previewView.gestureRecognizers ?? [])
                    .contains { $0 is UILongPressGestureRecognizer }
                if !already {
                    let hold = UILongPressGestureRecognizer(target: self,
                        action: #selector(magnistraSaveDirectMedia(_:)))
                    hold.minimumPressDuration = 0.50
                    media.previewView.addGestureRecognizer(hold)
                }
            }
        }

        (cell.viewWithTag(magnistraDirectTimeTag) as? UILabel)?.removeFromSuperview()
        (cell.viewWithTag(magnistraDirectDateTag) as? UILabel)?.removeFromSuperview()
        let amount = magnistraDirectTimestampReveal
        let isOutgoing = messages[row].isOutgoing
        var safeReveal = amount
        if isOutgoing {
            if let bubbleCell = cell as? MagnistraDirectMessageCell {

                let available = max(0.0, bubbleCell.bubbleView.frame.minX - 8.0)
                safeReveal = min(amount, available)
            } else {
                safeReveal = 0.0
            }
        }
        cell.transform = isOutgoing
            ? CGAffineTransform(translationX: -safeReveal, y: 0.0)
            : CGAffineTransform.identity
        if amount > 0.0 {
            let tag = 1300000 + row
            let label: UILabel
            if let existing = tableView.viewWithTag(tag) as? UILabel {
                label = existing
            } else {
                label = UILabel(frame: CGRect.zero)
                label.tag = tag
                label.backgroundColor = UIColor.clear
                label.font = UIFont.systemFont(ofSize: 10.0)
                label.textColor = UIColor(white: 0.46, alpha: 1.0)
                label.textAlignment = .right
                label.isUserInteractionEnabled = false
                tableView.addSubview(label)
            }
            let normalFrame = tableView.rectForRow(at: self.magnistraDirectPath(forMessage: row))
            label.frame = CGRect(x: max(0.0, tableView.bounds.size.width - 60.0),
                                 y: normalFrame.midY - 10.0,
                                 width: 54.0, height: 20.0)
            label.text = magnistraDirectTimeFormatter.string(from:
                magnistraDirectDate(messages[row].timestampMilliseconds))
            label.alpha = min(1.0, amount / 50.0)
            tableView.bringSubviewToFront(label)
        } else {
            (tableView.viewWithTag(1300000 + row) as? UILabel)?.removeFromSuperview()
        }
    }

@objc func magnistraDirectTimestampPullChanged(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: tableView)
        switch recognizer.state {
        case .began, .changed:
            if translation.x <= 0.0 && abs(translation.x) > abs(translation.y) {
                magnistraDirectTimestampReveal = min(62.0, max(0.0, -translation.x))
                for cell in tableView.visibleCells {
                    if let index = tableView.indexPath(for: cell) {
                        magnistraDirectDecorateVisibleCell(cell, row: self.magnistraDirectMessageIndex(index))
                    }
                }
            }
        case .ended, .cancelled, .failed:
            magnistraDirectTimestampReveal = 0.0
            UIView.animate(withDuration: 0.18, animations: { [weak self] in
                guard let owner = self else { return }
                for cell in owner.tableView.visibleCells {
                    if let index = owner.tableView.indexPath(for: cell) {
                        owner.magnistraDirectDecorateVisibleCell(cell, row: owner.magnistraDirectMessageIndex(index))
                    }
                }
            })
        default: break
        }
    }

func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if magnistraDirectDateRowMessageIndex(indexPath) != nil { return }

        magnistraDirectDecorateVisibleCell(cell, row: self.magnistraDirectMessageIndex(indexPath))
    }

    @objc func matrixMembersTapped() {
        guard magnistraDirectIsMatrix else { return }
        let roomId = summary.threadFBID
        guard !roomId.isEmpty else { return }

        let members = MagnistraMatrixRoomParticipantsViewController()
        members.setRoomId(roomId)
        navigationController?.pushViewController(members, animated: true)
    }

    @objc func magnistraDirectProfileTapped() {
        guard !magnistraDirectIsMatrix, !summary.isGroupConversation else { return }
        guard let userID = summary.participantUserIDs.first, !userID.isEmpty else { return }
        let username = summary.username.isEmpty ? summary.title : summary.username
        guard !username.isEmpty else { return }
        let synthetic = MagnistraRealPost(
            mediaID: "", userID: userID, username: username, fullName: username, caption: "",
            commentCount: 0, previewComments: [], likes: 0, location: "", takenAt: 0.0,
            imagePath: "", imageURL: "", imageCacheKey: "direct-profile:" + userID,
            avatarPath: nil, avatarURL: summary.avatarURL, avatarCacheKey: "direct-profile-avatar:" + userID,
            musicTitle: nil, musicArtist: nil, musicAudioURL: nil, musicStartTimeMs: 0,
            photoMusicImageURLFallback: nil, videoURL: nil, videoWidth: 0, videoHeight: 0
        )
        navigationController?.pushViewController(MagnistraProfileViewController(post: synthetic), animated: true)
    }
}
