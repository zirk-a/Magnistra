// Overview: Home feed: table view rows, opening profiles and comments, caption toggle.
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


    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection
            section: Int
    ) -> Int {
        return posts.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt
            indexPath: IndexPath
    ) -> UITableViewCell {
        let cell:
            MagnistraPostCell

        if let reused =
            tableView.dequeueReusableCell(
                withIdentifier:
                    postReuseID
            ) as? MagnistraPostCell
        {
            cell = reused
        } else {
            cell =
                MagnistraPostCell(
                    style: .default,
                    reuseIdentifier:
                        postReuseID
                )
        }

        let post =
            posts[
                indexPath.row
            ]

        let expanded =
            expandedPostIDs
                .contains(
                    post.mediaID
                )

        cell.onProfileTap = {
            [weak self] in

            self?
                .openProfile(
                    post
                )
        }

        cell.onCaptionToggle = {
            [weak self] in

            self?
                .toggleCaption(
                    mediaID:
                        post.mediaID
                )
        }

        cell.onCommentsTap = {
            [weak self] in

            self?
                .openComments(
                    post
                )
        }

        cell.configure(
            post: post,
            avatarVariant:
                indexPath.row,
            expanded:
                expanded
        )

        configureHomePhotoMusicOverlay(in: cell, post: post, tableView: tableView)
        configureHomeVideoOverlay(in: cell, post: post, tableView: tableView)

        return cell
    }


    // A reused post cell must discard the previous photo-music controls first.
    // Keep the failure callback and the overlay creation in their original order.
    private func configureHomePhotoMusicOverlay(
        in cell: MagnistraPostCell,
        post: MagnistraRealPost,
        tableView: UITableView
    ) {
        cell.onPhotoMusicImageFailure = nil

        if
            post.videoURL == nil,
            post.musicAudioURL != nil
        {
            let failedMediaID = post.mediaID
            cell.onPhotoMusicImageFailure = { [weak self, weak cell] in

                DispatchQueue.main.async { [weak self, weak cell] in
                    guard let owner = self, let shownCell = cell,
                          let current = owner.tableView.indexPath(for: shownCell),
                          current.row < owner.posts.count,
                          owner.posts[current.row].mediaID == failedMediaID else { return }
                    shownCell.resumeDeferredPhotoLoadIfNeeded()
                }
            }
        }

        cell.contentView
            .viewWithTag(
                MagnistraPhotoMusicUITags.cover
            )?
            .removeFromSuperview()

        cell.contentView
            .viewWithTag(
                MagnistraPhotoMusicUITags.status
            )?
            .removeFromSuperview()

        if
            post.videoURL == nil,
            post.musicAudioURL != nil
        {
            let mediaWidth =
                max(
                    1.0,
                    tableView.bounds
                        .size.width
                )

            let photoTapButton =
                MagnistraPhotoMusicButton(
                    frame:
                        CGRect(
                            x: 0.0,
                            y: 46.0,
                            width:
                                mediaWidth,
                            height:
                                mediaWidth
                        )
                )

            photoTapButton.tag =
                MagnistraPhotoMusicUITags.cover

            photoTapButton.mediaID =
                post.mediaID

            photoTapButton.backgroundColor =
                UIColor.clear

            photoTapButton.setTitle(
                nil,
                for:
                    .normal
            )

            photoTapButton.addTarget(
                self,
                action:
                    #selector(
                        photoMusicTapped(
                            _:
                        )
                    ),
                for:
                    .touchUpInside
            )

            let musicHold = UILongPressGestureRecognizer(
                target: self, action: #selector(homeMusicCoverHeld(_:)))
            musicHold.minimumPressDuration = 0.45
            musicHold.cancelsTouchesInView = true
            photoTapButton.addGestureRecognizer(musicHold)

            cell.contentView
                .addSubview(
                    photoTapButton
                )

            let musicStatus =
                MagnistraVideoGlyphButton(
                    frame:
                        CGRect(
                            x:
                                mediaWidth -
                                38.0,
                            y: 54.0,
                            width: 30.0,
                            height: 30.0
                        )
                )

            musicStatus.tag =
                MagnistraPhotoMusicUITags.status

            musicStatus.mediaID =
                post.mediaID

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
                for:
                    .touchUpInside
            )

            cell.contentView
                .addSubview(
                    musicStatus
                )
        }
    }

    // Reset player views before preparing the inline video for this post.
    private func configureHomeVideoOverlay(
        in cell: MagnistraPostCell,
        post: MagnistraRealPost,
        tableView: UITableView
    ) {
        let tags = [
            MagnistraVideoUITags.surface,
            MagnistraVideoUITags.status,
            MagnistraVideoUITags.mute,
            MagnistraVideoUITags.fullscreen
        ]

        for tag in tags {
            cell.contentView
                .viewWithTag(tag)?
                .removeFromSuperview()
        }

        MagnistraInlineVideoPlayer
            .shared
            .prepare(
                hostView:
                    cell.contentView,
                mediaID:
                    post.mediaID
            )

        if post.videoURL != nil {
            let mediaWidth =
                max(
                    1.0,
                    tableView.bounds
                        .size.width
                )

            let surface =
                MagnistraVideoSurfaceButton(
                    frame:
                        CGRect(
                            x: 0.0,
                            y: 46.0,
                            width: mediaWidth,
                            height: mediaWidth
                        )
                )

            surface.tag =
                MagnistraVideoUITags
                    .surface

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
                for:
                    .touchUpInside
            )

            cell.contentView
                .addSubview(surface)

            let status =
                MagnistraVideoGlyphButton(
                    frame:
                        CGRect(
                            x:
                                mediaWidth -
                                38.0,
                            y: 54.0,
                            width: 30.0,
                            height: 30.0
                        )
                )

            status.tag =
                MagnistraVideoUITags
                    .status

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
                for:
                    .touchUpInside
            )

            cell.contentView
                .addSubview(status)

            syncVideoControls(
                in:
                    cell.contentView,
                post:
                    post
            )
        }
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt
            indexPath: IndexPath
    ) -> CGFloat {
        let post =
            posts[
                indexPath.row
            ]

        let homeTableWidth = tableView.bounds.size.width
        if homeRowHeightCacheWidth != homeTableWidth {
            homeRowHeightCacheWidth = homeTableWidth
            homeRowHeightCache.removeAll(keepingCapacity: true)
        }
        if let cached = homeRowHeightCache[indexPath.row] {
            return cached
        }
        let computedHomeRowHeight = MagnistraPostCell
            .rowHeight(
                post: post,
                expanded:
                    expandedPostIDs
                        .contains(
                            post.mediaID
                        ),
                width:
                    tableView
                        .bounds
                        .size
                        .width
            )
        if homeRowHeightCache.count >= 512 {
            homeRowHeightCache.removeAll(keepingCapacity: true)
        }
        homeRowHeightCache[indexPath.row] = computedHomeRowHeight
        return computedHomeRowHeight
    }

    func openProfile(
        _ post:
            MagnistraRealPost
    ) {
        let controller =
            MagnistraProfileViewController(
                post: post
            )

        navigationController?
            .pushViewController(
                controller,
                animated: true
            )
    }

    func openComments(
        _ post:
            MagnistraRealPost
    ) {
        let controller =
            MagnistraCommentsViewController(
                post: post
            )

        navigationController?
            .pushViewController(
                controller,
                animated: true
            )
    }

    func toggleCaption(
        mediaID: String
    ) {
        homeRowHeightCache.removeAll(keepingCapacity: true)
        if expandedPostIDs
            .contains(
                mediaID
            )
        {
            expandedPostIDs
                .remove(
                    mediaID
                )
        } else {
            expandedPostIDs
                .insert(
                    mediaID
                )
        }

        guard let index =
            posts.firstIndex(
                where: {
                    $0.mediaID ==
                        mediaID
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

        tableView.reloadRows(
            at: [path],
            with: .none
        )
    }
}
