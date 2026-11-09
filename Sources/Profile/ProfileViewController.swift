// Overview: Profile screen (ProfileViewController): header stats and media grid.
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

final class ProfileViewController:
    UIViewController,
    UIScrollViewDelegate
{
    func magnistraReturnToTop() {
        rootTabHeaderScroll.revealForTabReturn()
        let y = -scrollView.contentInset.top
        scrollView.setContentOffset(CGPoint(x: 0.0, y: y), animated: true)
    }
    private let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)
    private let profilePaginationDarkTail = UIView()

    private let rootTabHeaderScroll = MagnistraRootTabHeaderScrollBehavior()
    private let queue = OperationQueue()
    private let scrollView = UIScrollView()
    private let avatarView = UIImageView()
    private let highlightTray = MagnistraStoryTrayView(frame: .zero)
    private var highlightReels: [MagnistraStoryReel] = []
    private var lastHighlightUserID = ""

    private let postsValueLabel = UILabel()
    private let followersValueLabel = UILabel()
    private let followingValueLabel = UILabel()
    private let postsTitleLabel = UILabel()
    private let followersTitleLabel = UILabel()
    private let followingTitleLabel = UILabel()
    private let fullNameLabel = UILabel()
    private let biographyLabel = UILabel()
    private let statusLabel = UILabel()
    private let savedActionButton = UIButton(type: .custom)
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

    private var gridSection = 0

    private var gridExpectedPostCount = 0
    private var gridFallbackStarted = false
    private var gridFallbackRequestStarted = false
    private var gridFailureMessage = ""
    private var gridLoadMoreGestureConsumed = false
    private var gridUserID = ""
    private var gridUsername = ""
    private let gridImageQueue = OperationQueue()
    private var biographyText = ""
    private var statusText = "Loading profile…"

    override func viewDidLoad() {
        super.viewDidLoad()
        queue.maxConcurrentOperationCount = 1
        title = "Profile"
        view.backgroundColor = UIColor(white: 0.96, alpha: 1.0)

        let settingsGear = UIButton(type: .custom)
        settingsGear.frame = CGRect(x: 0.0, y: 0.0,
                                    width: 32.0, height: 32.0)
        settingsGear.backgroundColor = UIColor.clear
        settingsGear.setImage(magnistraProfileSettingsGear(), for: .normal)
        settingsGear.accessibilityLabel = "Settings"
        settingsGear.addTarget(self, action: #selector(settingsTapped),
                               for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: settingsGear)

        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
        avatarView.layer.borderColor = UIColor(white: 0.72, alpha: 1.0).cgColor
        scrollView.addSubview(avatarView)

        configureStatValue(postsValueLabel)
        configureStatValue(followersValueLabel)
        configureStatValue(followingValueLabel)
        configureStatTitle(postsTitleLabel, text: "posts")
        configureStatTitle(followersTitleLabel, text: "followers")
        configureStatTitle(followingTitleLabel, text: "following")
        postsValueLabel.text = "—"
        followersValueLabel.text = "—"
        followingValueLabel.text = "—"

        fullNameLabel.backgroundColor = UIColor.clear
        fullNameLabel.textColor = UIColor(white: 0.28, alpha: 1.0)
        fullNameLabel.font = UIFont.boldSystemFont(ofSize: 12.5)
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

        savedActionButton.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        savedActionButton.layer.cornerRadius = 4.0
        savedActionButton.clipsToBounds = true
        savedActionButton.setTitle("View Saved", for: .normal)
        savedActionButton.setTitleColor(UIColor(white: 0.25, alpha: 1.0), for: .normal)
        savedActionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 12.0)
        savedActionButton.addTarget(self, action: #selector(viewSavedTapped),
                                      for: .touchUpInside)
        scrollView.addSubview(savedActionButton)

        photosBar.backgroundColor = UIColor(white: 0.91, alpha: 1.0)
        photosBar.layer.borderWidth = 1.0
        photosBar.layer.borderColor = UIColor(white: 0.77, alpha: 1.0).cgColor
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

        loadCurrentProfile()
    }

    private func configureStatValue(_ label: UILabel) {
        label.backgroundColor = UIColor.clear
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.30, alpha: 1.0)
        label.font = UIFont.boldSystemFont(ofSize: 15.0)
        scrollView.addSubview(label)
    }

    private func configureStatTitle(_ label: UILabel, text: String) {
        label.backgroundColor = UIColor.clear
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.55, alpha: 1.0)
        label.font = UIFont.systemFont(ofSize: 9.5)
        label.text = text
        scrollView.addSubview(label)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootTabHeaderScroll.activate(scrollView, navigationController: navigationController)

    }

    override func viewWillDisappear(_ animated: Bool) {
        rootTabHeaderScroll.deactivate()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)
        if !rootTabHeaderScroll.managesViewport {
            scrollView.frame = view.bounds
        }
        let width = max(1.0, view.bounds.size.width)
        let side: CGFloat = 10.0
        let avatarSize: CGFloat = 72.0

        avatarView.frame = CGRect(x: side, y: 10.0, width: avatarSize, height: avatarSize)
        avatarView.layer.cornerRadius = avatarSize * 0.5

        let statsX = side + avatarSize + 7.0
        let statsWidth = max(1.0, width - statsX - 5.0)
        let columnWidth = statsWidth / 3.0
        let values = [postsValueLabel, followersValueLabel, followingValueLabel]
        let titles = [postsTitleLabel, followersTitleLabel, followingTitleLabel]

        for i in 0..<3 {
            let x = statsX + CGFloat(i) * columnWidth
            values[i].frame = CGRect(x: x, y: 18.0, width: columnWidth, height: 22.0)
            titles[i].frame = CGRect(x: x, y: 40.0, width: columnWidth, height: 16.0)
        }

        fullNameLabel.frame = CGRect(x: side, y: 91.0, width: width - side * 2.0, height: 17.0)
        biographyLabel.text = biographyText
        let bioSize = biographyLabel.sizeThatFits(
            CGSize(width: width - side * 2.0, height: 1000.0)
        )
        let bioHeight = min(
            max(biographyText.isEmpty ? 0.0 : 17.0, bioSize.height),
            68.0
        )
        biographyLabel.frame = CGRect(
            x: side,
            y: 109.0,
            width: width - side * 2.0,
            height: bioHeight
        )

        statusLabel.text = statusText
        let statusHeight: CGFloat = statusText.isEmpty ? 0.0 : 14.0
        statusLabel.frame = CGRect(
            x: side,
            y: 113.0 + bioHeight,
            width: width - side * 2.0,
            height: statusHeight
        )

        let actionsY = 116.0 + bioHeight + statusHeight
        savedActionButton.frame = CGRect(x: side, y: actionsY,
                                          width: max(1.0, width - side * 2.0), height: 32.0)
        let actionsHeight: CGFloat = 37.0
        let highlightHeight: CGFloat = highlightReels.isEmpty ? 0 : 92
        let photosY = actionsY + actionsHeight + highlightHeight
        highlightTray.frame = CGRect(x: 0, y: photosY - highlightHeight,
                                     width: width, height: highlightHeight)
        photosBar.frame = CGRect(x: 0.0, y: photosY, width: width, height: 34.0)
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

        let gridY = photosY + 35.0
        let gap: CGFloat = 1.0
        let tileWidth = floor((width - gap * 2.0) / 3.0)

        for i in 0..<gridViews.count {
            let row = CGFloat(i / 3)
            let col = CGFloat(i % 3)

            gridViews[i].index = i < gridPosts.count ? i : -1
            gridViews[i].frame = CGRect(
                x: col * (tileWidth + gap),
                y: gridY + row * (tileWidth + gap),
                width: tileWidth,
                height: tileWidth
            )
        }

        let rows = CGFloat((gridViews.count + 2) / 3)
        scrollView.contentSize = CGSize(
            width: width,
            height: max(
                gridY + rows * (tileWidth + gap) + 8.0,
                view.bounds.size.height + 1.0
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
    rootTabHeaderScroll.restoreViewportAfterOwnerLayout()
    }

    @objc private func repostsSectionTapped() {
        selectProfileGrid(section: 1)
    }

    @objc private func postsSectionTapped() {
        selectProfileGrid(section: 0)
    }

    private func clearProfileGridImmediately() {
        gridLoadQueue.cancelAllOperations()
        gridImageQueue.cancelAllOperations()

        gridLoading = false
        unifiedLoadingBand.show(false, on: view)
        gridNextMaxID = nil
        gridReachedEnd = false
        gridFallbackStarted = false
        gridFallbackRequestStarted = false
        gridFailureMessage = ""
        if statusText != "Loading profile…" && statusText != "Private account" {
            statusText = ""
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
        section: Int
    ) {
        guard
            section >= 0,
            section <= 1
        else {
            return
        }

        if
            gridSection == section &&
            (gridLoading || !gridPosts.isEmpty)
        {
            return
        }

        gridGeneration += 1
        gridSection = section
        gridShowingReposts = section == 1

        let inactive = UIColor(white: 0.42, alpha: 1.0)

        photosLabel.textColor = section == 0 ? MagnistraPostCell.magnistraBlue : inactive
        photosIconView.image = MagnistraProfileIcons.png(section == 0 ? "PostsActive" : "PostsIdle")
        repostsButton.setImage(MagnistraProfileIcons.profileRepost(section == 1), for: .normal)
        repostsButton.setTitleColor(section == 1 ? MagnistraPostCell.magnistraBlue : inactive, for: .normal)

        clearProfileGridImmediately()
        loadGridPage(maxID: nil, replacing: true)
    }

    private func loadCurrentProfile() {
        statusText =
            "Loading profile…"

        view.setNeedsLayout()

        queue.addOperation {
            [weak self] in

            var loadedProfile:
                MagnistraProfileInfo? =
                    nil

            do {
                loadedProfile = try MagnistraHomeService.loadCurrentProfile()
            } catch {
                MagnistraLoadFailureDiagnostic.record("own_profile", error: error)

            }

            OperationQueue.main
                .addOperation {
                    [weak self] in

                    guard
                        let profile =
                            loadedProfile
                    else {
                        self?
                            .statusText =
                            "Profile details unavailable"

                        self?
                            .view
                            .setNeedsLayout()

                        return
                    }

                    self?
                        .applyProfile(
                            profile
                        )
                }
        }
    }

    private func fetchHighlights(userID: String) {
        queue.addOperation { [weak self] in
            let entries = (try? MagnistraHomeService.loadStoryHighlights(userID: userID)) ?? []
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self, self.lastHighlightUserID == userID else { return }
                self.highlightReels = entries
                self.highlightTray.isHidden = entries.isEmpty
                self.highlightTray.show(entries)
                self.view.setNeedsLayout()
            }
        }
    }

    private func applyProfile(_ profile: MagnistraProfileInfo) {
        title = profile.username
        if lastHighlightUserID != profile.userID {
            lastHighlightUserID = profile.userID
            fetchHighlights(userID: profile.userID)
        }
        fullNameLabel.text = profile.fullName.isEmpty ? profile.username : profile.fullName
        biographyText = profile.biography
        postsValueLabel.text = magnistraProfileDisplayCount(profile.mediaCount)

        gridExpectedPostCount =
            max(
                0,
                profile.mediaCount
            )

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
        followersValueLabel.text = magnistraProfileDisplayCount(profile.followerCount)
        followingValueLabel.text = magnistraProfileDisplayCount(profile.followingCount)
        statusText = profile.isPrivate ? "Private account" : gridFailureMessage

        if gridUserID != profile.userID {
            gridUserID = profile.userID
            gridUsername = profile.username
            loadGridPage(maxID: nil, replacing: true)
        }

        if
            profile.profilePicURL != nil ||
            profile.profilePicURLFallback != nil
        {
            let primaryURL =
                profile.profilePicURL

            let fallbackURL =
                profile.profilePicURLFallback

            queue.addOperation {
                [weak self] in

                guard
                    let image =
                        MagnistraHomeService
                            .loadProfileAvatar(
                                primaryURL:
                                    primaryURL,
                                fallbackURL:
                                    fallbackURL
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

        view.setNeedsLayout()
    }

    private func loadGridPage(
        maxID: String?,
        replacing: Bool
    ) {
        if gridLoading && !replacing {
            return
        }

        gridLoading =
            true

        if
            replacing &&
            gridPosts.isEmpty &&
            gridViews.isEmpty
        {
            for placeholderIndex in 0..<(gridSection == 2 ? 15 : 9) {
                let placeholder =
                    MagnistraProfileGridTile(
                        frame:
                            CGRect.zero
                    )

                placeholder.index =
                    -1

                placeholder.backgroundColor =
                    magnistraProfileGridPlaceholderColor(
                        for:
                            placeholderIndex
                    )

                gridViews.append(
                    placeholder
                )

                scrollView.addSubview(
                    placeholder
                )
            }

            view.setNeedsLayout()
            view.layoutIfNeeded()
        }

        if !replacing {
            if
                scrollView.viewWithTag(
                    magnistraProfileGridLoadingTag
                ) == nil
            {
                let loadingLabel =
                    UILabel(
                        frame:
                            CGRect.zero
                    )

                loadingLabel.tag =
                    magnistraProfileGridLoadingTag

                loadingLabel.backgroundColor =
                    UIColor(white: 0.10, alpha: 0.88)

                loadingLabel.textAlignment =
                    .center

                loadingLabel.textColor =
                    UIColor.white

                loadingLabel.font =
                    UIFont.boldSystemFont(
                        ofSize:
                            12.0
                    )

                loadingLabel.text =
                    "Loading..."

                loadingLabel.isUserInteractionEnabled =
                    false

                let loadingY = scrollView.contentSize.height + 4.0

                loadingLabel.frame =
                    CGRect(
                        x:
                            0.0,
                        y:
                            loadingY,
                        width:
                            max(
                                1.0,
                                scrollView.bounds.size.width
                            ),
                        height:
                            38.0
                    )

                scrollView.addSubview(
                    loadingLabel
                )

                view.setNeedsLayout()
            }
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

        let userID =
            gridUserID

        let username =
            gridUsername

        let section =
            gridSection

        let generation =
            gridGeneration

        gridLoadQueue.addOperation {
            [weak self] in

            do {
                let page:
                    MagnistraProfileMediaPage

                switch section {
                case 1:
                    page =
                        try MagnistraHomeService
                            .loadProfileRepostsPage(
                                userID:
                                    userID,
                                maxID:
                                    maxID
                            )

                default:
                    page =
                        try MagnistraHomeService
                            .loadProfileMediaPage(
                                userID:
                                    userID,
                                username:
                                    username,
                                maxID:
                                    maxID
                            )
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self,
                            self.gridGeneration ==
                                generation,
                            self.gridSection ==
                                section
                        else {
                            return
                        }

                        if replacing && section != 2 {
                            for placeholder in self.gridViews {
                                if placeholder.index < 0 {
                                    placeholder.removeFromSuperview()
                                }
                            }
                            self.gridViews = self.gridViews.filter { $0.index >= 0 }
                        }

                        if
                            let loadingLabel =
                                self.scrollView
                                    .viewWithTag(
                                        magnistraProfileGridLoadingTag
                                    )
                        {
                            loadingLabel.removeFromSuperview()
                        }

                        self.applyGridPage(
                            page,
                            replacing:
                                replacing
                        )

                        if section == 0 {
                            if !page.posts.isEmpty {
                                self.gridFailureMessage = ""
                            } else if replacing && maxID == "gql:START" {
                                self.gridFailureMessage = "Posts unavailable"
                            } else if replacing && maxID == nil &&
                                      self.gridExpectedPostCount == 0 {
                                self.gridFailureMessage = "No posts"
                            }
                            if self.statusText != "Private account" &&
                               self.statusText != "Loading profile…" {
                                self.statusText = self.gridFailureMessage
                            }
                        }
                        self.view.setNeedsLayout()
                        self.view.layoutIfNeeded()
                        if replacing && section == 0 && maxID == nil &&
                           page.posts.isEmpty && self.gridExpectedPostCount > 0 &&
                           !self.gridFallbackRequestStarted && !userID.isEmpty {
                            self.gridFallbackRequestStarted = true
                            self.gridFallbackStarted = true
                            self.loadGridPage(maxID: "gql:START", replacing: true)
                        }

                    }
            } catch {
                MagnistraLoadFailureDiagnostic.record("own_profile_grid", error: error)
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self,
                            self.gridGeneration ==
                                generation,
                            self.gridSection ==
                                section
                        else {
                            return
                        }

                        self.gridLoading =
                            false

                        if section == 0 && replacing && maxID == nil &&
                           self.gridPosts.isEmpty && !self.gridFallbackRequestStarted &&
                           !userID.isEmpty &&
                           MagnistraLoadFailureDiagnostic.canTryAlternateProfileFeed(error) {
                            self.gridFallbackRequestStarted = true
                            self.gridFallbackStarted = true
                            self.loadGridPage(maxID: "gql:START", replacing: true)
                            return
                        }
                        self.gridReachedEnd = true
                        self.gridNextMaxID = nil
                        if self.gridPosts.isEmpty && section == 0 {
                            self.gridFailureMessage =
                                MagnistraLoadFailureDiagnostic.profileGridStatus(error)
                            if self.statusText != "Private account" &&
                               self.statusText != "Loading profile…" {
                                self.statusText = self.gridFailureMessage
                            }
                        }
                        self.unifiedLoadingBand.show(false, on: self.view)
                        self.profilePaginationDarkTail.isHidden = true

                        if replacing && section != 2 {
                            for placeholder in self.gridViews {
                                if placeholder.index < 0 {
                                    placeholder.removeFromSuperview()
                                }
                            }
                            self.gridViews = self.gridViews.filter { $0.index >= 0 }
                        }

                        if
                            let loadingLabel =
                                self.scrollView
                                    .viewWithTag(
                                        magnistraProfileGridLoadingTag
                                    )
                        {
                            loadingLabel.removeFromSuperview()
                        }

                        self.view.setNeedsLayout()
                        self.view.layoutIfNeeded()
                    }
            }
        }
    }

    private func applyGridPage(_ page: MagnistraProfileMediaPage, replacing: Bool) {
        gridLoading = false
        unifiedLoadingBand.show(false, on: view)
        if replacing {
            gridPosts.removeAll()
            gridKnownMediaIDs.removeAll()
            for tile in gridViews { tile.removeFromSuperview() }
            gridViews.removeAll()
        } else if gridSection == 2 {

            for tile in gridViews where tile.index < 0 {
                tile.removeFromSuperview()
            }
            gridViews = gridViews.filter { $0.index >= 0 }
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

        if gridSection == 2 {
            maintainSavedGridSlots()

            if !replacing && addedCount == 0 {
                removeUnusedSavedGridSlotsAfterScroll()
            }
        }

        if
            gridSection == 0 && gridExpectedPostCount > 0 &&
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
            gridSection == 0 && gridExpectedPostCount > 0 &&
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
        if gridSection == 0 && gridPosts.isEmpty &&
           gridFallbackRequestStarted && gridReachedEnd {
            gridFailureMessage = "Posts unavailable"
            if statusText != "Private account" && statusText != "Loading profile…" {
                statusText = gridFailureMessage
            }
        }

}

    private func maintainSavedGridSlots() {
        guard gridSection == 2 else { return }

        let targetCount = max(15, gridPosts.count)
        if gridViews.count < targetCount {
            for slot in gridViews.count..<targetCount {
                let tile = MagnistraProfileGridTile(frame: CGRect.zero)
                tile.index = -1
                tile.isUserInteractionEnabled = false
                tile.backgroundColor = magnistraProfileGridPlaceholderColor(for: slot)
                gridViews.append(tile)
                scrollView.addSubview(tile)
            }
        }
        view.setNeedsLayout()
    }

    private func removeUnusedSavedGridSlotsAfterScroll() {
        guard gridSection == 2 else { return }
        for tile in gridViews where tile.index < 0 {
            tile.removeFromSuperview()
        }
        gridViews = gridViews.filter { $0.index >= 0 }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func enqueueGridTile(
        _ post: MagnistraRealPost
    ) {
        let generation =
            gridGeneration

        let index =
            gridPosts.count

        let tile =
            MagnistraProfileGridTile(
                frame:
                    CGRect.zero
            )

        tile.index =
            index

        if gridSection != 0 && (post.isVideo || post.videoURL != nil) {
            tile.addSubview(
                MagnistraExploreVideoCornerMark(
                    frame: CGRect(x: 6.0, y: 6.0, width: 14.0, height: 14.0)
                )
            )
        }

        tile.backgroundColor = gridSection == 2
            ? magnistraProfileGridPlaceholderColor(for: index)
            : UIColor(white: 0.92, alpha: 1.0)

        tile.addTarget(
            self,
            action:
                #selector(
                    gridTileTapped(_:)
                ),
            for:
                .touchUpInside
        )

        if gridSection == 1 && post.videoURL == nil &&
           post.musicAudioURL != nil {
            let music = UILabel(frame: CGRect(x: 6.0, y: 6.0,
                                              width: 22.0, height: 20.0))
            music.text = "♫"
            music.font = UIFont.boldSystemFont(ofSize: 16.0)
            music.textAlignment = .center
            music.textColor = UIColor.white
            music.backgroundColor = UIColor(white: 0.10, alpha: 0.60)
            music.layer.cornerRadius = 5.0
            music.clipsToBounds = true
            music.isUserInteractionEnabled = false
            tile.addSubview(music)
        }

        gridPosts.append(
            post
        )

        gridViews.append(
            tile
        )

        scrollView.addSubview(
            tile
        )

        view.setNeedsLayout()

        let localPath =
            post.imagePath

        let remoteURL =
            post.imageURL

        let stableKey =
            post.imageCacheKey

        gridImageQueue.addOperation {
            [weak self, weak tile] in

            var image:
                UIImage? =
                    nil

            if
                !localPath.isEmpty
            {
                image =
                    magnistraGridThumbnail(
                        path:
                            localPath
                    )
            }

            if
                image == nil,
                !remoteURL.isEmpty,
                let materialized =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                remoteURL,
                            stableKey:
                                stableKey,
                            isAvatar:
                                false
                        )
            {
                image =
                    magnistraGridThumbnail(
                        path:
                            materialized
                    )
            }

            guard
                let ready =
                    image
            else {
                if !remoteURL.isEmpty {
                    MagnistraConnectionRecovery.shared.noteFailedMedia(
                        key: "profile-grid:" + post.mediaID) { [weak self, weak tile] in
                        guard let owner = self, let tile = tile,
                              owner.view.window != nil,
                              owner.gridGeneration == generation,
                              tile.superview != nil else { return }
                        owner.retryGridThumbnail(post, tile: tile,
                            generation: generation)
                    }
                }
                return
            }

            OperationQueue.main
                .addOperation {
                    [weak self, weak tile] in

                    guard
                        let self =
                            self,
                        let tile =
                            tile,
                        self.gridGeneration ==
                            generation,
                        tile.index >= 0,
                        tile.index <
                            self.gridPosts.count,
                        self.gridPosts[
                            tile.index
                        ].mediaID ==
                            post.mediaID
                    else {
                        return
                    }

                    tile.imageView.image =
                        ready
                }
        }
    }

    private func retryGridThumbnail(_ post: MagnistraRealPost,
                                    tile: MagnistraProfileGridTile,
                                    generation: Int) {
        guard gridGeneration == generation, tile.imageView.image == nil,
              tile.index >= 0, tile.index < gridPosts.count,
              gridPosts[tile.index].mediaID == post.mediaID else { return }
        gridImageQueue.addOperation { [weak self, weak tile] in
            guard let path = MagnistraHomeService.materializeFeedImage(
                url: post.imageURL, stableKey: post.imageCacheKey,
                isAvatar: false),
                let image = magnistraGridThumbnail(path: path)
            else { return }
            OperationQueue.main.addOperation { [weak self, weak tile] in
                guard let owner = self, let tile = tile,
                      owner.gridGeneration == generation,
                      tile.index >= 0, tile.index < owner.gridPosts.count,
                      owner.gridPosts[tile.index].mediaID == post.mediaID
                else { return }
                tile.imageView.image = image
            }
        }
    }

    private let savedVideoResolveQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var savedVideoResolvingIDs = Set<String>()

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

        let selectedPost =
            gridPosts[index]

        if gridSection != 0 && MagnistraProfileMediaOpeningGate.needsDetails(selectedPost) {
            if savedVideoResolvingIDs.contains(selectedPost.mediaID) { return }
            savedVideoResolvingIDs.insert(selectedPost.mediaID)
            let generation = gridGeneration
            let section = gridSection
            MagnistraProfileMediaOpeningGate.open(selectedPost) { [weak self] ready in
                guard let self = self else { return }
                self.savedVideoResolvingIDs.remove(selectedPost.mediaID)
                guard self.gridSection == section, self.gridGeneration == generation,
                      index < self.gridPosts.count,
                      self.gridPosts[index].mediaID == selectedPost.mediaID else { return }
                guard let ready = ready else {
                    MagnistraProfileMediaOpeningGate.showUnavailable()
                    return
                }
                self.gridPosts[index] = ready
                self.showSelectedGridPost(index: index, selectedPost: ready)
            }
            return
        }
        showSelectedGridPost(index: index, selectedPost: selectedPost)
    }

    private func showSelectedGridPost(
        index: Int,
        selectedPost: MagnistraRealPost
    ) {

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

        if gridSection == 1 {
            controller.magnistraUseRepostsFeed(userID: gridUserID)
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
        rootTabHeaderScroll.observe(scrollView, initialContentReady: !gridPosts.isEmpty)

        if gridSection == 2 && !gridLoading && gridReachedEnd &&
           !gridLoadMoreGestureConsumed &&
           magnistraUserInitiatedPagination(scrollView) {
            let remaining = scrollView.contentSize.height -
                (scrollView.contentOffset.y + scrollView.bounds.size.height)
            if remaining < 24.0 && gridViews.contains(where: { $0.index < 0 }) {
                gridLoadMoreGestureConsumed = true
                removeUnusedSavedGridSlotsAfterScroll()
                return
            }
        }
        if
            (gridPosts.isEmpty && gridSection != 2) ||
            gridLoading ||
            gridReachedEnd ||
            gridImageQueue.operationCount > 0 ||
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

    @objc private func viewSavedTapped() {
        let saved = ExploreViewController()
        saved.magnistraPrepareSavedGrid()
        saved.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(saved, animated: true)
    }

    @objc private func settingsTapped() {
        let settings = SettingsViewController()
        navigationController?.pushViewController(settings, animated: true)
    }
}

