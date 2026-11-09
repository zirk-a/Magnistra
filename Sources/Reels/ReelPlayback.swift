// Overview: Reels: playback scheduling and asset preparation.
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

extension MagnistraReelsViewController {


    func scheduleStartCurrent() {
        startCurrentPending = true
        NSObject
            .cancelPreviousPerformRequests(
                withTarget:
                    self,
                selector:
                    #selector(
                        startCurrentAfterSettle
                    ),
                object:
                    nil
            )

        perform(
            #selector(
                startCurrentAfterSettle
            ),
            with:
                nil,
            afterDelay:
                0.10
        )
    }

    @objc func startCurrentAfterSettle() {
        startCurrentPending = false
        guard
            !scrollView.isDragging,
            !scrollView.isDecelerating,
            currentIndex >= 0,
            currentIndex < posts.count,
            let page =
                renderedPages[
                    currentIndex
                ]
        else {
            return
        }

        let post = posts[currentIndex]

        if reelPlayer.activeMediaID == post.mediaID {

            _ = reelPlayer.resumeIfMediaID(post.mediaID)
            if !page.posterView.isHidden {
                schedulePosterRelease(mediaID: post.mediaID)
            }
            return
        }

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        let started =
            reelPlayer
                .start(
                    post: post,
                    hostView:
                        page.videoHostView,
                    frame:
                        page.videoHostView.bounds
                )

        if started {

            if
                resumeFromPostMediaID ==
                    post.mediaID,
                resumeFromPostSeconds >
                    0.0
            {
                _ =
                    reelPlayer
                        .seekActive(
                            mediaID:
                                post.mediaID,
                            seconds:
                                resumeFromPostSeconds
                        )

                resumeFromPostMediaID =
                    nil

                resumeFromPostSeconds =
                    0.0

                resumeFromPostWasPlaying =
                    false
            }

            page.muteButton.glyphKind =
                .volume

            page.posterView.isHidden =
                false

            page.posterView.alpha =
                1.0

            schedulePosterRelease(
                mediaID:
                    post.mediaID
            )
        }
    }

    func prepareUpcomingReelAsset() {
        guard currentIndex >= 0,
              currentIndex + 1 < posts.count,
              reelPlayer.activeMediaID == posts[currentIndex].mediaID
        else { return }
        reelPlayer.prepareNextReel(post: posts[currentIndex + 1])
    }

    func schedulePosterRelease(
        mediaID: String
    ) {
        posterReleaseMediaID =
            mediaID

        NSObject
            .cancelPreviousPerformRequests(
                withTarget:
                    self,
                selector:
                    #selector(
                        checkPosterRelease
                    ),
                object:
                    nil
            )

        perform(
            #selector(
                checkPosterRelease
            ),
            with:
                nil,
            afterDelay:
                0.04
        )
    }

    @objc func checkPosterRelease() {
        guard
            let mediaID =
                posterReleaseMediaID,
            currentIndex >=
                0,
            currentIndex <
                posts.count,
            posts[currentIndex].mediaID ==
                mediaID,
            let page =
                renderedPages[
                    currentIndex
                ],
            page.mediaID ==
                mediaID
        else {
            posterReleaseMediaID =
                nil

            return
        }

        if
            reelPlayer
                .hasPlaybackProgress(
                    mediaID:
                        mediaID
                )
        {
            page.posterView.isHidden =
                true
            prepareUpcomingReelAsset()

            posterReleaseMediaID =
                nil

            return
        }

        if
            scrollView.isDragging ||
            scrollView.isDecelerating
        {

            return
        }

        perform(
            #selector(
                checkPosterRelease
            ),
            with:
                nil,
            afterDelay:
                0.04
        )
    }

    func settleCurrentPage() {
        guard !posts.isEmpty else {
            return
        }

        let height =
            max(
                1.0,
                scrollView.bounds.size.height
            )

        let raw =
            scrollView.contentOffset.y /
            height

        let index =
            max(
                0,
                min(
                    posts.count - 1,
                    Int(raw + 0.5)
                )
            )

        currentIndex = index

        renderWindow(
            center: index
        )

        for (
            pageIndex,
            page
        ) in renderedPages {
            if pageIndex != index {
                page.resetReelVideoZoom()
            }
        }

        reelPlayer
            .scheduleScrollStopFinish()

        scheduleStartCurrent()

        if
            !reachedEnd,
            index >= posts.count - 3
        {
            requestPage(
                maxID: nextMaxID,
                replacing: false
            )
        }
    }

    func suspendOffscreenActiveReel() {
        let player =
            reelPlayer

        guard
            let activeID =
                player.activeMediaID,
            let index =
                postIndex(
                    mediaID:
                        activeID
                )
        else {
            return
        }

        guard
            let page =
                renderedPages[
                    index
                ]
        else {
            player
                .suspendForScrollIfMediaID(
                    activeID
                )
            return
        }

        let viewport =
            CGRect(
                origin:
                    scrollView.contentOffset,
                size:
                    scrollView.bounds.size
            )

        if
            !page.frame.intersects(
                viewport
            )
        {
            player
                .suspendForScrollIfMediaID(
                    activeID
                )
        }
    }
}
