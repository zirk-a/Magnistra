// Overview: Explore feed: table view rows and scrolling.
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


    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return posts.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let requestedPost =
            posts[
                indexPath.row
            ]
        resolveVisibleSavedVideoIfNeeded(requestedPost)

        if
            let prewarmed =
                prewarmedPostCells
                    .removeValue(
                        forKey:
                            requestedPost.mediaID
                    )
        {
            prewarmAnchorRow =
                max(
                    prewarmAnchorRow,
                    indexPath.row
                )

            scheduleSuccessorCellPrewarm()
            prewarmed.savedMetadataPending = savedPostRequiresMetadata(requestedPost)
            return prewarmed
        }

        prewarmAnchorRow =
            max(
                prewarmAnchorRow,
                indexPath.row
            )

        let post =
            posts[indexPath.row]

        let expanded =
            expandedMediaIDs.contains(
                post.mediaID
            )

        let cell: MagnistraPostCell
        if let reused = tableView.dequeueReusableCell(
            withIdentifier: "MagnistraSharedPostCell"
        ) as? MagnistraPostCell {
            cell = reused
        } else {
            cell = MagnistraPostCell(
                style: .default,
                reuseIdentifier: "MagnistraSharedPostCell"
            )
        }

        cell.onPhotoMusicImageFailure = nil

        cell.onProfileTap = {
            [weak self] in
            guard let self = self else {
                return
            }

            self.navigationController?
                .pushViewController(
                    MagnistraProfileViewController(
                        post: post
                    ),
                    animated: true
                )
        }

        cell.onCaptionToggle = {
            [weak self] in
            guard let self = self else {
                return
            }

            if
                self.expandedMediaIDs
                    .contains(
                        post.mediaID
                    )
            {
                self.expandedMediaIDs
                    .remove(
                        post.mediaID
                    )
            } else {
                self.expandedMediaIDs
                    .insert(
                        post.mediaID
                    )
            }

            self.tableView.reloadRows(
                at: [indexPath],
                with: .none
            )
        }

        cell.onCommentsTap = {
            [weak self] in
            guard let self = self else {
                return
            }

            self.navigationController?
                .pushViewController(
                    MagnistraCommentsViewController(
                        post: post
                    ),
                    animated: true
                )
        }

        cell.configure(
            post: post,
            avatarVariant: indexPath.row,
            expanded: expanded,
            savedGridPreview: magnistraSavedFeed || magnistraRepostsUserID != nil
        )

        installMediaControls(
            in: cell,
            post: post
        )
        cell.savedMetadataPending = savedPostRequiresMetadata(post)

        return cell
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        let post =
            posts[indexPath.row]

        return MagnistraPostCell
            .rowHeight(
                post: post,
                expanded:
                    expandedMediaIDs
                        .contains(
                            post.mediaID
                        ),
                width:
                    tableView.bounds
                        .size.width
            )
    }

    func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {

        if let postCell = cell as? MagnistraPostCell {
            postCell.suspendCarouselVideoForScroll()
        }

        if let surface =
            cell.contentView
                .viewWithTag(
                    MagnistraVideoUITags.surface
                )
                as?
                MagnistraVideoSurfaceButton
        {
            MagnistraInlineVideoPlayer
                .shared
                .suspendForScrollIfMediaID(
                    surface.mediaID
                )
        }

        if let musicStatus =
            cell.contentView
                .viewWithTag(MagnistraPhotoMusicUITags.status)
                as?
                MagnistraVideoGlyphButton
        {
            MagnistraPhotoMusicPlayer
                .shared
                .stopIfMediaID(
                    musicStatus.mediaID
                )
        }
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        unifiedLoadingBand.refresh()
        MagnistraInlineVideoPlayer
            .shared
            .cancelScheduledScrollStopFinish()

        MagnistraPhotoMusicPlayer
            .shared
            .cancelScheduledScrollStopFinish()

        stopActiveVideoIfNeededForScroll()

        guard scrollView === tableView else {
            return
        }
        stopActivePhotoMusicIfNeededForScroll()

        if
            posts.isEmpty ||
            isLoadingPage ||
            reachedEnd
        {
            return
        }

        let remaining =
            tableView.contentSize.height -
            (
                tableView.contentOffset.y +
                tableView.bounds.size.height
            )

        if paginationIsHeavyScroll() {

            paginationScrollPaused =

                true

            return

        }

        paginationScrollPaused =

            false

        if remaining < 700.0 &&
            magnistraUserInitiatedPagination(scrollView) {

            requestNextPage()

        }
    }
}
