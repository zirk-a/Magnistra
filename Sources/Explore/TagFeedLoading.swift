// Overview: Tag feed: cell prewarming, deferred posts and media frames.
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


    func scheduleSuccessorCellPrewarm() {
        NSObject
            .cancelPreviousPerformRequests(
                withTarget:
                    self,
                selector:
                    #selector(
                        prewarmNextSuccessorCell
                    ),
                object:
                    nil
            )

        guard
            prewarmedPostCells.count <
                prewarmCapacity,
            posts.count >
                prewarmAnchorRow + 1
        else {
            return
        }

        let firstRow =
            prewarmAnchorRow + 1

        let endRow =
            min(
                posts.count,
                firstRow + 8
            )

        var heavy:
            [Int] = []

        var normal:
            [Int] = []

        if firstRow < endRow {
            for row in firstRow..<endRow {
                let post =
                    posts[row]

                if
                    prewarmedPostCells[
                        post.mediaID
                    ] != nil ||
                    prewarmCompletedMediaIDs
                        .contains(
                            post.mediaID
                        )
                {
                    continue
                }

                if
                    post.videoURL != nil ||
                    post.musicAudioURL != nil
                {
                    heavy.append(
                        row
                    )
                } else {
                    normal.append(
                        row
                    )
                }
            }
        }

        prewarmQueueRows =
            Array(
                (
                    heavy +
                    normal
                )
                .prefix(
                    prewarmCapacity -
                    prewarmedPostCells.count
                )
            )

        prewarmQueueCursor =
            0

        guard
            !prewarmQueueRows.isEmpty
        else {
            return
        }

        perform(
            #selector(
                prewarmNextSuccessorCell
            ),
            with:
                nil,
            afterDelay:
                0.30
        )
    }

    @objc func prewarmNextSuccessorCell() {
        if
            tableView.isDragging ||
            tableView.isDecelerating
        {
            perform(
                #selector(
                    prewarmNextSuccessorCell
                ),
                with:
                    nil,
                afterDelay:
                    0.12
            )

            return
        }

        guard
            prewarmedPostCells.count <
                prewarmCapacity,
            prewarmQueueCursor <
                prewarmQueueRows.count
        else {
            return
        }

        let row =
            prewarmQueueRows[
                prewarmQueueCursor
            ]

        prewarmQueueCursor +=
            1

        guard
            row <
                posts.count
        else {
            return
        }

        let post =
            posts[row]

        if
            prewarmedPostCells[
                post.mediaID
            ] ==
                nil,
            !prewarmCompletedMediaIDs
                .contains(
                    post.mediaID
                )
        {
            let path =
                IndexPath(
                    row:
                        row,
                    section:
                        0
                )

            let candidate =
                self.tableView(
                    tableView,
                    cellForRowAt:
                        path
                )

            if
                let cell =
                    candidate as?
                    MagnistraPostCell
            {
                prewarmedPostCells[
                    post.mediaID
                ] =
                    cell

                prewarmCompletedMediaIDs
                    .insert(
                        post.mediaID
                    )
            }
        }

        if
            prewarmedPostCells.count <
                prewarmCapacity,
            prewarmQueueCursor <
                prewarmQueueRows.count
        {
            perform(
                #selector(
                    prewarmNextSuccessorCell
                ),
                with:
                    nil,
                afterDelay:
                    0.09
            )
        }
    }

    func installDeferredPosts() {
        guard
            let provider =
                deferredPostsProvider
        else {
            return
        }

        deferredPostsProvider =
            nil

        let tail =
            provider()

        if tail.isEmpty {
            return
        }

        var paths:
            [IndexPath] = []

        for post in tail {
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

            let row =
                posts.count

            posts.append(
                post
            )

            paths.append(
                IndexPath(
                    row: row,
                    section: 0
                )
            )
        }

        if !paths.isEmpty {
            tableView.insertRows(
                at: paths,
                with: .none
            )

            scheduleSuccessorCellPrewarm()
        }
    }

    func mediaFrame() -> CGRect {
        let mediaWidth =
            max(
                1.0,
                tableView.bounds.size.width
            )

        return CGRect(
            x: 0.0,
            y: 46.0,
            width: mediaWidth,
            height: mediaWidth
        )
    }

    func postForMediaID(
        _ mediaID: String
    ) -> MagnistraRealPost? {
        guard
            let index =
                posts.firstIndex(
                    where: {
                        $0.mediaID == mediaID
                    }
                )
        else {
            return nil
        }

        return posts[index]
    }
}
