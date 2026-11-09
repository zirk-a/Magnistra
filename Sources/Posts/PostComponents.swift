// Overview: Main post cell (MagnistraPostCell): lifecycle and layout.
import Foundation
import UIKit
import Security
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration



final class MagnistraPostCell:
    UITableViewCell
{
    var configuredPostForImageResume:
        MagnistraRealPost?

    let cardView = UIView()
    let avatarView = UIImageView()
    let usernameLabel = UILabel()
    let locationLabel = UILabel()
    let headerLine = UIView()
    let photoView = UIImageView()

    let carouselLoadingSpinner = UIActivityIndicatorView(style: .white)
    var carouselTransitionInProgress = false
    let carouselPageLabel = UILabel()
    let carouselPlayButton = MagnistraVideoGlyphButton(frame: CGRect.zero)
    let carouselMuteButton = MagnistraVideoGlyphButton(frame: CGRect.zero)
    let carouselFullscreenButton = MagnistraVideoGlyphButton(frame: CGRect.zero)
    var carouselIndex = 0

    let photoMusicFullscreenButton =
        MagnistraVideoGlyphButton(
            frame: CGRect.zero
        )
    let footerLine = UIView()
    let likesLabel = MagnistraPostActionBarLabel()
    let captionAuthorLabel = UILabel()
    let captionBulletLabel = UILabel()
    let captionFirstLineLabel = UILabel()
    let captionContinuationLabel = UILabel()
    let captionAuthorHitButton = UIButton(type: .custom)
    let moreButton = UIButton(type: .custom)
    let commentsButton = UIButton(type: .custom)
    let commentPreviewOne = MagnistraCommentPreviewView()
    let commentPreviewTwo = MagnistraCommentPreviewView()
    let timeLabel = UILabel()

    let followButton =
        UIButton(type: .custom)

    static var transientFollowingMediaIDs = Set<String>()

    static let postMutationQueue:
        OperationQueue = {
            let queue =
                OperationQueue()

            queue.maxConcurrentOperationCount =
                1

            return queue
        }()

    var actionLiked:
        Bool? = nil

    var actionSaved:
        Bool? = nil

    var actionFollowing:
        Bool? = nil

    var actionLikeCount:
        Int? = nil

    var actionReposted:
        Bool? = nil

    var actionRepostCount:
        Int? = nil

    var onProfileTap: (() -> Void)?
    var onCaptionToggle: (() -> Void)?
    var onCommentsTap: (() -> Void)?

    var photoLoadToken: String? = nil
    var avatarLoadToken: String? = nil
    var currentPost: MagnistraRealPost? = nil
    var savedMetadataPending = false
    var currentExpanded = false
    var currentCaptionHeight: CGFloat = 18.0
    var currentShowToggle = false
    var currentAuthorHitWidth: CGFloat = 44.0
    var lastLayoutWidth: CGFloat = -1.0
    var lastLayoutHeight: CGFloat = -1.0

    static let loadingPostPalette: [UIColor] =
        (0..<9).map { magnistraProfileGridPlaceholderColor(for: $0) }

    static let magnistraBlue =
        UIColor(
            red: 0.24,
            green: 0.44,
            blue: 0.63,
            alpha: 1.0
        )

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = UIColor(white: 0.94, alpha: 1.0)
        contentView.backgroundColor = UIColor(white: 0.94, alpha: 1.0)

        cardView.backgroundColor = UIColor.white
        contentView.addSubview(cardView)

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 15.0
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action: #selector(profileTapped)
            )
        )
        cardView.addSubview(avatarView)

        usernameLabel.backgroundColor = UIColor.clear
        usernameLabel.textColor = MagnistraPostCell.magnistraBlue
        usernameLabel.font = UIFont.boldSystemFont(ofSize: 13.0)
        usernameLabel.isUserInteractionEnabled = true
        usernameLabel.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action: #selector(profileTapped)
            )
        )
        cardView.addSubview(usernameLabel)

        locationLabel.backgroundColor = UIColor.clear
        locationLabel.textColor = UIColor(white: 0.50, alpha: 1.0)
        locationLabel.font = UIFont.systemFont(ofSize: 10.5)
        cardView.addSubview(locationLabel)

        headerLine.backgroundColor = UIColor(white: 0.83, alpha: 1.0)
        cardView.addSubview(headerLine)

        photoView.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        cardView.addSubview(photoView)
        carouselLoadingSpinner.hidesWhenStopped = true
        carouselLoadingSpinner.stopAnimating()
        cardView.addSubview(carouselLoadingSpinner)

        photoView.isUserInteractionEnabled =
            true

        let photoLongPress =
            UILongPressGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        normalPhotoLongPressed(
                            _:
                        )
                    )
            )

        photoLongPress.minimumPressDuration =
            0.45

        photoView.addGestureRecognizer(
            photoLongPress
        )
        let carouselLeft = UISwipeGestureRecognizer(
            target: self, action: #selector(carouselSwiped(_:)))
        carouselLeft.direction = .left
        photoView.addGestureRecognizer(carouselLeft)
        let carouselRight = UISwipeGestureRecognizer(
            target: self, action: #selector(carouselSwiped(_:)))
        carouselRight.direction = .right
        photoView.addGestureRecognizer(carouselRight)

        let carouselVideoTap = UITapGestureRecognizer(
            target: self, action: #selector(carouselVideoSurfaceTapped(_:)))
        carouselVideoTap.cancelsTouchesInView = false
        photoView.addGestureRecognizer(carouselVideoTap)

        carouselPageLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.58)
        carouselPageLabel.textColor = .white
        carouselPageLabel.textAlignment = .center
        carouselPageLabel.font = UIFont.boldSystemFont(ofSize: 11.0)
        carouselPageLabel.layer.cornerRadius = 6.0
        carouselPageLabel.clipsToBounds = true
        carouselPageLabel.isHidden = true
        cardView.addSubview(carouselPageLabel)

        carouselPlayButton.glyphKind = .play
        carouselPlayButton.isHidden = true
        carouselPlayButton.addTarget(self,
            action: #selector(carouselPlayTapped), for: .touchUpInside)
        cardView.addSubview(carouselPlayButton)

        carouselMuteButton.glyphKind = .volume
        carouselMuteButton.isHidden = true
        carouselMuteButton.addTarget(self,
            action: #selector(carouselMuteTapped), for: .touchUpInside)
        cardView.addSubview(carouselMuteButton)

        carouselFullscreenButton.glyphKind = .fullscreen
        carouselFullscreenButton.isHidden = true
        carouselFullscreenButton.addTarget(self,
            action: #selector(carouselFullscreenTapped), for: .touchUpInside)
        cardView.addSubview(carouselFullscreenButton)

        photoMusicFullscreenButton.glyphKind =
            .fullscreen

        photoMusicFullscreenButton.isHidden =
            true
        installHomePhotoMusicLongPressIfNeeded()

        photoMusicFullscreenButton.addTarget(
            self,
            action:
                #selector(
                    photoMusicFullscreenTapped
                ),
            for:
                .touchUpInside
        )

        contentView.addSubview(
            photoMusicFullscreenButton
        )

        footerLine.backgroundColor = UIColor(white: 0.84, alpha: 1.0)
        cardView.addSubview(footerLine)

        likesLabel.backgroundColor = UIColor.clear
        likesLabel.textColor = UIColor(white: 0.18, alpha: 1.0)
        likesLabel.font = UIFont.boldSystemFont(ofSize: 13.0)
        cardView.addSubview(likesLabel)

        likesLabel.onLikeTap = {
            [weak self] in
            self?.postLikeTapped()
        }

        likesLabel.onCommentsTap = {
            [weak self] in
            self?.onCommentsTap?()
        }

        likesLabel.onRepostTap = {
            [weak self] in
            self?.postRepostTapped()
        }

        likesLabel.onShareTap = {
            [weak self] in
            self?.postShareTapped()
        }

        likesLabel.onSaveTap = {
            [weak self] in
            self?.postSaveTapped()
        }

        followButton.backgroundColor =
            UIColor.clear
        followButton.setImage(nil, for: .normal)
        followButton.setTitle("Follow", for: .normal)
        followButton.setTitleColor(MagnistraPostCell.magnistraBlue, for: .normal)
        followButton.accessibilityLabel = "Follow"
        followButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize: 13.0
            )
        followButton.contentHorizontalAlignment =
            .right
        followButton.isUserInteractionEnabled =
            true
        followButton.addTarget(
            self,
            action:
                #selector(
                    postFollowTapped
                ),
            for:
                .touchUpInside
        )
        cardView.addSubview(followButton)

        captionAuthorLabel.backgroundColor = UIColor.clear
        captionAuthorLabel.textColor = MagnistraPostCell.magnistraBlue
        captionAuthorLabel.font = UIFont.boldSystemFont(ofSize: 13.0)
        cardView.addSubview(captionAuthorLabel)

        captionBulletLabel.backgroundColor = UIColor.clear
        captionBulletLabel.textColor = UIColor(white: 0.48, alpha: 1.0)
        captionBulletLabel.font = UIFont.systemFont(ofSize: 13.0)
        captionBulletLabel.text = "•"
        captionBulletLabel.textAlignment = .center
        cardView.addSubview(captionBulletLabel)

        captionFirstLineLabel.backgroundColor = UIColor.clear
        captionFirstLineLabel.textColor = UIColor(white: 0.24, alpha: 1.0)
        captionFirstLineLabel.font = UIFont.systemFont(ofSize: 13.0)
        captionFirstLineLabel.numberOfLines = 1
        captionFirstLineLabel.lineBreakMode = .byClipping
        cardView.addSubview(captionFirstLineLabel)

        captionContinuationLabel.backgroundColor = UIColor.clear
        captionContinuationLabel.textColor = UIColor(white: 0.24, alpha: 1.0)
        captionContinuationLabel.font = UIFont.systemFont(ofSize: 13.0)
        captionContinuationLabel.numberOfLines = 1
        captionContinuationLabel.lineBreakMode = .byWordWrapping
        cardView.addSubview(captionContinuationLabel)

        captionAuthorHitButton.backgroundColor = UIColor.clear
        captionAuthorHitButton.addTarget(
            self,
            action: #selector(profileTapped),
            for: .touchUpInside
        )
        cardView.addSubview(captionAuthorHitButton)

        moreButton.setTitleColor(
            MagnistraPostCell.magnistraBlue,
            for: .normal
        )
        moreButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 11.0)
        moreButton.contentHorizontalAlignment = .left
        moreButton.addTarget(
            self,
            action: #selector(captionToggleTapped),
            for: .touchUpInside
        )
        cardView.addSubview(moreButton)

        commentsButton.setTitleColor(
            MagnistraPostCell.magnistraBlue,
            for: .normal
        )
        commentsButton.titleLabel?.font =
            UIFont.boldSystemFont(ofSize: 11.0)
        commentsButton.contentHorizontalAlignment = .left
        commentsButton.addTarget(
            self,
            action: #selector(commentsTapped),
            for: .touchUpInside
        )
        cardView.addSubview(commentsButton)

        cardView.addSubview(commentPreviewOne)
        cardView.addSubview(commentPreviewTwo)

        timeLabel.backgroundColor = UIColor.clear
        timeLabel.textColor = UIColor(white: 0.62, alpha: 1.0)
        timeLabel.font = UIFont.systemFont(ofSize: 9.5)
        cardView.addSubview(timeLabel)

        photoLongPress.cancelsTouchesInView =
            true

        if
            let photoRecognizers =
                photoView.gestureRecognizers
        {
            for recognizer in
                photoRecognizers
            {
                if
                    let tap =
                        recognizer
                            as?
                            UITapGestureRecognizer
                {
                    tap.require(
                        toFail:
                            photoLongPress
                    )
                }
            }
        }

}

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        actionLiked = nil
        actionSaved = nil
        actionFollowing = nil
        actionLikeCount = nil
        actionReposted = nil
        actionRepostCount = nil
        followButton.setImage(nil, for: .normal)
        followButton.setTitle("Follow", for: .normal)
        followButton.setTitleColor(MagnistraPostCell.magnistraBlue, for: .normal)
        followButton.isHidden = false
        followButton.accessibilityLabel = "Follow"

        configuredPostForImageResume =
            nil

        super.prepareForReuse()

        photoLoadToken = nil
        avatarLoadToken = nil
        onProfileTap = nil
        carouselLoadingSpinner.stopAnimating()
        carouselTransitionInProgress = false
        photoView.subviews.filter { $0.tag == 93210 }.forEach { $0.removeFromSuperview() }
        onCaptionToggle = nil
        onCommentsTap = nil
        onPhotoMusicImageFailure = nil
        if let post = currentPost,
           carouselIndex < post.carouselMedia.count {
            MagnistraInlineVideoPlayer.shared.suspendForScrollIfMediaID(
                post.carouselMedia[carouselIndex].mediaID)
        }
        currentPost = nil
        carouselIndex = 0
        carouselPageLabel.isHidden = true
        carouselPlayButton.isHidden = true
        carouselMuteButton.isHidden = true
        carouselFullscreenButton.isHidden = true
        currentExpanded = false

        avatarView.image = nil
        photoView.image = nil
        usernameLabel.text = nil
        locationLabel.text = nil
        likesLabel.text = nil
        likesLabel.reset()
        captionAuthorLabel.text = nil
        captionFirstLineLabel.text = nil
        captionContinuationLabel.text = nil
        timeLabel.text = nil
        moreButton.setTitle(nil, for: .normal)
        commentsButton.setTitle(nil, for: .normal)
        commentPreviewOne.configure(nil)
        commentPreviewTwo.configure(nil)

        lastLayoutWidth = -1.0
        lastLayoutHeight = -1.0
    }

    struct CaptionLayout {
        let authorWidth: CGFloat
        let bulletWidth: CGFloat
        let firstLine: String
        let continuation: String
        let continuationHeight: CGFloat
        let totalHeight: CGFloat
        let showToggle: Bool
    }

    final class CaptionLayoutBox: NSObject {
        let value: CaptionLayout
        init(_ value: CaptionLayout) {
            self.value = value
            super.init()
        }
    }

    static let captionLayoutCache: NSCache<NSString, CaptionLayoutBox> = {
        let cache = NSCache<NSString, CaptionLayoutBox>()
        cache.countLimit = 240
        return cache
    }()

    static let rowHeightCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 320
        return cache
    }()

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let post = currentPost else {
            return
        }

        let width = contentView.bounds.size.width
        let height = contentView.bounds.size.height

        if
            abs(width - lastLayoutWidth) < 0.5 &&
            abs(height - lastLayoutHeight) < 0.5
        {
            return
        }

        lastLayoutWidth = width
        lastLayoutHeight = height

        let metrics =
            MagnistraPostCell.cachedCaptionLayout(
                post: post,
                expanded: currentExpanded,
                width: width
            )

        currentCaptionHeight =
            metrics.totalHeight
        currentShowToggle =
            metrics.showToggle
        currentAuthorHitWidth =
            metrics.authorWidth

        let headerHeight: CGFloat = 46.0
        let photoHeight = MagnistraPostCell.mediaBoxHeight(post: post, width: width)

        cardView.frame =
            CGRect(
                x: 0.0,
                y: 0.0,
                width: width,
                height: max(1.0, height - 10.0)
            )

        avatarView.frame =
            CGRect(
                x: 8.0,
                y: 8.0,
                width: 30.0,
                height: 30.0
            )

        usernameLabel.frame =
            CGRect(
                x: 46.0,
                y:
                    (
                        !post.location.isEmpty ||
                        (
                            post.videoURL == nil &&
                            post.musicAudioURL != nil
                        )
                    )
                        ? 7.0
                        : 14.0,
                width: width - 54.0,
                height: 18.0
            )

        let followCaption = followButton.title(for: .normal) ?? "Follow"
        let measuredCaptionWidth = followButton.titleLabel?.sizeThatFits(
            CGSize(width: 80.0, height: 24.0)).width ?? 0.0
        let textWidth = min(80.0, max(measuredCaptionWidth,
            followCaption == "Following" ? 66.0 : 42.0))
        let secondaryLineRight: CGFloat = followButton.isHidden
            ? width - 8.0 : max(46.0, width - 8.0 - textWidth - 6.0)
        locationLabel.frame = CGRect(
            x: 46.0, y: 24.0,
            width: max(0.0, secondaryLineRight - 46.0),
            height: 15.0)
        locationLabel.numberOfLines = 1
        locationLabel.lineBreakMode = .byTruncatingTail

        followButton.frame =
            CGRect(
                x: max(0.0, width - 88.0),
                y: 10.0,
                width: 80.0,
                height: 24.0
            )

        headerLine.frame =
            CGRect(
                x: 0.0,
                y: headerHeight - 1.0,
                width: width,
                height: 1.0
            )

        photoView.frame =
            CGRect(
                x: 0.0,
                y: headerHeight,
                width: width,
                height: photoHeight
            )
        carouselLoadingSpinner.center = CGPoint(
            x: width / 2.0, y: headerHeight + photoHeight / 2.0)
        carouselPageLabel.frame = CGRect(
            x: max(0.0, width - 61.0),
            y: headerHeight + 9.0,
            width: 51.0,
            height: 23.0)

        carouselPlayButton.frame = CGRect(
            x: 10.0,
            y: headerHeight + 9.0,
            width: 30.0,
            height: 30.0)
        carouselMuteButton.frame = CGRect(
            x: 8.0,
            y: headerHeight + max(0.0, photoHeight - 38.0),
            width: 30.0,
            height: 30.0)
        carouselFullscreenButton.frame = CGRect(
            x: max(0.0, width - 38.0),
            y: headerHeight + max(0.0, photoHeight - 38.0),
            width: 30.0,
            height: 30.0)

        let footerY =
            headerHeight +
            photoHeight

        footerLine.frame =
            CGRect(
                x: 0.0,
                y: footerY,
                width: width,
                height: 1.0
            )

        likesLabel.frame =
            CGRect(
                x: 10.0,
                y: footerY + 13.0,
                width: width - 20.0,
                height: 20.0
            )

        let captionY =
            footerY +
            43.0

        captionAuthorLabel.frame =
            CGRect(
                x: 10.0,
                y: captionY,
                width: metrics.authorWidth,
                height: 18.0
            )

        captionBulletLabel.frame =
            CGRect(
                x:
                    10.0 +
                    metrics.authorWidth,
                y: captionY,
                width: metrics.bulletWidth,
                height: 18.0
            )

        captionFirstLineLabel.frame =
            CGRect(
                x:
                    10.0 +
                    metrics.authorWidth +
                    metrics.bulletWidth,
                y: captionY,
                width:
                    max(
                        24.0,
                        width -
                        20.0 -
                        metrics.authorWidth -
                        metrics.bulletWidth
                    ),
                height: 18.0
            )

        captionContinuationLabel.frame =
            CGRect(
                x: 10.0,
                y: captionY + 18.0,
                width: max(40.0, width - 20.0),
                height:
                    metrics.continuationHeight
            )

        captionAuthorHitButton.frame =
            CGRect(
                x: 10.0,
                y: captionY - 1.0,
                width: metrics.authorWidth,
                height: 20.0
            )

        let toggleY =
            captionY +
            metrics.totalHeight

        moreButton.frame =
            CGRect(
                x: 10.0,
                y: toggleY,
                width: 70.0,
                height: 18.0
            )

        var commentsY =
            toggleY +
            (metrics.showToggle ? 18.0 : 0.0)

        let previewCount =
            min(
                2,
                post.previewComments.count
            )

        let showCommentsButton =
            post.commentCount > 0 ||
            previewCount > 0

        commentsButton.frame =
            CGRect(
                x: 10.0,
                y: commentsY,
                width: width - 20.0,
                height:
                    showCommentsButton
                        ? 18.0
                        : 0.0
            )

        if showCommentsButton {
            commentsY += 18.0
        }

        commentPreviewOne.frame =
            CGRect(
                x: 10.0,
                y: commentsY,
                width: width - 20.0,
                height:
                    previewCount >= 1
                        ? 18.0
                        : 0.0
            )

        if previewCount >= 1 {
            commentsY += 18.0
        }

        commentPreviewTwo.frame =
            CGRect(
                x: 10.0,
                y: commentsY,
                width: width - 20.0,
                height:
                    previewCount >= 2
                        ? 18.0
                        : 0.0
            )

        if previewCount >= 2 {
            commentsY += 18.0
        }

        let timeY =
            commentsY +
            2.0

        timeLabel.frame =
            CGRect(
                x: 10.0,
                y: timeY,
                width: width - 20.0,
                height: 14.0
            )

        let photoRect =
            cardView.convert(
                photoView.frame,
                to:
                    contentView
            )

        photoMusicFullscreenButton.frame =
            CGRect(
                x:
                    max(
                        photoRect.minX,
                        photoRect.maxX -
                        38.0
                    ),
                y:
                    max(
                        photoRect.minY,
                        photoRect.maxY -
                        38.0
                    ),
                width:
                    30.0,
                height:
                    30.0
            )

        if
            !photoMusicFullscreenButton
                .isHidden
        {
            contentView
                .bringSubviewToFront(
                    photoMusicFullscreenButton
                )
        }

}

    var magnistraSavedGridPreviewEnabled = false

    var onPhotoMusicImageFailure:
        (() -> Void)? = nil

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil,
           let post = currentPost,
           carouselIndex < post.carouselMedia.count {
            MagnistraInlineVideoPlayer.shared.suspendForScrollIfMediaID(
                post.carouselMedia[carouselIndex].mediaID)
        }
        refreshCarouselVideoControls()
    }

    override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?
    ) -> UIView? {
        if
            !photoMusicFullscreenButton
                .isHidden
        {
            let local =
                photoMusicFullscreenButton
                    .convert(
                        point,
                        from:
                            self
                    )

            if
                photoMusicFullscreenButton
                    .point(
                        inside:
                            local,
                        with:
                            event
                    )
            {
                return
                    photoMusicFullscreenButton
            }
        }

        return super.hitTest(
            point,
            with:
                event
        )
    }

}

