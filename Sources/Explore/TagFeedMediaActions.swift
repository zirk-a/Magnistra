// Overview: Tag feed: video, mute, fullscreen and photo-music button actions.
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

extension MagnistraExploreTagFeedViewController {


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
                hostView: host
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
            refreshVideoControls(
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
                hostView: host
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

    @objc func photoMusicPhotoButtonTapped(
        _ sender:
            MagnistraExplorePhotoMusicTapButton
    ) {
        photoMusicPhotoTapped(
            mediaID:
                sender.mediaID
        )
    }

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

        if let previousMediaID =
            previousMediaID
        {
            refreshPhotoMusicControl(
                mediaID:
                    previousMediaID
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

        if !decelerate {
            resumeVisibleDeferredPhotoLoads()
        }

        if !decelerate {
            resumeIncrementalPaginationAfterScroll()
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

        resumeVisibleDeferredPhotoLoads()

        resumeIncrementalPaginationAfterScroll()
}

    func resumeVisibleDeferredPhotoLoads() {
        MagnistraDecodedImageLoader
            .shared
            .setPostImageLoadsSuspended(
                false
            )

        for case let cell as MagnistraPostCell
            in tableView.visibleCells
        {
            cell.resumeDeferredPhotoLoadIfNeeded()
        }
    }

    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {
        MagnistraDecodedImageLoader
            .shared
            .setPostImageLoadsSuspended(
                true
            )

    }
}
