// Overview: Profile screen (MagnistraProfileViewController): header stats and media grid.
import UIKit
import Security
import QuartzCore
import CoreText
import ImageIO
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import SystemConfiguration

final class MagnistraProfileViewController:
    UIViewController,
    UIScrollViewDelegate
{
    private let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)
    private let profilePaginationDarkTail = UIView()

    private let post: MagnistraRealPost
    private let queue = OperationQueue()
    private let scrollView = UIScrollView()
    private let avatarView = UIImageView()
    private let highlightTray = MagnistraStoryTrayView(frame: .zero)
    private var highlightReels: [MagnistraStoryReel] = []
    private var highlightsRequested = false

    private let postsValueLabel = UILabel()
    private let followersValueLabel = UILabel()
    private let followingValueLabel = UILabel()
    private let postsTitleLabel = UILabel()
    private let followersTitleLabel = UILabel()
    private let followingTitleLabel = UILabel()

    private let fullNameLabel = UILabel()
    private let biographyLabel = UILabel()
    private let statusLabel = UILabel()
    private let followProfileButton = UIButton(type: .custom)
    private let messageProfileButton = UIButton(type: .custom)
    private var profileUserID = ""
    private var profileFollowing = false
    private var profileFollowBusy = false
    private var profileMessageBusy = false
    private var profileIsOwnAccount = false

    private let photosBar = UIView()
    private let photosLabel = UILabel()
    private let photosIconView = UIImageView()
    private let photosIndicator = UIView()
    private let repostsButton = UIButton(type: .custom)

    private var gridViews: [MagnistraProfileGridTile] = []
    private var gridPosts: [MagnistraRealPost] = []
    private var gridKnownMediaIDs = Set<String>()
    private var gridNextMaxID: String? = nil
    private var gridLoading = false
    private var gridReachedEnd = false
    private var gridShowingReposts = false
    private var gridGeneration = 0

    private let gridLoadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private var gridExpectedPostCount = 0
    private var gridFallbackStarted = false

    private var gridProfileLoaded = false
    private var gridProfilePrivate = false
    private var gridPrimaryEmptyResponse = false
    private var gridFallbackRequestStarted = false
    private var gridFailureMessage = ""
    private var gridLoadMoreGestureConsumed = false
    private let gridImageQueue = OperationQueue()
    private var biographyText = ""
    private var statusText = ""

    init(post: MagnistraRealPost) {
        self.post = post
        super.init(nibName: nil, bundle: nil)
        queue.maxConcurrentOperationCount = 1
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = post.username
        view.backgroundColor = UIColor(white: 0.96, alpha: 1.0)

        scrollView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]
        scrollView.delegate = self
        gridImageQueue.maxConcurrentOperationCount = 2
        view.addSubview(scrollView)
        profilePaginationDarkTail.backgroundColor = UIColor(white: 0.10, alpha: 0.88)
        profilePaginationDarkTail.isUserInteractionEnabled = false
        profilePaginationDarkTail.isHidden = true
        scrollView.addSubview(profilePaginationDarkTail)
        scrollView.sendSubviewToBack(profilePaginationDarkTail)

        avatarView.backgroundColor = MagnistraPostCell.magnistraBlue
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.borderWidth = 1.0
        avatarView.layer.borderColor =
            UIColor(white: 0.72, alpha: 1.0).cgColor

        if
            let path =
                post.avatarPath
        {
            avatarView.image =
                UIImage(
                    contentsOfFile:
                        path
                )
        } else if
            let remoteURL =
                post.avatarURL,
            !remoteURL.isEmpty
        {
            let stableKey =
                post.avatarCacheKey

            queue.addOperation {
                [weak self] in

                guard
                    let path =
                        MagnistraHomeService
                            .materializeFeedImage(
                                url:
                                    remoteURL,
                                stableKey:
                                    stableKey,
                                isAvatar:
                                    true
                            ),
                    let image =
                        UIImage(
                            contentsOfFile:
                                path
                        )
                else {
                    return
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?
                            .avatarView
                            .image =
                            image
                    }
            }
        }
        scrollView.addSubview(avatarView)

        configureStatValue(postsValueLabel)
        configureStatValue(followersValueLabel)
        configureStatValue(followingValueLabel)

        configureStatTitle(
            postsTitleLabel,
            text: "posts"
        )
        configureStatTitle(
            followersTitleLabel,
            text: "followers"
        )
        configureStatTitle(
            followingTitleLabel,
            text: "following"
        )

        postsValueLabel.text = "—"
        followersValueLabel.text = "—"
        followingValueLabel.text = "—"

        fullNameLabel.backgroundColor = UIColor.clear
        fullNameLabel.textColor = UIColor(white: 0.28, alpha: 1.0)
        fullNameLabel.font = UIFont.boldSystemFont(ofSize: 12.5)
        fullNameLabel.text =
            post.fullName.isEmpty
                ? post.username
                : post.fullName
        scrollView.addSubview(fullNameLabel)

        biographyLabel.backgroundColor = UIColor.clear
        biographyLabel.textColor = UIColor(white: 0.34, alpha: 1.0)
        biographyLabel.font = UIFont.systemFont(ofSize: 12.0)
        biographyLabel.numberOfLines = 0
        biographyLabel.lineBreakMode = .byWordWrapping
        scrollView.addSubview(biographyLabel)

        statusLabel.backgroundColor = UIColor.clear
        statusLabel.textColor = UIColor(white: 0.58, alpha: 1.0)
        statusLabel.font = UIFont.systemFont(ofSize: 10.0)
        scrollView.addSubview(statusLabel)

        for button in [followProfileButton, messageProfileButton] {
            button.layer.cornerRadius = 4.0
            button.clipsToBounds = true
            button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 12.0)
            scrollView.addSubview(button)
        }
        followProfileButton.accessibilityLabel = "Follow"
        followProfileButton.addTarget(self, action: #selector(profileFollowTapped),
                                      for: .touchUpInside)
        messageProfileButton.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        messageProfileButton.setTitle("Message", for: .normal)
        messageProfileButton.setTitleColor(UIColor(white: 0.25, alpha: 1.0), for: .normal)
        messageProfileButton.addTarget(self, action: #selector(profileMessageTapped),
                                       for: .touchUpInside)
        updateProfileFollowAppearance()

        photosBar.backgroundColor =
            UIColor(
                white: 0.91,
                alpha: 1.0
            )
        photosBar.layer.borderWidth = 1.0
        photosBar.layer.borderColor =
            UIColor(
                white: 0.77,
                alpha: 1.0
            ).cgColor
        scrollView.addSubview(photosBar)
        highlightTray.onOpen = { [weak self] reel in
            guard let self = self else { return }
            self.present(MagnistraStoryViewer(reel: reel, siblings: self.highlightReels),
                         animated: true, completion: nil)
        }
        highlightTray.isHidden = true
        scrollView.addSubview(highlightTray)

        photosLabel.backgroundColor = UIColor.clear
        photosLabel.textAlignment = .center

        photosLabel.text = nil
        photosIconView.image = MagnistraProfileIcons.png("PostsActive")
        photosIconView.contentMode = .scaleAspectFit
        photosIconView.isUserInteractionEnabled = false
        photosLabel.addSubview(photosIconView)
        photosLabel.isAccessibilityElement = true
        photosLabel.accessibilityLabel = "Posts"
        photosLabel.textColor = MagnistraPostCell.magnistraBlue
        photosLabel.font = UIFont.boldSystemFont(ofSize: 12.0)
        photosBar.addSubview(photosLabel)

        photosLabel.isUserInteractionEnabled = true
        photosLabel.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action: #selector(postsSectionTapped)
            )
        )

        photosIndicator.backgroundColor = MagnistraPostCell.magnistraBlue
        photosBar.addSubview(photosIndicator)

        repostsButton.backgroundColor =
            UIColor.clear

        repostsButton.setTitle(nil, for: .normal)
        repostsButton.setImage(MagnistraProfileIcons.profileRepost(false), for: .normal)
        repostsButton.imageView?.contentMode = .scaleAspectFit
        repostsButton.accessibilityLabel = "Reposts"

        repostsButton.setTitleColor(
            UIColor(
                white:
                    0.42,
                alpha:
                    1.0
            ),
            for:
                .normal
        )

        repostsButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize:
                    12.0
            )

        repostsButton.addTarget(
            self,
            action:
                #selector(
                    repostsSectionTapped
                ),
            for:
                .touchUpInside
        )

        photosBar.addSubview(
            repostsButton
        )

        loadProfile()
        loadGridPage(maxID: nil, replacing: true)
    }

    private func configureStatValue(
        _ label: UILabel
    ) {
        label.backgroundColor = UIColor.clear
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.30, alpha: 1.0)
        label.font = UIFont.boldSystemFont(ofSize: 15.0)
        scrollView.addSubview(label)
    }

    private func configureStatTitle(
        _ label: UILabel,
        text: String
    ) {
        label.backgroundColor = UIColor.clear
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.55, alpha: 1.0)
        label.font = UIFont.systemFont(ofSize: 9.5)
        label.text = text
        scrollView.addSubview(label)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)

        scrollView.frame = view.bounds

        let width =
            max(
                1.0,
                view.bounds.size.width
            )

        let side: CGFloat = 10.0
        let avatarSize: CGFloat = 72.0

        avatarView.frame =
            CGRect(
                x: side,
                y: 10.0,
                width: avatarSize,
                height: avatarSize
            )
        avatarView.layer.cornerRadius = avatarSize * 0.5

        let statsX =
            side +
            avatarSize +
            7.0

        let statsWidth =
            max(
                1.0,
                width -
                statsX -
                5.0
            )

        let columnWidth =
            statsWidth /
            3.0

        let values = [
            postsValueLabel,
            followersValueLabel,
            followingValueLabel
        ]

        let titles = [
            postsTitleLabel,
            followersTitleLabel,
            followingTitleLabel
        ]

        for i in 0..<3 {
            let x =
                statsX +
                CGFloat(i) *
                columnWidth

            values[i].frame =
                CGRect(
                    x: x,
                    y: 18.0,
                    width: columnWidth,
                    height: 22.0
                )

            titles[i].frame =
                CGRect(
                    x: x,
                    y: 40.0,
                    width: columnWidth,
                    height: 16.0
                )
        }

        fullNameLabel.frame =
            CGRect(
                x: side,
                y: 91.0,
                width:
                    width -
                    side * 2.0,
                height: 17.0
            )

        biographyLabel.text = biographyText

        let bioSize =
            biographyLabel
                .sizeThatFits(
                    CGSize(
                        width:
                            width -
                            side * 2.0,
                        height: 1000.0
                    )
                )

        let bioHeight =
            min(
                max(
                    biographyText.isEmpty
                        ? 0.0
                        : 17.0,
                    bioSize.height
                ),
                68.0
            )

        biographyLabel.frame =
            CGRect(
                x: side,
                y: 109.0,
                width:
                    width -
                    side * 2.0,
                height: bioHeight
            )

        statusLabel.text = statusText

        let statusHeight: CGFloat =
            statusText.isEmpty
                ? 0.0
                : 14.0

        statusLabel.frame =
            CGRect(
                x: side,
                y:
                    111.0 +
                    bioHeight,
                width:
                    width -
                    side * 2.0,
                height: statusHeight
            )

        let actionsY = 116.0 + bioHeight + statusHeight
        let actionsHeight: CGFloat = profileIsOwnAccount ? 0.0 : 37.0
        let actionGap: CGFloat = 8.0
        let actionWidth = max(1.0, (width - side * 2.0 - actionGap) * 0.5)
        followProfileButton.frame = CGRect(x: side, y: actionsY,
                                           width: actionWidth, height: 32.0)
        messageProfileButton.frame = CGRect(x: side + actionWidth + actionGap,
                                            y: actionsY, width: actionWidth, height: 32.0)
        let highlightHeight: CGFloat = highlightReels.isEmpty ? 0 : 92
        let photosY =
            116.0 +
            bioHeight +
            statusHeight + actionsHeight + highlightHeight
        highlightTray.frame = CGRect(x: 0, y: photosY - highlightHeight,
                                     width: width, height: highlightHeight)

        photosBar.frame =
            CGRect(
                x: 0.0,
                y: photosY,
                width: width,
                height: 34.0
            )

        photosLabel.frame =
            CGRect(
                x:
                    0.0,
                y:
                    0.0,
                width:
                    width *
                    0.5,
                height:
                    34.0
            )

        repostsButton.frame =
            CGRect(
                x:
                    width *
                    0.5,
                y:
                    0.0,
                width:
                    width *
                    0.5,
                height:
                    34.0
            )

        photosIndicator.frame =
            CGRect(
                x:
                    0.0,
                y:
                    31.0,
                width:
                    width *
                    0.5,
                height:
                    3.0
            )

        photosIndicator.frame.origin.x = gridShowingReposts ? width * 0.5 : 0.0
        photosIconView.frame = CGRect(x: (photosLabel.bounds.width - 23.0) * 0.5,
                                      y: 5.5, width: 23.0, height: 23.0)

        let gridY =
            photosY +
            35.0

        let gap: CGFloat = 1.0

        let tileWidth =
            floor(
                (
                    width -
                    gap * 2.0
                ) /
                3.0
            )

        for i in 0..<gridViews.count {
            let row =
                CGFloat(
                    i / 3
                )
            let col =
                CGFloat(
                    i % 3
                )

            gridViews[i].frame =
                CGRect(
                    x:
                        col *
                        (
                            tileWidth +
                            gap
                        ),
                    y:
                        gridY +
                        row *
                        (
                            tileWidth +
                            gap
                        ),
                    width: tileWidth,
                    height: tileWidth
                )
        }

        let rows =
            CGFloat(
                (
                    gridViews.count +
                    2
                ) /
                3
            )

        scrollView.contentSize =
            CGSize(
                width: width,
                height:
                    max(
                        gridY +
                        rows *
                        (
                            tileWidth +
                            gap
                        ) +
                        8.0,
                        view.bounds.size.height +
                        1.0
                    )
            )

        if
            let loadingLabel =
                scrollView
                    .viewWithTag(
                        magnistraProfileGridLoadingTag
                    )
        {
            let loadingY = gridY + rows * (tileWidth + gap) - gap

            loadingLabel.frame =
                CGRect(
                    x:
                        0.0,
                    y:
                        loadingY,
                    width:
                        width,
                    height:
                        38.0
                )

            scrollView.contentSize =
                CGSize(
                    width:
                        width,
                    height:
                        max(
                            loadingY +
                            38.0,
                            view.bounds
                                .size.height +
                            1.0
                        )
                )
        }

        if let loading = scrollView.viewWithTag(magnistraProfileGridLoadingTag) {
            profilePaginationDarkTail.frame = CGRect(x: 0.0,
                y: loading.frame.maxY, width: width,
                height: max(640.0, scrollView.bounds.height * 2.0))
            profilePaginationDarkTail.isHidden = false
            scrollView.sendSubviewToBack(profilePaginationDarkTail)
        } else {
            profilePaginationDarkTail.isHidden = true
        }
}

    private func loadGridPage(
        maxID: String?,
        replacing: Bool
    ) {
        if gridLoading && !replacing {
            return
        }

        gridLoading = true
        if !replacing &&
            scrollView.viewWithTag(magnistraProfileGridLoadingTag) == nil {
            let loading = UILabel(frame: CGRect(
                x: 0.0,
                y: scrollView.contentSize.height + 4.0,
                width: max(1.0, scrollView.bounds.width), height: 38.0))
            loading.tag = magnistraProfileGridLoadingTag
            loading.text = "Loading..."
            loading.font = UIFont.boldSystemFont(ofSize: 12.0)
            loading.textAlignment = .center
            loading.textColor = UIColor.white
            loading.backgroundColor = UIColor(white: 0.10, alpha: 0.88)
            scrollView.addSubview(loading)

            view.setNeedsLayout()
        }

        unifiedLoadingBand.show(!replacing, on: view, tracking: scrollView,
            inline: scrollView.viewWithTag(magnistraProfileGridLoadingTag))
        if !replacing,
           let loading = scrollView.viewWithTag(magnistraProfileGridLoadingTag) {
            profilePaginationDarkTail.frame = CGRect(x: 0.0,
                y: loading.frame.maxY, width: scrollView.bounds.width,
                height: max(640.0, scrollView.bounds.height * 2.0))
            profilePaginationDarkTail.isHidden = false
            scrollView.sendSubviewToBack(profilePaginationDarkTail)
        }

        let userID = profileUserID.isEmpty ? post.userID : profileUserID
        let username = post.username
        let showingReposts = gridShowingReposts
        let generation = gridGeneration

        gridLoadQueue.addOperation { [weak self] in
            do {
                let page: MagnistraProfileMediaPage

                if showingReposts {
                    page =
                        try MagnistraHomeService
                            .loadProfileRepostsPage(
                                userID: userID,
                                maxID: maxID
                            )
                } else {
                    page =
                        try MagnistraHomeService
                            .loadProfileMediaPage(
                                userID: userID,
                                username: username,
                                maxID: maxID
                            )
                }

                OperationQueue.main.addOperation { [weak self] in
                    guard
                        let self = self,
                        self.gridGeneration == generation,
                        self.gridShowingReposts == showingReposts
                    else {
                        return
                    }

                    self.applyGridPage(
                        page,
                        replacing: replacing
                    )

                    if replacing && maxID == nil && !showingReposts && page.posts.isEmpty {
                        self.gridPrimaryEmptyResponse = true
                    }
                    if !page.posts.isEmpty {
                        self.gridPrimaryEmptyResponse = false
                        self.gridFailureMessage = ""
                    } else if replacing && maxID == "gql:START" && !showingReposts {
                        self.gridFailureMessage = "Posts unavailable"
                    }
                    self.statusText = self.gridProfilePrivate
                        ? "Private account" : self.gridFailureMessage
                    self.view.setNeedsLayout()
                    self.view.layoutIfNeeded()
                    if self.gridPrimaryEmptyResponse && self.gridProfileLoaded &&
                       self.gridExpectedPostCount > 0 && !self.gridProfilePrivate &&
                       !self.gridFallbackRequestStarted &&
                       !(self.profileUserID.isEmpty && userID.isEmpty) {

                        self.gridFallbackRequestStarted = true
                        self.gridFallbackStarted = true
                        self.gridPrimaryEmptyResponse = false
                        self.loadGridPage(maxID: "gql:START", replacing: true)
                    }
                }
            } catch {
                MagnistraLoadFailureDiagnostic.record("visited_profile_grid", error: error)
                OperationQueue.main.addOperation { [weak self] in
                    guard
                        let self = self,
                        self.gridGeneration == generation,
                        self.gridShowingReposts == showingReposts
                    else {
                        return
                    }

                    self.gridLoading = false

                    if replacing && maxID == nil && !showingReposts &&
                       self.gridPosts.isEmpty && !self.gridFallbackRequestStarted &&
                       MagnistraLoadFailureDiagnostic.canTryAlternateProfileFeed(error) {
                        if !userID.isEmpty {
                            self.gridFallbackRequestStarted = true
                            self.gridFallbackStarted = true
                            self.loadGridPage(maxID: "gql:START", replacing: true)
                            return
                        }

                        self.gridPrimaryEmptyResponse = true
                    }

                    self.gridReachedEnd = true
                    self.gridNextMaxID = nil
                    if self.gridPosts.isEmpty && !showingReposts {
                        self.gridFailureMessage =
                            MagnistraLoadFailureDiagnostic.profileGridStatus(error)
                        self.statusText = self.gridProfilePrivate
                            ? "Private account" : self.gridFailureMessage
                    }
                    self.unifiedLoadingBand.show(false, on: self.view)
                    self.profilePaginationDarkTail.isHidden = true
                    self.scrollView.viewWithTag(
                        magnistraProfileGridLoadingTag)?.removeFromSuperview()
                    self.view.setNeedsLayout()
                    self.view.layoutIfNeeded()
                }
            }
        }
    }

    private func applyGridPage(_ page: MagnistraProfileMediaPage, replacing: Bool) {
        gridLoading = false
        unifiedLoadingBand.show(false, on: view)
        profilePaginationDarkTail.isHidden = true
        scrollView.viewWithTag(
            magnistraProfileGridLoadingTag)?.removeFromSuperview()
        if replacing {
            gridPosts.removeAll()
            gridKnownMediaIDs.removeAll()
            for tile in gridViews { tile.removeFromSuperview() }
            gridViews.removeAll()
        }

        let knownBefore =
            gridKnownMediaIDs.count

        for post in page.posts {
            if gridKnownMediaIDs.contains(post.mediaID) { continue }
            gridKnownMediaIDs.insert(post.mediaID)
            enqueueGridTile(post)
        }

        let addedCount =
            gridKnownMediaIDs.count -
            knownBefore

        if
            gridExpectedPostCount > 0 &&
            gridKnownMediaIDs.count >=
                gridExpectedPostCount
        {
            gridNextMaxID =
                nil

            gridReachedEnd =
                true
        }
        else if
            let next =
                page.nextMaxID,
            !next.isEmpty
        {
            gridNextMaxID =
                next

            gridReachedEnd =
                false

        }
        else if
            gridExpectedPostCount > 0 &&
            gridKnownMediaIDs.count <
                gridExpectedPostCount &&
            !gridFallbackStarted
        {
            gridFallbackStarted =
                true

            gridNextMaxID =
                "gql:START"

            gridReachedEnd =
                false

        }
        else {
            gridNextMaxID =
                nil

            gridReachedEnd =
                true
        }
        if !gridShowingReposts && gridPosts.isEmpty &&
           gridFallbackRequestStarted && gridReachedEnd {
            gridFailureMessage = "Posts unavailable"
            statusText = gridProfilePrivate ? "Private account" : gridFailureMessage
        }
    }

    private func showVisitedGridThumbnailFailure(
        _ reason: String?, on tile: MagnistraProfileGridTile
    ) {
        let tag = 933301
        if reason == nil {
            tile.viewWithTag(tag)?.removeFromSuperview()
            return
        }
        let failure: UILabel
        if let existing = tile.viewWithTag(tag) as? UILabel {
            failure = existing
        } else {
            failure = UILabel(frame: tile.bounds)
            failure.tag = tag
            failure.backgroundColor = UIColor(white: 0.15, alpha: 0.80)
            failure.textColor = UIColor.white
            failure.font = UIFont.systemFont(ofSize: 10.0)
            failure.textAlignment = .center
            failure.numberOfLines = 3
            failure.lineBreakMode = .byWordWrapping
            failure.isUserInteractionEnabled = false
            failure.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            tile.addSubview(failure)
        }
        failure.text = reason
    }

    private func enqueueGridTile(_ post: MagnistraRealPost) {
        let generation = gridGeneration
        let postIndex = gridPosts.count
        let localPath = post.imagePath
        let remoteURL = post.imageURL
        let stableKey = post.imageCacheKey

        let tile = MagnistraProfileGridTile(frame: CGRect.zero)
        tile.index = postIndex
        tile.backgroundColor = magnistraProfileGridPlaceholderColor(for: postIndex)
        tile.addTarget(self, action: #selector(gridTileTapped(_:)), for: .touchUpInside)
        if post.isVideo || post.videoURL != nil {
            tile.addSubview(MagnistraExploreVideoCornerMark(
                frame: CGRect(x: 6.0, y: 6.0, width: 14.0, height: 14.0)))
        } else if gridShowingReposts && post.musicAudioURL != nil {
            let note = UILabel(frame: CGRect(x: 6.0, y: 6.0, width: 22.0, height: 20.0))
            note.text = "♫"
            note.font = UIFont.boldSystemFont(ofSize: 16.0)
            note.textColor = UIColor.white
            note.textAlignment = .center
            note.backgroundColor = UIColor(white: 0.10, alpha: 0.60)
            note.layer.cornerRadius = 5.0
            note.clipsToBounds = true
            note.isUserInteractionEnabled = false
            tile.addSubview(note)
        }
        gridPosts.append(post)
        gridViews.append(tile)
        scrollView.addSubview(tile)
        view.setNeedsLayout()

        gridImageQueue.addOperation { [weak self, weak tile] in
            var image: UIImage? = nil
            var failure = "Image URL\nmissing"
            var retryable = false
            if !localPath.isEmpty {
                image = magnistraGridThumbnail(path: localPath)
                if image == nil { failure = "Cached image\ninvalid" }
            }
            if image == nil && !remoteURL.isEmpty {
                let result = MagnistraHomeService.materializeVisitedProfileGridImage(
                    url: remoteURL, stableKey: stableKey)
                if let path = result.path {
                    image = magnistraGridThumbnail(path: path)
                    failure = "Thumbnail\ndecode failed"
                } else {
                    failure = result.failure
                    retryable = result.retryable
                }
            }
            OperationQueue.main.addOperation { [weak self, weak tile] in
                guard let owner = self, let tile = tile,
                      owner.gridGeneration == generation,
                      postIndex < owner.gridViews.count,
                      owner.gridViews[postIndex] === tile,
                      postIndex < owner.gridPosts.count,
                      owner.gridPosts[postIndex].mediaID == post.mediaID
                else { return }
                if let ready = image {
                    tile.imageView.image = ready
                    owner.showVisitedGridThumbnailFailure(nil, on: tile)
                } else {
                    owner.showVisitedGridThumbnailFailure(failure, on: tile)
                    if retryable {
                        MagnistraConnectionRecovery.shared.noteFailedMedia(
                            key: "visited-profile-grid:" + post.mediaID) { [weak owner, weak tile] in
                                guard let owner = owner, let tile = tile,
                                      owner.view.window != nil,
                                      owner.gridGeneration == generation,
                                      tile.superview != nil else { return }
                                owner.retryVisitedGridThumbnail(post, on: tile,
                                    generation: generation, index: postIndex)
                            }
                    }
                }
            }
        }
    }

    private func retryVisitedGridThumbnail(
        _ post: MagnistraRealPost, on tile: MagnistraProfileGridTile,
        generation: Int, index: Int
    ) {
        guard gridGeneration == generation, tile.imageView.image == nil,
              index >= 0, index < gridPosts.count,
              index < gridViews.count, gridViews[index] === tile,
              gridPosts[index].mediaID == post.mediaID else { return }
        gridImageQueue.addOperation { [weak self, weak tile] in
            let result = MagnistraHomeService.materializeVisitedProfileGridImage(
                url: post.imageURL, stableKey: post.imageCacheKey)
            let image: UIImage? = result.path.flatMap { path in
                magnistraGridThumbnail(path: path)
            }
            OperationQueue.main.addOperation { [weak self, weak tile] in
                guard let owner = self, let tile = tile,
                      owner.gridGeneration == generation,
                      index >= 0, index < owner.gridViews.count,
                      owner.gridViews[index] === tile,
                      index < owner.gridPosts.count,
                      owner.gridPosts[index].mediaID == post.mediaID
                else { return }
                if let ready = image {
                    tile.imageView.image = ready
                    owner.showVisitedGridThumbnailFailure(nil, on: tile)
                } else {
                    owner.showVisitedGridThumbnailFailure(result.path == nil ?
                        result.failure : "Thumbnail\ndecode failed", on: tile)
                }
            }
        }
    }

    @objc private func gridTileTapped(
        _ sender:
            MagnistraProfileGridTile
    ) {
        let index =
            sender.index

        if
            index < 0 ||
            index >= gridPosts.count
        {
            return
        }

        let selectedPost = gridPosts[index]
        if gridShowingReposts && MagnistraProfileMediaOpeningGate.needsDetails(selectedPost) {
            let generation = gridGeneration
            MagnistraProfileMediaOpeningGate.open(selectedPost) { [weak self] ready in
                guard let self = self, self.gridGeneration == generation,
                      index < self.gridPosts.count,
                      self.gridPosts[index].mediaID == selectedPost.mediaID else { return }
                guard let ready = ready else {
                    MagnistraProfileMediaOpeningGate.showUnavailable()
                    return
                }
                self.gridPosts[index] = ready
                self.showSelectedVisitedGridPost(index: index)
            }
            return
        }
        showSelectedVisitedGridPost(index: index)
    }

    private func showSelectedVisitedGridPost(index: Int) {
        guard index >= 0 && index < gridPosts.count else { return }
        let selectedPost = gridPosts[index]

        for (
            previewPost,
            previewTile
        ) in zip(
            gridPosts,
            gridViews
        ) {
            if
                let preview =
                    previewTile
                        .imageView
                        .image
            {
                MagnistraDecodedImageLoader
                    .shared
                    .storeGridPreview(
                        preview,
                        stableKey:
                            previewPost
                                .imageCacheKey
                    )
            }
        }

let snapshot =
            gridPosts

        let tailStart =
            index + 1

        let controller =
            MagnistraExploreFeedViewController(
                selectedPost:
                    selectedPost,
                deferredPostsProvider: {
                    if
                        tailStart >=
                        snapshot.count
                    {
                        return []
                    }

                    return Array(
                        snapshot[
                            tailStart..<snapshot.count
                        ]
                    )
                },
                nextMaxID:
                    gridNextMaxID,
                reachedEnd:
                    gridReachedEnd
            )

        if gridShowingReposts {
            controller.magnistraUseRepostsFeed(
                userID: profileUserID.isEmpty ? post.userID : profileUserID)
        }

        controller.title =
            selectedPost.username

        navigationItem.backBarButtonItem =
            UIBarButtonItem(
                title:
                    "Back",
                style:
                    .plain,
                target:
                    nil,
                action:
                    nil
            )

        navigationController?
            .pushViewController(
                controller,
                animated: true
            )
    }

    func scrollViewWillBeginDragging(
        _ scrollView:
            UIScrollView
    ) {
        gridLoadMoreGestureConsumed =
            false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        unifiedLoadingBand.refresh()
        if
            gridPosts.isEmpty ||
            gridLoading ||
            gridReachedEnd ||
            !magnistraUserInitiatedPagination(scrollView) ||
            gridLoadMoreGestureConsumed
        {
            return
        }

        let remaining =
            scrollView.contentSize.height -
            (
                scrollView.contentOffset.y +
                scrollView.bounds.size.height
            )

        if
            remaining < 24.0,
            let cursor =
                gridNextMaxID,
            !cursor.isEmpty
        {
            gridLoadMoreGestureConsumed =
                true

            loadGridPage(
                maxID:
                    cursor,
                replacing:
                    false
            )
        }
    }

    @objc private func repostsSectionTapped() {
        selectProfileGrid(reposts: true)
    }

    @objc private func postsSectionTapped() {
        selectProfileGrid(reposts: false)
    }

    private func clearProfileGridImmediately() {
        gridLoadQueue.cancelAllOperations()
        gridImageQueue.cancelAllOperations()

        gridLoading = false
        unifiedLoadingBand.show(false, on: view)
        profilePaginationDarkTail.isHidden = true
        scrollView.viewWithTag(
            magnistraProfileGridLoadingTag)?.removeFromSuperview()
        gridNextMaxID = nil
        gridReachedEnd = false
        gridFallbackStarted = false
        gridPrimaryEmptyResponse = false
        gridFallbackRequestStarted = false
        gridFailureMessage = ""
        if gridProfileLoaded {
            statusText = gridProfilePrivate ? "Private account" : ""
        }

        gridPosts.removeAll()
        gridKnownMediaIDs.removeAll()

        for tile in gridViews {
            tile.removeFromSuperview()
        }

        gridViews.removeAll()

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func selectProfileGrid(
        reposts: Bool
    ) {
        if
            gridShowingReposts == reposts &&
            (gridLoading || !gridPosts.isEmpty)
        {
            return
        }

        gridGeneration += 1
        gridShowingReposts = reposts

        photosLabel.textColor =
            reposts
                ? UIColor(white: 0.42, alpha: 1.0)
                : MagnistraPostCell.magnistraBlue
        photosIconView.image = MagnistraProfileIcons.png(reposts ? "PostsIdle" : "PostsActive")
        repostsButton.setImage(MagnistraProfileIcons.profileRepost(reposts), for: .normal)

        repostsButton.setTitleColor(
            reposts
                ? MagnistraPostCell.magnistraBlue
                : UIColor(white: 0.42, alpha: 1.0),
            for: .normal
        )

        clearProfileGridImmediately()

        loadGridPage(
            maxID: nil,
            replacing: true
        )
    }

    private func loadProfile() {
        let userID = post.userID
        let username = post.username
        let fullName = post.fullName

        queue.addOperation {
            [weak self] in

            do {
                let profile =
                    try MagnistraHomeService
                        .loadProfile(
                            userID: userID,
                            fallbackUsername: username,
                            fallbackFullName: fullName
                        )

                OperationQueue.main.addOperation {
                    [weak self] in

                    self?.applyProfile(
                        profile
                    )
                }
            } catch {
                MagnistraLoadFailureDiagnostic.record("visited_profile", error: error)
                OperationQueue.main.addOperation {
                    [weak self] in

                    self?.statusText =
                        "Profile details unavailable"

                    self?.view.setNeedsLayout()
                }
            }
        }
    }

    private func fetchHighlights(userID: String) {
        queue.addOperation { [weak self] in
            let entries = (try? MagnistraHomeService.loadStoryHighlights(userID: userID)) ?? []
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.highlightReels = entries
                self.highlightTray.isHidden = entries.isEmpty
                self.highlightTray.show(entries)
                self.view.setNeedsLayout()
            }
        }
    }

    private func updateProfileFollowAppearance() {
        followProfileButton.setTitle(profileFollowing ? "Following" : "Follow", for: .normal)
        followProfileButton.backgroundColor = profileFollowing
            ? UIColor(red: 0.40, green: 0.70, blue: 0.30, alpha: 1.0)
            : MagnistraPostCell.magnistraBlue
        followProfileButton.setTitleColor(UIColor.white, for: .normal)
        followProfileButton.accessibilityLabel = profileFollowing ? "Following" : "Follow"
        followProfileButton.isEnabled = !profileFollowBusy
        followProfileButton.alpha = profileFollowBusy ? 0.65 : 1.0
    }

    private func showProfileActionError(_ text: String) {
        UIAlertView(title: "Magnistra", message: text, delegate: nil,
                    cancelButtonTitle: "OK").show()
    }

    @objc private func profileFollowTapped() {
        guard !profileFollowBusy, !profileIsOwnAccount, !profileUserID.isEmpty else { return }
        let targetUserID = profileUserID
        let oldValue = profileFollowing
        let newValue = !oldValue
        let attribution = gridPosts.first?.mediaID ?? post.mediaID
        profileFollowBusy = true
        profileFollowing = newValue
        updateProfileFollowAppearance()
        MagnistraHomeService.setCachedFollowingState(userID: targetUserID,
                                                       following: newValue)
        queue.addOperation { [weak self] in
            var failure: String? = nil
            do {
                try MagnistraHomeService.setFollowing(userID: targetUserID,
                                                       mediaID: attribution,
                                                       following: newValue)
            } catch {
                failure = error.localizedDescription
                MagnistraHomeService.setCachedFollowingState(userID: targetUserID,
                                                               following: oldValue)
            }
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self, self.profileUserID == targetUserID else { return }
                self.profileFollowBusy = false
                if let message = failure {
                    self.profileFollowing = oldValue
                    self.showProfileActionError(message)
                }
                self.updateProfileFollowAppearance()
            }
        }
    }

    @objc private func profileMessageTapped() {
        guard !profileMessageBusy, !profileIsOwnAccount, !profileUserID.isEmpty else { return }
        profileMessageBusy = true
        messageProfileButton.isEnabled = false
        let targetUserID = profileUserID
        let targetUsername = title ?? post.username
        queue.addOperation { [weak self] in
            var found: MagnistraDirectThreadSummary? = nil
            var errorText: String? = nil
            do {

                let inbox = try MagnistraHomeService.loadDirectInbox()
                found = inbox.threads.first {
                    !$0.isGroupConversation && $0.participantUserIDs.contains(targetUserID)
                }
                if found == nil {
                    found = try? MagnistraHomeService.resolveDirectForRecipient(userID: targetUserID)
                }
                if found == nil {
                    found = MagnistraDirectThreadSummary(
                        threadFBID: "pending:" + targetUserID,
                        minUQSeqID: 0, title: targetUsername,
                        username: targetUsername,
                        snippet: "", avatarURL: nil,
                        lastActivityMilliseconds: 0, isUnread: false,
                        participantUserIDs: [targetUserID], isGroupConversation: false)
                }
            } catch {
                errorText = error.localizedDescription
            }
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self, self.profileUserID == targetUserID else { return }
                self.profileMessageBusy = false
                self.messageProfileButton.isEnabled = true
                if let summary = found {
                    self.navigationController?.pushViewController(
                        MagnistraDirectThreadViewController(summary: summary),
                        animated: true)
                } else {
                    self.showProfileActionError(errorText ?? "Direct conversation unavailable.")
                }
            }
        }
    }

    private func applyProfile(
        _ profile:
            MagnistraProfileInfo
    ) {
        title = profile.username
        profileUserID = profile.userID
        profileIsOwnAccount = MagnistraHomeService.isCurrentAccountProfile(userID: profile.userID)
        followProfileButton.isHidden = profileIsOwnAccount
        messageProfileButton.isHidden = profileIsOwnAccount
        if let serverValue = profile.viewerFollows {
            profileFollowing = serverValue
            MagnistraHomeService.setCachedFollowingState(userID: profile.userID,
                                                           following: serverValue)
        } else if let cached = MagnistraHomeService.cachedFollowingState(userID: profile.userID) {
            profileFollowing = cached
        }
        updateProfileFollowAppearance()
        if !highlightsRequested {
            highlightsRequested = true
            fetchHighlights(userID: profile.userID)
        }

        fullNameLabel.text =
            profile.fullName.isEmpty
                ? profile.username
                : profile.fullName

        biographyText =
            profile.biography

        postsValueLabel.text =
            magnistraProfileDisplayCount(profile.mediaCount)

        gridExpectedPostCount =
            max(
                0,
                profile.mediaCount
            )
        gridProfileLoaded = true
        gridProfilePrivate = profile.isPrivate

        if
            gridReachedEnd &&
            gridExpectedPostCount > 0 &&
            gridKnownMediaIDs.count <
                gridExpectedPostCount &&
            !gridFallbackStarted
        {
            gridFallbackStarted =
                true

            gridNextMaxID =
                "gql:START"

            gridReachedEnd =
                false
        }
        followersValueLabel.text =
            magnistraProfileDisplayCount(profile.followerCount)
        followingValueLabel.text =
            magnistraProfileDisplayCount(profile.followingCount)

        if !profile.isPrivate && gridPrimaryEmptyResponse &&
           profile.mediaCount == 0 && gridPosts.isEmpty {
            gridFailureMessage = "No posts"
        }
        statusText = profile.isPrivate ? "Private account" : gridFailureMessage
        view.setNeedsLayout()

        if gridPrimaryEmptyResponse && profile.mediaCount > 0 &&
           !profile.isPrivate && !gridLoading &&
           !gridFallbackRequestStarted && !profile.userID.isEmpty {
            gridFallbackRequestStarted = true
            gridFallbackStarted = true
            gridPrimaryEmptyResponse = false
            loadGridPage(maxID: "gql:START", replacing: true)
        }
    }
}

