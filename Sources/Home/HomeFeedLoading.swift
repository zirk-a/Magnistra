// Overview: Home feed: refresh, story tray and page loading.
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


    @objc func refreshTapped() {
        guard !isLoadingPage else { return }

        preservingFeedDuringPullRefresh = !posts.isEmpty
        setHomePullRefreshIndicator(true)
        refreshFeed()
    }

    func refreshFeed() {
        if isLoadingPage {
            return
        }

        activePhotoQualityToken =
            MagnistraMediaPreferences
                .photoQuality
                .cacheToken

        storyLoadGeneration += 1
        if !preservingFeedDuringPullRefresh {
            posts.removeAll()
            expandedPostIDs.removeAll()
            nextMaxID = nil
            reachedEnd = false
            tableView.reloadData()
            showStatus("Loading your feed…")
        }

        requestPage(
            maxID: nil,
            replacesFeed: true
        )
    }

    func refreshStoryTray() {
        storyLoadGeneration += 1
        let generation = storyLoadGeneration
        storyQueue.addOperation { [weak self] in
            let tray = (try? MagnistraHomeService.loadStoryTray()) ?? []
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self, self.storyLoadGeneration == generation else { return }
                self.storyTray.show(tray)
                if tray.isEmpty {
                    if self.tableView.tableHeaderView != nil {
                        self.tableView.tableHeaderView = nil
                    }
                } else {
                    self.storyTray.frame = CGRect(x: 0, y: 0,
                              width: self.tableView.bounds.width, height: 88)
                    if self.tableView.tableHeaderView !== self.storyTray {
                        self.tableView.tableHeaderView = self.storyTray
                    }
                }
                self.positionHomeStatusBelowStories()
            }
        }
    }

    func requestNextPage() {
        if
            isLoadingPage ||
            reachedEnd
        {
            return
        }

        guard let cursor =
            nextMaxID,
            !cursor.isEmpty
        else {
            reachedEnd = true
            updateFooter()
            return
        }

        requestPage(
            maxID: cursor,
            replacesFeed: false
        )
    }

    func requestPage(
        maxID: String?,
        replacesFeed: Bool
    ) {
        if isLoadingPage {
            return
        }

        isLoadingPage = true
        MagnistraFeedTiming.begin("HOME")
        homeRequestStartedAtEpoch = NSDate().timeIntervalSince1970
        unifiedLoadingBand.show(!replacesFeed && !posts.isEmpty, on: view, tracking: tableView, inline: tableView.tableFooterView)

        navigationItem
            .rightBarButtonItem?
            .isEnabled = false

        updateFooter()

        let request =
            MagnistraHomePageRequest(
                maxID: maxID,
                replacesFeed:
                    replacesFeed
            )

        performSelector(
            inBackground:
                #selector(
                    loadPageBackground(_:)
                ),
            with: request
        )
    }

    @objc func loadPageBackground(
        _ object: Any?
    ) {
        autoreleasepool {
            guard let request =
                object
                    as?
                    MagnistraHomePageRequest
            else {
                return
            }

            let result:
                MagnistraHomeLoadResult

            do {
                let page =
                    try MagnistraHomeService
                        .loadPage(
                            maxID:
                                request.maxID
                        )

                result =
                    MagnistraHomeLoadResult(
                        posts: page.posts,
                        nextMaxID:
                            page.nextMaxID,
                        replacesFeed:
                            request.replacesFeed,
                        errorText: nil
                    )
            } catch {
                MagnistraLoadFailureDiagnostic.record("home_feed", error: error)
                let ns =
                    error as NSError

                result =
                    MagnistraHomeLoadResult(
                        posts: [],
                        nextMaxID:
                            request.maxID,
                        replacesFeed:
                            request.replacesFeed,
                        errorText:
                            ns.localizedDescription
                    )
            }

            performSelector(
                onMainThread:
                    #selector(
                        applyPageResult(_:)
                    ),
                with: result,
                waitUntilDone: false
            )
        }
    }

    @objc func applyPageResult(
        _ object: Any?
    ) {
        let uiApplyStartedAt = MagnistraFeedTiming.now()
        MagnistraFeedTiming.apply("HOME")
        defer { MagnistraFeedTiming.mark("HOME", "UI_APPLY_SYNC", uiApplyStartedAt) }

        if homeRequestStartedAtEpoch > 0.0 {
            let homeRequestDurationMs = (NSDate().timeIntervalSince1970 - homeRequestStartedAtEpoch) * 1000.0
            homeRequestStartedAtEpoch = 0.0
            print("MAGNISTRA_PERF2H1_HOME_REQUEST_TO_APPLY_MS=\(Int(homeRequestDurationMs))")
        }

        homeRowHeightCache.removeAll(keepingCapacity: true)
        isLoadingPage = false

        setHomePullRefreshIndicator(false)
        unifiedLoadingBand.show(false, on: view)

        navigationItem
            .rightBarButtonItem?
            .isEnabled = true

        guard let result =
            object
                as?
                MagnistraHomeLoadResult
        else {
            preservingFeedDuringPullRefresh = false
            if posts.isEmpty {
                showStatus(
                    "Couldn’t load the Home feed."
                )
            }

            updateFooter()
            return
        }

        let wasPreservingFeed =
            result.replacesFeed && preservingFeedDuringPullRefresh

        if result.errorText != nil {
            if posts.isEmpty {
                MagnistraConnectionRecovery.shared.noteFailedMedia(
                    key: "home-feed") { [weak self] in
                    guard let owner = self, owner.view.window != nil,
                          owner.posts.isEmpty, !owner.isLoadingPage else { return }
                    owner.refreshFeed()
                }
            }
            preservingFeedDuringPullRefresh = false

            if wasPreservingFeed {
                hideStatus()
                updateFooter()
                return
            }
            if
                posts.isEmpty &&
                result.replacesFeed
            {
                if
                    transientInitialErrorRetryCount <
                        transientInitialErrorRetryLimit
                {
                    transientInitialErrorRetryCount += 1
                    pendingInitialFreshRetry = true

                    showStatus(
                        "Loading your feed…"
                    )

                    updateFooter()

                    if view.window != nil {
                        perform(
                            #selector(
                                retryEmptyInitialFeed
                            ),
                            with:
                                nil,
                            afterDelay:
                                0.65
                        )
                    }

                    return
                }

                let fallback = "Couldn’t load the Home feed."
                let message = result.errorText ?? fallback
                showStatus(NoConnectionBanner.isHTTPZero(message)
                    ? message : fallback)
            }

            updateFooter()
            return
        }

        var seen = result.replacesFeed
            ? Set<String>()
            : Set(posts.map { $0.mediaID })

        var incoming:
            [MagnistraRealPost] = []

        for post in result.posts {
            if !seen.contains(
                post.mediaID
            ) {
                seen.insert(
                    post.mediaID
                )

                incoming.append(post)
            }
        }

        if result.replacesFeed {
            preservingFeedDuringPullRefresh = false

            if wasPreservingFeed && incoming.isEmpty {
                hideStatus()
                updateFooter()
                return
            }
            posts = incoming
            expandedPostIDs.removeAll()
            MagnistraPostCell.resetTransientFollowConfirmation()

            refreshStoryTray()
        } else {
            posts.append(
                contentsOf: incoming
            )
        }

        nextMaxID =
            result.nextMaxID

        reachedEnd =
            result.nextMaxID == nil

        var shouldRetryFreshInitial =
            false

        if posts.isEmpty {
            if !reachedEnd {
                showStatus(
                    "Loading your feed…"
                )
            } else if
                emptyFeedFreshRetryCount <
                    emptyFeedFreshRetryLimit
            {
                emptyFeedFreshRetryCount += 1
                shouldRetryFreshInitial = true

                showStatus(
                    "Loading your feed…"
                )
            } else {
                showStatus(
                    "Couldn’t load the Home feed."
                )
            }
        } else {
            emptyFeedFreshRetryCount = 0
            transientInitialErrorRetryCount = 0
            pendingInitialFreshRetry = false
            hideStatus()
        }

        let savedViewportY = wasPreservingFeed ? tableView.contentOffset.y : nil
        tableView.reloadData()
        if let previousY = savedViewportY {
            tableView.layoutIfNeeded()
            let firstY = -tableView.contentInset.top
            let lastY = max(firstY, tableView.contentSize.height -
                tableView.bounds.height + tableView.contentInset.bottom)
            tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x,
                y: min(lastY, max(firstY, previousY))), animated: false)
        }
        updateFooter()

        if
            incoming.isEmpty &&
            !reachedEnd
        {
            requestNextPage()
            return
        }

        if shouldRetryFreshInitial {
            perform(
                #selector(
                    retryEmptyInitialFeed
                ),
                with:
                    nil,
                afterDelay:
                    0.65
            )
        }
    }

    @objc func retryEmptyInitialFeed() {
        if
            isLoadingPage ||
            !posts.isEmpty
        {
            return
        }

        if view.window == nil {
            pendingInitialFreshRetry = true
            return
        }

        pendingInitialFreshRetry = false

        requestPage(
            maxID:
                nil,
            replacesFeed:
                true
        )
    }

    func updateFooter() {
        guard let footer =
            tableView.tableFooterView
        else {
            return
        }

        let atEnd = reachedEnd && !posts.isEmpty && !isLoadingPage
        let footerHeight: CGFloat = atEnd ? 2.0 : 38.0
        if abs(footer.frame.height - footerHeight) > 0.5 {
            var frame = footer.frame
            frame.size.height = footerHeight
            footer.frame = frame
            tableView.tableFooterView = footer
        }
        tableView.backgroundColor = UIColor.white
        if atEnd {
            for child in footer.subviews { child.removeFromSuperview() }
            footer.backgroundColor = UIColor(white: 0.94, alpha: 1.0)
            return
        }

        footer.backgroundColor =
            isLoadingPage && !preservingFeedDuringPullRefresh && !posts.isEmpty
                ? UIColor(white: 0.10, alpha: 0.88) : UIColor.clear

        for view in
            footer.subviews {
            view.removeFromSuperview()
        }

        let label =
            UILabel(
                frame: CGRect(
                    x: 10.0,
                    y: 5.0,
                    width:
                        footer.bounds.size.width -
                        20.0,
                    height: 30.0
                )
            )

        label.backgroundColor =
            UIColor.clear

        label.textAlignment =
            .center

        label.textColor =
            isLoadingPage && !preservingFeedDuringPullRefresh && !posts.isEmpty
                ? UIColor.white : UIColor(white: 0.55, alpha: 1.0)

        label.font =
            (isLoadingPage && !preservingFeedDuringPullRefresh && !posts.isEmpty)
                ? UIFont.boldSystemFont(ofSize: 11.0)
                : UIFont.systemFont(ofSize: 11.0)

        if isLoadingPage && !preservingFeedDuringPullRefresh && !posts.isEmpty {
            label.text = "Loading..."
        } else if
            reachedEnd &&
            !posts.isEmpty
        {
            label.text =
                "You’re all caught up."
        } else {
            label.text = ""
        }

        footer.addSubview(label)
    }
}
