// Overview: Home feed: video, mute and photo-music button actions.
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

extension HomeViewController {


    @objc func photoMusicStatusTapped(
        _ sender:
            MagnistraVideoGlyphButton
    ) {
        guard
            let post =
                postForMediaID(
                    sender.mediaID
                ),
            post.videoURL == nil,
            post.musicAudioURL != nil
        else {
            return
        }

        let musicPlayer =
            MagnistraPhotoMusicPlayer
                .shared

        if
            musicPlayer.activeMediaID ==
                post.mediaID
        {
            musicPlayer.stop()
            sender.glyphKind = .music
            return
        }

        let previousMediaID =
            musicPlayer.activeMediaID

        MagnistraInlineVideoPlayer
            .shared
            .stop()

        if musicPlayer.start(post: post) {
            sender.glyphKind = .stop
        }

        if let previousMediaID = previousMediaID {
            refreshPhotoMusicControl(
                mediaID:
                    previousMediaID
            )
        }
    }

    @objc func homeMusicCoverHeld(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let sender = gesture.view as? MagnistraPhotoMusicButton,
              let post = postForMediaID(sender.mediaID),
              post.videoURL == nil, post.musicAudioURL != nil,
              let row = posts.firstIndex(where: { $0.mediaID == sender.mediaID }),
              let cell = tableView.cellForRow(
                  at: IndexPath(row: row, section: 0)) as? MagnistraPostCell,
              let image = cell.currentMediaImage()
        else { return }

        let music = MagnistraPhotoMusicPlayer.shared
        let prior = music.activeMediaID
        MagnistraInlineVideoPlayer.shared.stop()
        if prior == post.mediaID {
            if !music.isPlaying { _ = music.toggle(post: post) }
        } else {
            _ = music.start(post: post)
        }
        refreshPhotoMusicControl(mediaID: post.mediaID)
        if let prior = prior, prior != post.mediaID {
            refreshPhotoMusicControl(mediaID: prior)
        }
        _ = MagnistraImageZoomOverlay.present(image: image)
    }

    @objc func photoMusicTapped(
        _ sender:
            MagnistraPhotoMusicButton
    ) {
        guard
            let post =
                postForMediaID(
                    sender.mediaID
                ),
            post.videoURL == nil,
            post.musicAudioURL != nil
        else {
            return
        }

        let previousMediaID =
            MagnistraPhotoMusicPlayer
                .shared
                .activeMediaID

        MagnistraInlineVideoPlayer
            .shared
            .stop()

        _ =
            MagnistraPhotoMusicPlayer
                .shared
                .toggle(
                    post:
                        post
                )

        refreshPhotoMusicControl(
            mediaID:
                post.mediaID
        )

        if
            let previousMediaID = previousMediaID,
            previousMediaID != post.mediaID
        {
            refreshPhotoMusicControl(
                mediaID:
                    previousMediaID
            )
        }
    }

    @objc func videoSurfaceTapped(
        _ sender:
            MagnistraVideoSurfaceButton
    ) {
        let player =
            MagnistraInlineVideoPlayer
                .shared

        if
            player.activeMediaID ==
            sender.mediaID
        {
            _ =
                player.toggle(
                    mediaID:
                        sender.mediaID
                )

            return
        }

        guard
            let host =
                sender.superview
        else {
            return
        }

        _ =
            startVideo(
                mediaID:
                    sender.mediaID,
                hostView:
                    host
            )
    }

    @objc func videoStatusTapped(
        _ sender:
            MagnistraVideoGlyphButton
    ) {
        let player =
            MagnistraInlineVideoPlayer
                .shared

        if
            player.activeMediaID ==
            sender.mediaID
        {
            player.stop()
            return
        }

        guard
            let host =
                sender.superview
        else {
            return
        }

        _ =
            startVideo(
                mediaID:
                    sender.mediaID,
                hostView:
                    host
            )
    }

    @objc func videoMuteTapped(
        _ sender:
            MagnistraVideoGlyphButton
    ) {
        guard
            MagnistraInlineVideoPlayer
                .shared
                .activeMediaID ==
            sender.mediaID
        else {
            return
        }

        if let muted =
            MagnistraInlineVideoPlayer
                .shared
                .toggleMuted()
        {
            sender.glyphKind =
                muted
                    ? .muted
                    : .volume
        }
    }

    @objc func videoFullscreenTapped(
        _ sender:
            MagnistraVideoGlyphButton
    ) {
        guard
            MagnistraInlineVideoPlayer
                .shared
                .activeMediaID ==
            sender.mediaID
        else {
            return
        }

        _ =
            MagnistraInlineVideoPlayer
                .shared
                .enterFullscreen()
    }

    func tableView(
        _ tableView: UITableView,
        didEndDisplaying
            cell: UITableViewCell,
        forRowAt
            indexPath: IndexPath
    ) {

        if let postCell = cell as? MagnistraPostCell {
            postCell.suspendCarouselVideoForScroll()
        }

        if let surface =
            cell.contentView
                .viewWithTag(
                    MagnistraVideoUITags
                        .surface
                )
                as? MagnistraVideoSurfaceButton
        {
            MagnistraInlineVideoPlayer
                .shared
                .suspendForScrollIfMediaID(
                    surface.mediaID
                )
        }
    }

    func scrollViewDidEndDragging(
        _ scrollView:
            UIScrollView,
        willDecelerate
            decelerate:
            Bool
    ) {
        guard
            scrollView ===
                tableView
        else {
            return
        }

        if !decelerate {
            MagnistraInlineVideoPlayer
                .shared
                .scheduleScrollStopFinish()

            MagnistraPhotoMusicPlayer
                .shared
                .scheduleScrollStopFinish()
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView:
            UIScrollView
    ) {
        guard
            scrollView ===
                tableView
        else {
            return
        }

        MagnistraInlineVideoPlayer
            .shared
            .scheduleScrollStopFinish()

        MagnistraPhotoMusicPlayer
            .shared
            .scheduleScrollStopFinish()
    }
}
