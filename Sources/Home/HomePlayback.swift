// Overview: Home feed: video playback and scroll handling.
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


    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        unifiedLoadingBand.refresh()
        postHeaderScroll.observe(
            scrollView,
            initialContentReady: !posts.isEmpty
        )
        MagnistraInlineVideoPlayer
            .shared
            .cancelScheduledScrollStopFinish()

        MagnistraPhotoMusicPlayer
            .shared
            .cancelScheduledScrollStopFinish()

        stopActiveVideoIfNeededForScroll()

        stopActivePhotoMusicIfNeededForScroll()

        if
            posts.isEmpty ||
            isLoadingPage ||
            reachedEnd
        {
            return
        }

        let remaining =
            scrollView.contentSize.height -
            (
                scrollView.contentOffset.y +
                scrollView.bounds.size.height
            )

        if remaining < 700.0 &&
            magnistraUserInitiatedPagination(scrollView) {
            requestNextPage()
        }
    }

    func postForMediaID(
        _ mediaID: String
    ) -> MagnistraRealPost? {
        guard
            let index =
                posts.firstIndex(
                    where: {
                        $0.mediaID ==
                            mediaID
                    }
                )
        else {
            return nil
        }

        return posts[index]
    }

    func mediaFrame()
        -> CGRect
    {
        let mediaWidth =
            max(
                1.0,
                tableView.bounds
                    .size.width
            )

        return CGRect(
            x: 0.0,
            y: 46.0,
            width: mediaWidth,
            height: mediaWidth
        )
    }

    func startVideo(
        mediaID: String,
        hostView: UIView
    ) -> Bool {
        guard
            let post =
                postForMediaID(
                    mediaID
                )
        else {
            return false
        }

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        let started =
            MagnistraInlineVideoPlayer
                .shared
                .start(
                    post: post,
                    hostView:
                        hostView,
                    frame:
                        mediaFrame()
                )

        syncVideoControls(
            in:
                hostView,
            post:
                post
        )

        return started
    }

    func syncVideoControls(
        in hostView: UIView,
        post: MagnistraRealPost
    ) {
        guard
            post.videoURL != nil
        else {
            return
        }

        let player =
            MagnistraInlineVideoPlayer
                .shared

        let active =
            player.activeMediaID ==
            post.mediaID

        if let status =
            hostView
                .viewWithTag(
                    MagnistraVideoUITags
                        .status
                )
                as? MagnistraVideoGlyphButton
        {
            status.glyphKind =
                active
                    ? .stop
                    : .play
        }

        hostView
            .viewWithTag(
                MagnistraVideoUITags
                    .mute
            )?
            .removeFromSuperview()

        hostView
            .viewWithTag(
                MagnistraVideoUITags
                    .fullscreen
            )?
            .removeFromSuperview()

        guard active else {
            return
        }

        let frame =
            mediaFrame()

        let mute =
            MagnistraVideoGlyphButton(
                frame:
                    CGRect(
                        x: 8.0,
                        y:
                            frame.maxY -
                            38.0,
                        width: 30.0,
                        height: 30.0
                    )
            )

        mute.tag =
            MagnistraVideoUITags
                .mute

        mute.mediaID =
            post.mediaID

        mute.glyphKind =
            player.isMuted
                ? .muted
                : .volume

        mute.addTarget(
            self,
            action:
                #selector(
                    videoMuteTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        hostView.addSubview(mute)

        let fullscreen =
            MagnistraVideoGlyphButton(
                frame:
                    CGRect(
                        x:
                            frame.maxX -
                            38.0,
                        y:
                            frame.maxY -
                            38.0,
                        width: 30.0,
                        height: 30.0
                    )
            )

        fullscreen.tag =
            MagnistraVideoUITags
                .fullscreen

        fullscreen.mediaID =
            post.mediaID

        fullscreen.glyphKind =
            .fullscreen

        fullscreen.addTarget(
            self,
            action:
                #selector(
                    videoFullscreenTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        hostView.addSubview(fullscreen)

        if let surface =
            hostView
                .viewWithTag(
                    MagnistraVideoUITags
                        .surface
                )
        {
            hostView.bringSubviewToFront(surface)
        }

        if let status =
            hostView
                .viewWithTag(
                    MagnistraVideoUITags
                        .status
                )
        {
            hostView.bringSubviewToFront(status)
        }

        hostView.bringSubviewToFront(mute)
        hostView.bringSubviewToFront(fullscreen)
    }

    func refreshVideoControls(
        mediaID: String
    ) {
        guard
            let index =
                posts.firstIndex(
                    where: {
                        $0.mediaID ==
                            mediaID
                    }
                )
        else {
            return
        }

        let path =
            IndexPath(
                row: index,
                section: 0
            )

        guard
            let cell =
                tableView.cellForRow(
                    at: path
                )
        else {
            return
        }

        syncVideoControls(
            in:
                cell.contentView,
            post:
                posts[index]
        )
    }

    func stopActiveVideoIfNeededForScroll() {
        let player =
            MagnistraInlineVideoPlayer
                .shared

        guard
            let activeMediaID =
                player.activeMediaID
        else {
            return
        }

        guard
            let index =
                posts.firstIndex(
                    where: {
                        $0.mediaID ==
                            activeMediaID
                    }
                )
        else {
            return
        }

        let path =
            IndexPath(
                row:
                    index,
                section:
                    0
            )

        guard
            let cell =
                tableView.cellForRow(
                    at:
                        path
                )
        else {
            player
                .suspendForScrollIfMediaID(
                    activeMediaID
                )

            return
        }

        guard
            let surface =
                cell.contentView
                    .viewWithTag(
                        MagnistraVideoUITags
                            .surface
                    )
                    as?
                    MagnistraVideoSurfaceButton
        else {
            return
        }

        let mediaRect =
            surface.convert(
                surface.bounds,
                to:
                    tableView
            )

        if
            !mediaRect.intersects(
                tableView.bounds
            )
        {
            player
                .suspendForScrollIfMediaID(
                    activeMediaID
                )
        }
    }

    func stopActivePhotoMusicIfNeededForScroll() {
        let musicPlayer =
            MagnistraPhotoMusicPlayer
                .shared

        guard
            let activeMediaID =
                musicPlayer.activeMediaID
        else {
            return
        }

        guard
            let index =
                posts.firstIndex(
                    where: {
                        $0.mediaID ==
                            activeMediaID
                    }
                )
        else {
            return
        }

        let path =
            IndexPath(
                row:
                    index,
                section:
                    0
            )

        guard
            let cell =
                tableView.cellForRow(
                    at:
                        path
                )
        else {
            musicPlayer
                .suspendForScrollIfMediaID(
                    activeMediaID
                )

            return
        }

        guard
            let photoSurface =
                cell.contentView
                    .viewWithTag(
                        MagnistraPhotoMusicUITags.cover
                    )
        else {
            return
        }

        let photoRect =
            photoSurface.convert(
                photoSurface.bounds,
                to:
                    tableView
            )

        if
            !photoRect.intersects(
                tableView.bounds
            )
        {
            musicPlayer
                .suspendForScrollIfMediaID(
                    activeMediaID
                )
        }
    }

    func refreshPhotoMusicControl(
        mediaID: String
    ) {
        guard
            let index =
                posts.firstIndex(
                    where: {
                        $0.mediaID ==
                            mediaID
                    }
                )
        else {
            return
        }

        let path =
            IndexPath(
                row: index,
                section: 0
            )

        guard
            let cell =
                tableView.cellForRow(
                    at: path
                ),
            let status =
                cell.contentView
                    .viewWithTag(
                        MagnistraPhotoMusicUITags.status
                    )
                    as? MagnistraVideoGlyphButton
        else {
            return
        }

        status.glyphKind =
            MagnistraPhotoMusicPlayer
                .shared
                .activeMediaID ==
            mediaID
                ? .stop
                : .music
    }
}
