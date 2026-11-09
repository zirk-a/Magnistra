// Overview: Direct thread: loading older messages while scrolling and prewarming previews.
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


    func prewarmDirectPreviewWindow() {
        guard
            !tableView.isDragging,
            !tableView.isDecelerating,
            !messages.isEmpty,
            let visible =
                tableView
                    .indexPathsForVisibleRows,
            let lastVisible =
                visible
                    .map({
                        $0.row
                    })
                    .max()
        else {
            return
        }

        let first =
            lastVisible +
            1

        let last =
            min(
                messages.count -
                1,
            lastVisible +
                2
            )

        guard
            first <= last
        else {
            return
        }

        for row in first...last {
            MagnistraDirectMessageCell
                .prewarmPreview(
                    messages[
                        row
                    ]
                )
        }
    }

    func resumeDirectPreviewPresentation() {
        MagnistraDirectMessageCell
            .setPreviewApplicationSuspended(
                false
            )

        for case let cell as MagnistraDirectMessageCell
            in tableView.visibleCells
        {
            cell.applyPendingPreviewIfNeeded()
        }

        prewarmDirectPreviewWindow()
    }
    func tryLoadOlderAfterPoll() {
        guard olderLoadPending, !usesMatrixBackend, !loading,
              !magnistraDirectLoadingOlder else { return }
        if tableView.isDragging || tableView.isTracking || tableView.isDecelerating { return }
        if tableView.contentOffset.y > 36.0 {
            olderLoadPending = false
            olderPullArmed = true
            return
        }
        guard magnistraDirectInitialPageReceived else { return }
        if !magnistraDirectHasOlder {
            olderLoadPending = false
            NSLog("MAGNISTRA_DIRECT_PAGING phase=NO_OLDER_CURSOR")
            return
        }
        olderLoadPending = false
        NSLog("MAGNISTRA_DIRECT_PAGING phase=OLDER_REQUESTED")
        magnistraDirectFetchOlder()
    }

    func offerOlderMessages(_ scrollView: UIScrollView) {
        guard scrollView === tableView, !usesMatrixBackend else { return }
        if scrollView.contentOffset.y > 36.0 {
            olderPullArmed = true
            olderLoadPending = false
        } else if scrollView.contentOffset.y <= 8.0 && olderPullArmed {
            olderPullArmed = false
            olderLoadPending = true
            NSLog("MAGNISTRA_DIRECT_PAGING phase=TOP_REACHED")
        }
        tryLoadOlderAfterPoll()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === tableView && usesMatrixBackend {
            if scrollView.contentOffset.y > 48.0 { matrixOlderArmed = true }
            if matrixOlderArmed && scrollView.isDragging &&
               scrollView.contentOffset.y < -24.0 {
                matrixOlderArmed = false
                loadMatrixOlder()
            }
            return
        }
        if scrollView === tableView && (scrollView.isDragging || scrollView.isDecelerating) {
            offerOlderMessages(scrollView)
        } else if scrollView === tableView && scrollView.contentOffset.y > 36.0 {
            olderPullArmed = true
            olderLoadPending = false
        }
    }

    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {

        MagnistraDirectMessageCell
            .setPreviewApplicationSuspended(
                true
            )
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        offerOlderMessages(scrollView)

        if !decelerate {
            tryLoadOlderAfterPoll()
            resumeDirectPreviewPresentation()
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        offerOlderMessages(scrollView)
        tryLoadOlderAfterPoll()
        resumeDirectPreviewPresentation()
    }
}
