// Overview: Post cell actions: like, save, follow, repost and share.
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

extension MagnistraPostCell {


    func postShowActionError(
        _ text: String
    ) {
        let alert =
            UIAlertView(
                title: "Instagram",
                message: text,
                delegate: nil,
                cancelButtonTitle: "OK"
            )

        alert.show()
    }

    func postLikeTapped() {
        guard let post =
            currentPost
        else {
            return
        }

        let cached =
            MagnistraHomeService
                .cachedPostInteractionState(
                    mediaID:
                        post.mediaID
                )

        let current =
            actionLiked ??
            cached.liked

        let oldCount =
            actionLikeCount ??
            MagnistraHomeService
                .cachedPostLikeCount(
                    mediaID:
                        post.mediaID,
                    fallback:
                        post.likes
                )

        let target =
            !current

        let newCount =
            max(
                0,
                oldCount +
                (
                    target
                        ? 1
                        : -1
                )
            )

        actionLiked =
            target

        actionLikeCount =
            newCount

        likesLabel.setLikeState(
            target,
            likes:
                newCount
        )

        MagnistraHomeService
            .setCachedPostInteractionState(
                mediaID:
                    post.mediaID,
                liked:
                    target,
                saved:
                    nil,
                likeCount:
                    newCount
            )

        MagnistraPostCell
            .postMutationQueue
            .addOperation {
                [weak self] in

                do {
                    try MagnistraHomeService
                        .setPostLiked(
                            mediaID:
                                post.mediaID,
                            liked:
                                target
                        )
                } catch {
                    let message =
                        error.localizedDescription

                    MagnistraHomeService
                        .setCachedPostInteractionState(
                            mediaID:
                                post.mediaID,
                            liked:
                                current,
                            saved:
                                nil,
                            likeCount:
                                oldCount
                        )

                    OperationQueue.main
                        .addOperation {
                            [weak self] in

                            guard let self =
                                self
                            else {
                                return
                            }

                            if
                                self.currentPost?
                                    .mediaID ==
                                post.mediaID
                            {
                                self.actionLiked =
                                    current

                                self.actionLikeCount =
                                    oldCount

                                self.likesLabel
                                    .setLikeState(
                                        current,
                                        likes:
                                            oldCount
                                    )
                            }

                            self.postShowActionError(
                                message
                            )
                        }
                }
            }
    }

    func postSaveTapped() {
        guard let post =
            currentPost
        else {
            return
        }

        let cached =
            MagnistraHomeService
                .cachedPostInteractionState(
                    mediaID:
                        post.mediaID
                )

        let current =
            actionSaved ??
            cached.saved

        let target =
            !current

        actionSaved =
            target

        likesLabel.setSaveState(
            target
        )

        MagnistraHomeService
            .setCachedPostInteractionState(
                mediaID:
                    post.mediaID,
                liked:
                    nil,
                saved:
                    target,
                likeCount:
                    nil
            )

        MagnistraPostCell
            .postMutationQueue
            .addOperation {
                [weak self] in

                do {
                    try MagnistraHomeService
                        .setPostSaved(
                            mediaID:
                                post.mediaID,
                            saved:
                                target
                        )
                } catch {
                    let message =
                        error.localizedDescription

                    MagnistraHomeService
                        .setCachedPostInteractionState(
                            mediaID:
                                post.mediaID,
                            liked:
                                nil,
                            saved:
                                current,
                            likeCount:
                                nil
                        )

                    OperationQueue.main
                        .addOperation {
                            [weak self] in

                            guard let self =
                                self
                            else {
                                return
                            }

                            if
                                self.currentPost?
                                    .mediaID ==
                                post.mediaID
                            {
                                self.actionSaved =
                                    current

                                self.likesLabel
                                    .setSaveState(
                                        current
                                    )
                            }

                            self.postShowActionError(
                                message
                            )
                        }
                }
            }
    }

    @objc func postFollowTapped() {
        guard let post =
            currentPost
        else {
            return
        }

        let current =
            actionFollowing ??
            MagnistraHomeService
                .cachedFollowingState(
                    userID:
                        post.userID
                ) ??
            false

        if current { return }
        let target = true
        actionFollowing = target
        MagnistraPostCell.transientFollowingMediaIDs.insert(post.mediaID)
        updatePostFollowButton(post, following: target)

        MagnistraHomeService
            .setCachedFollowingState(
                userID:
                    post.userID,
                following:
                    target
            )

        MagnistraPostCell
            .postMutationQueue
            .addOperation {
                [weak self] in

                do {
                    try MagnistraHomeService
                        .setFollowing(
                            userID:
                                post.userID,
                            mediaID:
                                post.mediaID,
                            following:
                                target
                        )
                } catch {
                    let message =
                        error.localizedDescription

                    MagnistraHomeService
                        .setCachedFollowingState(
                            userID:
                                post.userID,
                            following:
                                current
                        )

                    OperationQueue.main
                        .addOperation {
                            [weak self] in

                            guard let self =
                                self
                            else {
                                return
                            }

                            MagnistraPostCell.transientFollowingMediaIDs.remove(post.mediaID)
                            if self.currentPost?.mediaID == post.mediaID {
                                self.actionFollowing = current
                                self.updatePostFollowButton(post, following: current)
                            }

                            self.postShowActionError(
                                message
                            )
                        }
                }
            }
    }

    func postRepostTapped() {
        guard let post =
            currentPost
        else {
            return
        }

        let cached =
            MagnistraHomeService
                .cachedPostSocialState(
                    mediaID:
                        post.mediaID
                )

        let current =
            actionReposted ??
            cached.reposted

        let oldCount =
            actionRepostCount ??
            cached.reposts

        let target =
            !current

        let newCount =
            max(
                0,
                oldCount +
                (
                    target
                        ? 1
                        : -1
                )
            )

        actionReposted =
            target

        actionRepostCount =
            newCount

        likesLabel.setRepostState(
            target,
            reposts:
                newCount
        )

        MagnistraPostCell
            .postMutationQueue
            .addOperation {
                [weak self] in

                do {
                    let noteID =
                        try MagnistraHomeService
                            .setPostReposted(
                                mediaID:
                                    post.mediaID,
                                reposted:
                                    target
                            )

                    MagnistraHomeService
                        .setCachedPostRepostState(
                            mediaID:
                                post.mediaID,
                            reposted:
                                target,
                            repostCount:
                                newCount,
                            noteID:
                                noteID
                        )
                } catch {
                    let message =
                        error.localizedDescription

                    OperationQueue.main
                        .addOperation {
                            [weak self] in

                            guard let self =
                                self
                            else {
                                return
                            }

                            if
                                self.currentPost?
                                    .mediaID ==
                                post.mediaID
                            {
                                self.actionReposted =
                                    current

                                self.actionRepostCount =
                                    oldCount

                                self.likesLabel
                                    .setRepostState(
                                        current,
                                        reposts:
                                            oldCount
                                    )
                            }

                            self.postShowActionError(
                                message
                            )
                        }
                }
            }
    }

    func postShareTapped() {
        guard let post =
            currentPost
        else {
            return
        }

        var responder:
            UIResponder? =
                self

        while let current =
            responder
        {
            if let controller =
                current as?
                    UIViewController
            {
                let share =
                    MagnistraPostShareViewController(
                        post: post
                    )

                if let navigation =
                    controller
                        .navigationController
                {
                    navigation
                        .pushViewController(
                            share,
                            animated:
                                true
                        )
                } else {
                    controller.present(
                        UINavigationController(
                            rootViewController:
                                share
                        ),
                        animated:
                            true,
                        completion:
                            nil
                    )
                }

                return
            }

            responder =
                current.next
        }
    }

    @objc func profileTapped() {
        onProfileTap?()
    }

    @objc func captionToggleTapped() {
        onCaptionToggle?()
    }

    @objc func commentsTapped() {
        onCommentsTap?()
    }
}
