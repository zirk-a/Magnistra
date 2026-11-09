// Overview: Explore feed: loading and buffering of next pages.
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

extension MagnistraExploreFeedViewController {


    func requestNextPage() {
        guard
            !isLoadingPage,
            !reachedEnd,
            let cursor = nextMaxID,
            !cursor.isEmpty
        else {
            return
        }

        isLoadingPage = true
        tableView.tableFooterView =
            loadingFooter
        unifiedLoadingBand.show(true, on: view, tracking: tableView,
                                inline: loadingFooter)

        loadQueue.addOperation {
            [weak self] in

            do {
                let page: MagnistraExplorePage
                if let repostsUserID = self?.magnistraRepostsUserID {
                    let reposts = try MagnistraHomeService.loadProfileRepostsPage(
                        userID: repostsUserID, maxID: cursor)
                    page = MagnistraExplorePage(posts: reposts.posts,
                                               nextMaxID: reposts.nextMaxID)
                } else if self?.magnistraSavedFeed == true {
                    let saved = try MagnistraHomeService.loadProfileSavedPage(maxID: cursor)
                    page = MagnistraExplorePage(posts: saved.posts, nextMaxID: saved.nextMaxID)
                } else {
                    page = try MagnistraHomeService.loadExplorePage(maxID: cursor)
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in
                        self?
                            .applyNextPage(
                                page,
                                requestedCursor:
                                    cursor
                            )
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in
                        guard let self = self else {
                            return
                        }

                        self.isLoadingPage = false
                        self.unifiedLoadingBand.show(false, on: self.view)

                        self.reachedEnd = true
                        self.nextMaxID = nil
                        self.tableView.tableFooterView = nil
                    }
            }
        }
    }

    func applyNextPage(
        _ page: MagnistraExplorePage,
        requestedCursor: String
    ) {
        var incoming:
            [MagnistraRealPost] =
                []

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

            incoming.append(
                post
            )
        }

        nextMaxID =
            page.nextMaxID

        reachedEnd =
            page.nextMaxID == nil ||
            page.nextMaxID ==
                requestedCursor

        bufferedPaginationPosts
            .append(
                contentsOf:
                    incoming
            )

        if bufferedPaginationPosts.isEmpty {
            finishBufferedPagination()
        } else {
            scheduleBufferedPaginationDrain(
                after:
                    0.02
            )
        }
    }

    func paginationIsHeavyScroll()
        -> Bool
    {
        guard
            tableView.isDragging ||
            tableView.isDecelerating
        else {
            return false
        }

        let velocity =
            abs(
                tableView
                    .panGestureRecognizer
                    .velocity(
                        in:
                            tableView
                    )
                    .y
            )

        return velocity >=
            paginationHeavyVelocity
    }

    func scheduleBufferedPaginationDrain(
        after delay: TimeInterval
    ) {
        guard
            !paginationDrainScheduled,
            !bufferedPaginationPosts.isEmpty
        else {
            return
        }

        paginationDrainScheduled =
            true

        perform(
            #selector(
                drainBufferedPaginationPosts
            ),
            with:
                nil,
            afterDelay:
                delay
        )
    }

    @objc func drainBufferedPaginationPosts() {
        paginationDrainScheduled =
            false

        guard
            !bufferedPaginationPosts.isEmpty
        else {
            finishBufferedPagination()
            return
        }

        if paginationIsHeavyScroll() {
            paginationScrollPaused =
                true

            scheduleBufferedPaginationDrain(
                after:
                    0.18
            )

            return
        }

        paginationScrollPaused =
            false

        let nextPost =
            bufferedPaginationPosts
                .removeFirst()

        let row =
            posts.count

        posts.append(
            nextPost
        )

        tableView.insertRows(
            at: [
                IndexPath(
                    row:
                        row,
                    section:
                        0
                )
            ],
            with:
                .none
        )

        if bufferedPaginationPosts.isEmpty {
            finishBufferedPagination()
        } else {
            scheduleBufferedPaginationDrain(
                after:
                    0.08
            )
        }
    }

    func finishBufferedPagination() {
        paginationDrainScheduled =
            false

        paginationScrollPaused =
            false

        isLoadingPage =
            false
        unifiedLoadingBand.show(false, on: view)

        tableView.tableFooterView =
            nil
    }

    func resumeIncrementalPaginationAfterScroll() {
        paginationScrollPaused =
            false

        if !bufferedPaginationPosts.isEmpty {
            scheduleBufferedPaginationDrain(
                after:
                    0.02
            )

            return
        }

        guard
            !isLoadingPage,
            !reachedEnd
        else {
            return
        }

        let remaining =
            tableView.contentSize.height -
            (
                tableView.contentOffset.y +
                tableView.bounds.size.height
            )

        if remaining < 900.0 &&
            magnistraUserInitiatedPagination(tableView) {
            requestNextPage()
        }
    }
}
