// Overview: Post cell configuration: rendering a post.
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


    func configure(
        post: MagnistraRealPost,
        avatarVariant: Int,
        expanded: Bool,
        savedGridPreview: Bool = false
    ) {
        magnistraSavedGridPreviewEnabled = savedGridPreview

        photoView.isHidden = savedGridPreview && post.isVideo && post.videoURL == nil
        savedMetadataPending = false
        configuredPostForImageResume =
            post

        if currentPost?.mediaID != post.mediaID {
            carouselIndex = 0
        }
        currentPost = post
        currentExpanded = expanded

        photoView.contentMode =
            post.videoURL == nil
                ? .scaleAspectFit
                : .scaleAspectFill

        photoView.backgroundColor =
            MagnistraPostCell.loadingPostColor(mediaID: post.mediaID)
        carouselLoadingSpinner.stopAnimating()

        photoMusicFullscreenButton.isHidden =
            true

        photoMusicFullscreenButton.isEnabled =
            false

        photoMusicFullscreenButton.mediaID =
            post.mediaID

        if
            post.videoURL == nil &&
            post.musicAudioURL != nil
        {

            photoView.contentMode =
                .scaleAspectFit
        } else {

            photoView.contentMode =
                post.videoURL == nil
                    ? .scaleAspectFit
                    : .scaleAspectFill
        }

        usernameLabel.text = post.username

        configurePostCaption(post, expanded: expanded)
        configurePostComments(post)
        configurePostLocation(post)
        configurePostPhoto(post)
        configurePostAvatar(post, avatarVariant: avatarVariant)
        configurePostSocialActions(post)

        timeLabel.text =
            MagnistraPostCell.relativeTime(
                timestamp: post.takenAt
            )

        lastLayoutWidth = -1.0
        lastLayoutHeight = -1.0
        setNeedsLayout()
    }

    // Keep caption metrics and expansion UI in sync with the configured post.
    private func configurePostCaption(_ post: MagnistraRealPost, expanded: Bool) {
        let metrics =
            MagnistraPostCell.cachedCaptionLayout(
                post: post,
                expanded: expanded,
                width:
                    max(
                        1.0,
                        contentView.bounds.size.width
                    )
            )

        captionAuthorLabel.text =
            post.username

        captionBulletLabel.isHidden =
            post.caption.isEmpty

        captionFirstLineLabel.text =
            metrics.firstLine

        captionContinuationLabel.text =
            metrics.continuation

        captionContinuationLabel.numberOfLines =
            expanded
                ? 0
                : 1

        currentCaptionHeight =
            metrics.totalHeight
        currentShowToggle =
            metrics.showToggle
        currentAuthorHitWidth =
            metrics.authorWidth

        moreButton.isHidden = !metrics.showToggle
        moreButton.setTitle(
            expanded ? "less" : "more",
            for: .normal
        )
    }

    // The preview has exactly two cells; only the visible count may exceed two.
    private func configurePostComments(_ post: MagnistraRealPost) {
        let previewCount =
            min(
                2,
                post.previewComments.count
            )

        let visibleCommentCount =
            max(
                post.commentCount,
                previewCount
            )

        if visibleCommentCount > 0 {
            commentsButton.isHidden = false

            commentsButton.setTitle(
                visibleCommentCount == 1
                    ? "View 1 comment"
                    : "View all \(visibleCommentCount) comments",
                for: .normal
            )
        } else {
            commentsButton.isHidden = true
            commentsButton.setTitle(
                nil,
                for: .normal
            )
        }

        commentPreviewOne.configure(
            previewCount >= 1
                ? post.previewComments[0]
                : nil
        )

        commentPreviewTwo.configure(
            previewCount >= 2
                ? post.previewComments[1]
                : nil
        )
    }

    // Prefer music attribution over a post location when audio is attached.
    private func configurePostLocation(_ post: MagnistraRealPost) {
        if
            post.videoURL == nil,
            post.musicAudioURL != nil,
            let title =
                post.musicTitle,
            !title.isEmpty
        {
            var musicLine =
                "♫ " +
                title

            if
                let artist =
                    post.musicArtist,
                !artist.isEmpty
            {
                musicLine +=
                    " · " +
                    artist
            }

            locationLabel.text =
                musicLine

            locationLabel.textColor =
                UIColor(
                    white:
                        0.42,
                    alpha:
                        1.0
                )

            locationLabel.isHidden =
                false
        } else if
            post.location.isEmpty
        {
            locationLabel.text = nil
            locationLabel.isHidden = true
        } else {
            locationLabel.text =
                post.location

            locationLabel.textColor =
                UIColor(
                    white:
                        0.50,
                    alpha:
                        1.0
                )

            locationLabel.isHidden =
                false
        }
    }

    // Preserve the photo-music, cached-image and regular-image loading paths.
    private func configurePostPhoto(_ post: MagnistraRealPost) {
        let isOrdinaryPhoto =
            post.videoURL == nil &&
            post.musicAudioURL == nil

        let resolvedPhotoCacheKey =
            isOrdinaryPhoto
                ? (
                    "uncrop3:" +
                    post.imageCacheKey
                )
                : post.imageCacheKey

        let resolvedPhotoPath:
            String? =
            isOrdinaryPhoto
                ? nil
                : (
                    post.imagePath
                        .isEmpty
                        ? nil
                        : (
                            post.imagePath
                        )
                )

        let photoKey =
            "post:" +
            resolvedPhotoCacheKey

        photoLoadToken =
            photoKey

        if
            post.videoURL == nil &&
            post.musicAudioURL != nil
        {
            photoView.image =
                MagnistraDecodedImageLoader
                    .shared
                    .gridPreview(
                        stableKey:
                            post.imageCacheKey
                    )
            if photoView.image != nil {
                photoView.backgroundColor = UIColor.black
            }

            MagnistraPhotoMusicImageLoader
                .shared
                .request(
                    path:
                        resolvedPhotoPath,
                    remoteURL:
                        post.imageURL,
                    fallbackURL:
                        post.photoMusicImageURLFallback,
                    stableKey:
                        resolvedPhotoCacheKey,
                    key:
                        photoKey,
                    target:
                        self
                )
        } else if let ready =
            MagnistraDecodedImageLoader
                .shared
                .cachedImage(
                    forKey:
                        photoKey
                )
        {
            photoView.image =
                ready
            photoView.backgroundColor = UIColor.black
        } else {

            photoView.image = magnistraSavedGridPreviewEnabled
                ? MagnistraDecodedImageLoader.shared.gridPreview(
                    stableKey: post.imageCacheKey) : nil
            if photoView.image != nil {
                photoView.backgroundColor = UIColor.black
            }

            MagnistraDecodedImageLoader
                .shared
                .requestImage(
                    path:
                        resolvedPhotoPath,
                    remoteURL:
                        post.imageURL,
                    stableKey:
                        resolvedPhotoCacheKey,
                    key:
                        photoKey,
                    isAvatar:
                        false,
                    target:
                        self
                )
        }

        refreshCarouselDisplay()
    }

    // Use the cached avatar when available and the generated fallback otherwise.
    private func configurePostAvatar(_ post: MagnistraRealPost, avatarVariant: Int) {
        let avatarFallback =
            MagnistraPostCell
                .makeAvatarImage(
                    size:
                        CGSize(
                            width:
                                30.0,
                            height:
                                30.0
                        ),
                    variant:
                        avatarVariant
                )

        let avatarKey =
            "avatar:" +
            post.avatarCacheKey

        avatarLoadToken =
            avatarKey

        if let ready =
            MagnistraDecodedImageLoader
                .shared
                .cachedImage(
                    forKey:
                        avatarKey
                )
        {
            avatarView.image =
                ready
        } else {
            avatarView.image =
                avatarFallback

            if
                post.avatarPath != nil ||
                post.avatarURL != nil
            {
                MagnistraDecodedImageLoader
                    .shared
                    .requestImage(
                        path:
                            post.avatarPath,
                        remoteURL:
                            post.avatarURL,
                        stableKey:
                            post.avatarCacheKey,
                        key:
                            avatarKey,
                        isAvatar:
                            true,
                        target:
                            self
                    )
            }
        }
    }

    // Restore cached social state without triggering a new network request.
    private func configurePostSocialActions(_ post: MagnistraRealPost) {
        let cachedSocialState =
            MagnistraHomeService
                .cachedPostSocialState(
                    mediaID:
                        post.mediaID
                )

        likesLabel.text = nil
        likesLabel.configure(
            likes:
                post.likes,
            comments:
                post.commentCount,
            reposts:
                cachedSocialState.reposts,
            shares:
                cachedSocialState.shares
        )

        actionReposted =
            cachedSocialState.reposted

        actionRepostCount =
            cachedSocialState.reposts

        likesLabel.setRepostState(
            cachedSocialState.reposted,
            reposts:
                cachedSocialState.reposts
        )

        let cachedActionState =
            MagnistraHomeService
                .cachedPostInteractionState(
                    mediaID:
                        post.mediaID
                )

        let cachedLikeCount =
            MagnistraHomeService
                .cachedPostLikeCount(
                    mediaID:
                        post.mediaID,
                    fallback:
                        post.likes
                )

        actionLiked =
            cachedActionState.liked

        actionSaved =
            cachedActionState.saved

        actionLikeCount =
            cachedLikeCount

        likesLabel.setLikeState(
            cachedActionState.liked,
            likes:
                cachedLikeCount
        )

        likesLabel.setSaveState(
            cachedActionState.saved
        )

        if let cachedFollowing =
            MagnistraHomeService
                .cachedFollowingState(
                    userID:
                        post.userID
                )
        {
            actionFollowing =
                cachedFollowing

            updatePostFollowButton(post, following: cachedFollowing)
        } else {
            actionFollowing =
                nil

            updatePostFollowButton(post, following: false)
        }
    }
}
