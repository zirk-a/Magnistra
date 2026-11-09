// Overview: Explore: requesting and applying pages of the Explore grid.
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

extension ExploreViewController {


    func requestPage(
        maxID: String?,
        replacing: Bool
    ) {
        if
            isLoadingPage ||
            (
                !replacing &&
                reachedEnd
            )
        {
            return
        }

        isLoadingPage = true
        magnistraSerial += 1
        let exploreRequestSerial = magnistraSerial
        let exploreRequestStartedAt = MagnistraFeedTiming.now()
        MagnistraFeedTiming.begin("EXPLORE")
        exploreRequestStartedAtEpoch = NSDate().timeIntervalSince1970
        unifiedLoadingBand.show(!replacing && !posts.isEmpty, on: view, tracking: scrollView, inline: paginationLabel)
        if magnistraSavedGrid && replacing && posts.isEmpty {
            MagnistraBottomLoading.show(on: view)
        }

        if replacing {
            if !preservingGridDuringPullRefresh {
                statusLabel.text = nil
                deferredExplorePosts.removeAll(keepingCapacity: true)
                deferredExploreNextMaxID = nil
            }
        } else {
            paginationLabel.isHidden =
                false

            layoutGrid()
        }

        if !replacing && maxID == "__magnistra_explore_twelve_buffer__" {
            let pending = deferredExplorePosts
            let continuation = deferredExploreNextMaxID
            deferredExplorePosts.removeAll(keepingCapacity: true)
            deferredExploreNextMaxID = nil
            applyPage(
                MagnistraExplorePage(posts: pending, nextMaxID: continuation),
                requestedMaxID: maxID,
                replacing: false
            )
            return
        }

        loadQueue.addOperation {
            [weak self] in

            do {
                let page: MagnistraExplorePage
                let initialBatch: MagnistraExploreTwelveBatch?
                if self?.magnistraSavedGrid == true {
                    let saved = try MagnistraHomeService.loadProfileSavedPage(maxID: maxID)
                    page = MagnistraExplorePage(posts: saved.posts, nextMaxID: saved.nextMaxID)
                    initialBatch = nil
                } else if replacing && maxID == nil {
                    let batch = try MagnistraHomeService.loadExploreTwelveInitial(
                        onEarlyPosts: { [weak self] firstPosts in
                            OperationQueue.main.addOperation { [weak self] in
                                guard let self = self,
                                      self.magnistraSerial == exploreRequestSerial,
                                      self.isLoadingPage,
                                      !self.magnistraSavedGrid else { return }

                                self.applyPage(
                                    MagnistraExplorePage(
                                        posts: firstPosts,
                                        nextMaxID: "__magnistra_explore_twelve_buffer__"
                                    ),
                                    requestedMaxID: maxID,
                                    replacing: replacing
                                )
self.isLoadingPage = true

                                if self.posts.count < 12 {
                                    for magnistraPlaceholderSlots in self.posts.count..<12 {
                                        let wantedTag = self.placeholderTagBase + magnistraPlaceholderSlots
                                        if !self.placeholderViews.contains(where: { $0.tag == wantedTag }) {
                                            self.addPlaceholder(for: magnistraPlaceholderSlots)
                                        }
                                    }
                                }
                                self.layoutGrid()
                                self.magnistraPreviewApplied = exploreRequestSerial
                                MagnistraFeedTiming.mark("EXPLORE", "EARLY_UI_VISIBLE", exploreRequestStartedAt)
                            }
                        }
                    )
                    page = batch.page
                    initialBatch = batch
                } else {
                    page = try MagnistraHomeService.loadExplorePage(maxID: maxID)
                    initialBatch = nil
                }

                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    guard self.magnistraSerial == exploreRequestSerial else { return }
                    if let batch = initialBatch,
                       (!self.preservingGridDuringPullRefresh || !page.posts.isEmpty) {
                        self.deferredExplorePosts = batch.deferredPosts
                        self.deferredExploreNextMaxID = batch.deferredNextMaxID
                    }
                    if self.magnistraPreviewApplied == exploreRequestSerial {

                        self.applyPage(
                            MagnistraExplorePage(
                                posts: Array(page.posts.dropFirst(6)),
                                nextMaxID: page.nextMaxID
                            ),
                            requestedMaxID: maxID,
                            replacing: false
                        )
                    } else {
                        self.applyPage(page, requestedMaxID: maxID, replacing: replacing)
                    }
                    MagnistraFeedTiming.mark("EXPLORE", "FINAL_UI_VISIBLE", exploreRequestStartedAt)
                }
            } catch {
                MagnistraLoadFailureDiagnostic.record("explore_grid", error: error)
                let message =
                    (
                        error as NSError
                    )
                        .localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.isLoadingPage =
                            false
                        self.unifiedLoadingBand.show(false, on: self.view)
                        if self.magnistraSavedGrid { MagnistraBottomLoading.hide(on: self.view) }

                        if !self.preservingGridDuringPullRefresh {
                            self.reachedEnd = true
                            self.nextMaxID = nil
                        }

                        self.paginationLabel
                            .isHidden =
                                true

                        if replacing {
                            self.pullRefreshIndicator.end(on: self.navigationItem)
                            self.navigationItem
                                .rightBarButtonItem?
                                .isEnabled = true
                            let keepGrid = self.preservingGridDuringPullRefresh
                            self.preservingGridDuringPullRefresh = false
                            if !keepGrid {
                                self.removeAllPlaceholders()
                                if !self.magnistraSavedGrid &&
                                    NoConnectionBanner.showIfHTTPZero(message, on: self.view) {
                                    self.statusLabel.text = nil
                                } else {
                                    NoConnectionBanner.hide(on: self.view)
                                    self.statusLabel.text = message
                                }
                            }
                        }

                        self.layoutGrid()
                    }
            }
        }
    }

    func applyPage(
        _ page:
            MagnistraExplorePage,
        requestedMaxID:
            String?,
        replacing:
            Bool
    ) {
        if !magnistraSavedGrid {
            NoConnectionBanner.hide(on: view)
        }
        let uiApplyStartedAt = MagnistraFeedTiming.now()
        MagnistraFeedTiming.apply("EXPLORE")
        defer { MagnistraFeedTiming.mark("EXPLORE", "UI_APPLY_SYNC", uiApplyStartedAt) }

        if exploreRequestStartedAtEpoch > 0.0 {
            let exploreRequestDurationMs = (NSDate().timeIntervalSince1970 - exploreRequestStartedAtEpoch) * 1000.0
            exploreRequestStartedAtEpoch = 0.0
            print("MAGNISTRA_PERF2H1_EXPLORE_REQUEST_TO_APPLY_MS=\(Int(exploreRequestDurationMs))")
        }

        isLoadingPage =
            false
        unifiedLoadingBand.show(false, on: view)
        if magnistraSavedGrid { MagnistraBottomLoading.hide(on: view) }

        paginationLabel.isHidden =
            true

        if replacing {
            pullRefreshIndicator.end(on: navigationItem)
            navigationItem
                .rightBarButtonItem?
                .isEnabled = true
            let keepGrid = preservingGridDuringPullRefresh
            preservingGridDuringPullRefresh = false

            if keepGrid && page.posts.isEmpty {
                layoutGrid()
                return
            }
            if keepGrid {

                imageQueue.cancelAllOperations()
                contentGeneration += 1
            }

            magnistraViewportQueuedMediaIDs.removeAll(keepingCapacity: true)
            magnistraThumbnailRetryCount.removeAll(keepingCapacity: true)
            magnistraThumbnailRetryNotBefore.removeAll(keepingCapacity: true)
            posts.removeAll(
                keepingCapacity: true
            )

            seenMediaIDs.removeAll(
                keepingCapacity: true
            )

            for tile in tiles {
                tile.removeFromSuperview()
            }

            tiles.removeAll(
                keepingCapacity: true
            )

            removeAllPlaceholders()
        }

        var newIndexes:
            [Int] = []

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

            posts.append(
                post
            )

            let index =
                posts.count - 1

            newIndexes.append(
                index
            )

let magnistraSlotTag = placeholderTagBase + index
            if !placeholderViews.contains(where: { $0.tag == magnistraSlotTag }) {
                addPlaceholder(for: index)
            }
        }

        nextMaxID =
            page.nextMaxID

        reachedEnd =
            page.nextMaxID == nil ||
            page.nextMaxID ==
                requestedMaxID

        magnistraKeepFifteenSavedSlots()

        if posts.isEmpty {
            if magnistraSavedGrid {
                statusLabel.text = nil
                layoutGrid()
                return
            }
            removeAllPlaceholders()

            statusLabel.text =
                magnistraSavedGrid ? "No saved posts." : "No Explore posts available."

            scrollView.contentSize =
                scrollView.bounds.size

            return
        }

        statusLabel.text =
            nil

        layoutGrid()
        magnistraLoadNearViewportImages()
    }

    func magnistraKeepFifteenSavedSlots() {
        guard magnistraSavedGrid, posts.count < 15 else { return }
        for index in posts.count..<15 {
            let wantedTag = placeholderTagBase + index
            if !placeholderViews.contains(where: { $0.tag == wantedTag }) {
                addPlaceholder(for: index)
            }
        }
    }

    func magnistraLoadNearViewportImages() {
        guard view.window != nil, !posts.isEmpty, scrollView.bounds.height > 1.0 else { return }
        let h = scrollView.bounds.height
        let upper = scrollView.contentOffset.y - h * 0.35
        let lower = scrollView.contentOffset.y + h * 1.35
        for index in 0..<posts.count {
            let mediaID = posts[index].mediaID
            if magnistraViewportQueuedMediaIDs.contains(mediaID) { continue }
            if (magnistraThumbnailRetryCount[mediaID] ?? 0) > 3 { continue }
            if (magnistraThumbnailRetryNotBefore[mediaID] ?? 0.0) >
                Date().timeIntervalSince1970 { continue }
            let frame = frameForGridIndex(index)
            if frame.maxY < upper || frame.minY > lower { continue }
            magnistraViewportQueuedMediaIDs.insert(mediaID)
            enqueueImage(for: index)
        }
    }
}
