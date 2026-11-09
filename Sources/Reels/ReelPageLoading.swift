// Overview: Reels: page requests and bottom loading.
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


    func requestPage(
        maxID: String?,
        replacing: Bool
    ) {
        guard !isLoading else {
            return
        }

        if !replacing && Date().timeIntervalSince1970 < magnistraReelsRetryAfter {
            return
        }

        if !replacing && reachedEnd {
            return
        }

        isLoading = true
        refreshBottomLoading()

        let requestedMaxID = maxID
        let generation = contentGeneration

        loadQueue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraHomeService
                        .loadReelsPage(
                            maxID:
                                requestedMaxID
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self = self,
                            generation ==
                                self.contentGeneration
                        else {
                            return
                        }

                        self.isLoading = false

                        self.applyPage(
                            page,
                            replacing: replacing,
                            requestedMaxID:
                                requestedMaxID
                        )
                    }
            } catch {
                let message =
                    (error as NSError)
                        .localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self = self,
                            generation ==
                                self.contentGeneration
                        else {
                            return
                        }

                        self.isLoading = false

                        self.reachedEnd = false

                        self.nextMaxID = replacing ? nil : requestedMaxID
                        self.initialContinuationBudget = 0
                        self.magnistraReelsRetryAfter = Date().timeIntervalSince1970 + 8.0
                        self.refreshBottomLoading()

                        NSLog("MAGNISTRA_REELS_REQUEST_FAIL next=%d code=%ld",
                              replacing ? 0 : 1, (error as NSError).code)

                        if replacing {
                            self.loadingLabel.text =
                                message.isEmpty
                                    ? "Reels unavailable"
                                    : message
                        }
                    }
            }
        }
    }

    func applyPage(
        _ page: MagnistraReelsPage,
        replacing: Bool,
        requestedMaxID: String?
    ) {
        if replacing {
            reelPlayer
                .stop()

            posts.removeAll(
                keepingCapacity: true
            )

            seenMediaIDs.removeAll(
                keepingCapacity: true
            )

            for pageView in
                renderedPages.values
            {
                pageView.removeFromSuperview()
            }

            renderedPages.removeAll(
                keepingCapacity: true
            )

            currentIndex = 0
            initialContinuationBudget = 2
        }

        let countBefore = posts.count
        for post in page.posts {
            if
                seenMediaIDs.contains(
                    post.mediaID
                )
            {
                continue
            }

            seenMediaIDs.insert(
                post.mediaID
            )

            posts.append(post)
        }

        nextMaxID = page.nextMaxID
        reachedEnd =
            page.nextMaxID == nil ||
            page.nextMaxID == requestedMaxID
        let newReels = posts.count - countBefore
        NSLog("MAGNISTRA_REELS_PAGE next=%d received=%ld added=%ld total=%ld cursor=%d end=%d",
              replacing ? 0 : 1, page.posts.count, newReels,
              posts.count, nextMaxID == nil ? 0 : 1, reachedEnd ? 1 : 0)
        refreshBottomLoading()

        loadingLabel.isHidden =
            !posts.isEmpty

        if posts.isEmpty {
            if reachedEnd {
                loadingLabel.text = "No Reels"
            }

            return
        }

        updateContentGeometry(
            preserveIndex: replacing
        )

        renderWindow(
            center: currentIndex
        )

        prepareUpcomingReelAsset()

        if replacing {
            scrollView.setContentOffset(
                CGPoint.zero,
                animated: false
            )
            scheduleStartCurrent()
        }

        if posts.count < 8,
           !reachedEnd,
           nextMaxID != nil,
           initialContinuationBudget > 0 {
            initialContinuationBudget -= 1
            requestPage(maxID: nextMaxID, replacing: false)
        }
    }

    func refreshBottomLoading() {
        guard !posts.isEmpty, !reachedEnd else {
            bottomLoadingLabel.isHidden = true
            return
        }
        let maxY = max(0.0,
            scrollView.contentSize.height - scrollView.bounds.height)
        let pulling = scrollView.contentOffset.y > maxY + 8.0
        bottomLoadingLabel.isHidden = !pulling || !isLoading
    }
}
