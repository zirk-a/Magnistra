// Overview: Reels: scrolling and tap actions.
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


    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView,
              currentIndex >= 0,
              currentIndex < posts.count else { return }

        _ = reelPlayer.pauseIfMediaID(posts[currentIndex].mediaID)
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        guard
            scrollView ===
                self.scrollView
        else {
            return
        }

        if startCurrentPending {
            startCurrentPending = false
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(startCurrentAfterSettle),
                object: nil
            )
        }
        if posterReleaseMediaID != nil {
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(checkPosterRelease),
                object: nil
            )
            posterReleaseMediaID = nil
        }

        reelPlayer
            .cancelScheduledScrollStopFinish()

        suspendOffscreenActiveReel()

        if !posts.isEmpty && !reachedEnd && !isLoading,
           nextMaxID != nil {
            let maxY = max(0.0,
                scrollView.contentSize.height - scrollView.bounds.height)
            if scrollView.contentOffset.y > maxY + 18.0 {
                requestPage(maxID: nextMaxID, replacing: false)
            }
        }
        refreshBottomLoading()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate
            decelerate: Bool
    ) {
        if
            scrollView ===
                self.scrollView,
            !decelerate
        {
            settleCurrentPage()
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        if
            scrollView ===
                self.scrollView
        {
            settleCurrentPage()
        }
    }

    @objc func reelSurfaceTapped(
        _ sender:
            MagnistraVideoSurfaceButton
    ) {
        if
            let page =
                sender.superview
                    as?
                    MagnistraReelPageView,
            page
                .shouldSuppressSurfaceTapAfterPinch()
        {
            return
        }

        let player =
            reelPlayer

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
            let index =
                postIndex(
                    mediaID:
                        sender.mediaID
                ),
            index == currentIndex
        else {
            return
        }

        scheduleStartCurrent()
    }

    @objc func reelMuteTapped(
        _ sender:
            MagnistraVideoGlyphButton
    ) {
        guard
            reelPlayer
                .activeMediaID ==
            sender.mediaID
        else {
            return
        }

        if let muted =
            reelPlayer
                .toggleMuted()
        {
            sender.glyphKind =
                muted
                    ? .muted
                    : .volume
        }
    }

    @objc func reelPostTapped(
        _ sender:
            MagnistraReelOpenPostButton
    ) {
        guard
            let index =
                postIndex(
                    mediaID:
                        sender.mediaID
                ),
            index >= 0,
            index < posts.count
        else {
            return
        }

        let selectedPost =
            posts[index]

        let player =
            reelPlayer

        resumeFromPostMediaID =
            selectedPost.mediaID

        resumeFromPostSeconds =
            player
                .currentPlaybackSeconds(
                    mediaID:
                        selectedPost.mediaID
                ) ?? 0.0

        resumeFromPostWasPlaying =
            player.isPlaying

        preservePlayerForPost =
            true

        if
            let page =
                renderedPages[
                    index
                ]
        {
            page.posterView.isHidden =
                false

            page.posterView.alpha =
                1.0
        }

        posterReleaseMediaID =
            nil

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

        player.stop()

        resumeFromPostMediaID =
            nil

        resumeFromPostSeconds =
            0.0

        resumeFromPostWasPlaying =
            false

        preservePlayerForPost =
            false
let controller =
            MagnistraExploreFeedViewController(
                selectedPost:
                    selectedPost,
                deferredPostsProvider: {
                    return []
                },
                nextMaxID:
                    nil,
                reachedEnd:
                    true
            )

        let iosMajor = (UIDevice.current.systemVersion as NSString).integerValue
        magnistraReelsOpeningPostTransition = iosMajor < 7 || iosMajor > 10

        navigationController?
            .pushViewController(
                controller,
                animated:
                    true
            )
    }

    @objc func closeTapped() {
        preservePlayerForPost =
            false

        resumeFromPostMediaID =
            nil

        resumeFromPostSeconds =
            0.0

        resumeFromPostWasPlaying =
            false

        navigationController?
            .popViewController(
                animated: true
            )
    }

    func magnistraReelsInitialLoadingClearBackground() {
        loadingLabel.backgroundColor = UIColor.clear
        loadingLabel.isOpaque = false
        loadingLabel.layer.backgroundColor = UIColor.clear.cgColor
        loadingLabel.layer.isOpaque = false
    }
}
