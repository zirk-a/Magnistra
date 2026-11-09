// Overview: Tag feed: video and photo-music playback while scrolling.
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


    func startVideo(
        mediaID: String,
        hostView: UIView
    ) -> Bool {
        guard
            let post =
                postForMediaID(mediaID)
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
                    hostView: hostView,
                    frame: mediaFrame()
                )

        syncVideoControls(
            in: hostView,
            post: post
        )

        return started
    }

    func syncVideoControls(
        in hostView: UIView,
        post: MagnistraRealPost
    ) {
        guard post.videoURL != nil else {
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
                    MagnistraVideoUITags.status
                )
                as?
                MagnistraVideoGlyphButton
        {
            status.glyphKind =
                active
                    ? .stop
                    : .play
        }

        hostView
            .viewWithTag(
                MagnistraVideoUITags.mute
            )?
            .removeFromSuperview()

        hostView
            .viewWithTag(
                MagnistraVideoUITags.fullscreen
            )?
            .removeFromSuperview()

        guard active else {
            return
        }

        let frame = mediaFrame()

        let mute =
            MagnistraVideoGlyphButton(
                frame:
                    CGRect(
                        x: 8.0,
                        y: frame.maxY - 38.0,
                        width: 30.0,
                        height: 30.0
                    )
            )

        mute.tag =
            MagnistraVideoUITags.mute

        mute.mediaID = post.mediaID

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
            for: .touchUpInside
        )

        hostView.addSubview(mute)

        let fullscreen =
            MagnistraVideoGlyphButton(
                frame:
                    CGRect(
                        x: frame.maxX - 38.0,
                        y: frame.maxY - 38.0,
                        width: 30.0,
                        height: 30.0
                    )
            )

        fullscreen.tag =
            MagnistraVideoUITags.fullscreen

        fullscreen.mediaID = post.mediaID
        fullscreen.glyphKind = .fullscreen

        fullscreen.addTarget(
            self,
            action:
                #selector(
                    videoFullscreenTapped(
                        _:
                    )
                ),
            for: .touchUpInside
        )

        hostView.addSubview(fullscreen)

        if let surface =
            hostView
                .viewWithTag(
                    MagnistraVideoUITags.surface
                )
        {
            hostView.bringSubviewToFront(surface)
        }

        if let status =
            hostView
                .viewWithTag(
                    MagnistraVideoUITags.status
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
                        $0.mediaID == mediaID
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
            in: cell.contentView,
            post: posts[index]
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
                        73422
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
                        $0.mediaID == mediaID
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
                    .viewWithTag(MagnistraPhotoMusicUITags.status)
                    as?
                    MagnistraVideoGlyphButton
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

    func photoMusicPhotoTapped(
        mediaID: String
    ) {
        guard
            let post =
                postForMediaID(mediaID),
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
                    post: post
                )

        refreshPhotoMusicControl(
            mediaID: post.mediaID
        )

        if
            let previousMediaID =
                previousMediaID,
            previousMediaID !=
                post.mediaID
        {
            refreshPhotoMusicControl(
                mediaID:
                    previousMediaID
            )
        }
    }

    func installMediaControls(
        in cell: MagnistraPostCell,
        post: MagnistraRealPost
    ) {
        let host = cell.contentView

        let tags = [
            MagnistraVideoUITags.surface,
            MagnistraVideoUITags.status,
            MagnistraVideoUITags.mute,
            MagnistraVideoUITags.fullscreen,
            MagnistraPhotoMusicUITags.status,
            73422
        ]

        for tag in tags {
            host
                .viewWithTag(tag)?
                .removeFromSuperview()
        }

        MagnistraInlineVideoPlayer
            .shared
            .prepare(
                hostView: host,
                mediaID: post.mediaID
            )

        let width =
            max(
                1.0,
                tableView.bounds.size.width
            )

        if post.videoURL != nil {
            let frame = mediaFrame()

            let surface =
                MagnistraVideoSurfaceButton(
                    frame: frame
                )

            surface.tag =
                MagnistraVideoUITags.surface

            surface.mediaID =
                post.mediaID

            surface.backgroundColor =
                UIColor.clear
            surface.onFullscreenHold = { [weak self, weak cell] in
                guard let self = self, let cell = cell else { return }
                let player = MagnistraInlineVideoPlayer.shared
                if player.activeMediaID != post.mediaID {
                    _ = self.startVideo(mediaID: post.mediaID,
                                        hostView: cell.contentView)
                }
                _ = player.enterFullscreen()
            }

            surface.addTarget(
                self,
                action:
                    #selector(
                        videoSurfaceTapped(
                            _:
                        )
                    ),
                for: .touchUpInside
            )

            host.addSubview(surface)

            let status =
                MagnistraVideoGlyphButton(
                    frame:
                        CGRect(
                            x: width - 38.0,
                            y: 54.0,
                            width: 30.0,
                            height: 30.0
                        )
                )

            status.tag =
                MagnistraVideoUITags.status

            status.mediaID =
                post.mediaID

            status.addTarget(
                self,
                action:
                    #selector(
                        videoStatusTapped(
                            _:
                        )
                    ),
                for: .touchUpInside
            )

            host.addSubview(status)

            syncVideoControls(
                in: host,
                post: post
            )
        }

        if
            post.videoURL == nil,
            post.musicAudioURL != nil
        {
            let photoTap =
                MagnistraExplorePhotoMusicTapButton(
                    frame:
                        mediaFrame()
                )

            photoTap.tag =
                73422

            photoTap.mediaID =
                post.mediaID

            photoTap.backgroundColor =
                UIColor.clear

            photoTap.setTitle(
                nil,
                for:
                    .normal
            )

            photoTap.addTarget(
                self,
                action:
                    #selector(
                        photoMusicPhotoButtonTapped(
                            _:
                        )
                    ),
                for:
                    .touchUpInside
            )

            photoTap.onLongPress = {
                [weak self, weak cell] sender in

                guard
                    let self = self,
                    let cell = cell,
                    sender.mediaID ==
                        post.mediaID,
                    let image =
                        cell.currentMediaImage()
                else {
                    return
                }

                let music =
                    MagnistraPhotoMusicPlayer
                        .shared

                let previousMediaID =
                    music.activeMediaID

                MagnistraInlineVideoPlayer
                    .shared
                    .stop()

                if
                    music.activeMediaID ==
                        post.mediaID
                {
                    if !music.isPlaying {
                        _ =
                            music.toggle(
                                post:
                                    post
                            )
                    }
                } else {
                    _ =
                        music.start(
                            post:
                                post
                        )
                }

                self.refreshPhotoMusicControl(
                    mediaID:
                        post.mediaID
                )

                if
                    let previousMediaID =
                        previousMediaID,
                    previousMediaID !=
                        post.mediaID
                {
                    self.refreshPhotoMusicControl(
                        mediaID:
                            previousMediaID
                    )
                }

                _ =
                    MagnistraImageZoomOverlay
                        .present(
                            image:
                                image
                        )
            }

            host.addSubview(
                photoTap
            )

            let musicStatus =
                MagnistraVideoGlyphButton(
                    frame:
                        CGRect(
                            x: width - 38.0,
                            y: 54.0,
                            width: 30.0,
                            height: 30.0
                        )
                )

            musicStatus.tag = MagnistraPhotoMusicUITags.status
            musicStatus.mediaID = post.mediaID

            musicStatus.glyphKind =
                MagnistraPhotoMusicPlayer
                    .shared
                    .activeMediaID ==
                post.mediaID
                    ? .stop
                    : .music

            musicStatus.addTarget(
                self,
                action:
                    #selector(
                        photoMusicStatusTapped(
                            _:
                        )
                    ),
                for: .touchUpInside
            )

            host.addSubview(musicStatus)
        }
    }
}
