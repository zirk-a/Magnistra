// Overview: Tag grid screen: grid of posts for a hashtag.
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

final class MagnistraExploreTagGridViewController:
    UIViewController,
    UIScrollViewDelegate,
    UISearchBarDelegate
{
    private let pullRefreshGesture = MagnistraPullRefreshGesture()
    private let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    private let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

    private let tag:
        String

    private let tagSearchSessionID:
        String

    init(
        tag: String,
        searchSessionID: String
    ) {
        self.tag =
            tag

        self.tagSearchSessionID =
            searchSessionID

        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    private let searchBar =
        UISearchBar()

    private let searchModeButton =
        UIButton(
            type:
                .custom
        )

    private var searchModeIsTag =
        true

    private let scrollView =
        UIScrollView()

    private let statusLabel =
        UILabel()

    private let paginationLabel =
        UILabel()

    private let paginationOverscrollFill =
        UIView()

    private let loadQueue =
        OperationQueue()

    private let imageQueue =
        OperationQueue()

    private var posts:
        [MagnistraRealPost] = []

    private var tiles:
        [MagnistraExploreTile] = []

    private var placeholderViews:
        [UIView] = []

    private var seenMediaIDs =
        Set<String>()

    private var nextMaxID:
        String? =
            nil

    private var isLoadingPage =
        false

    private var reachedEnd =
        false

    private var contentGeneration =
        0

    private let placeholderTagBase =
        88000

    private var placeholderColorOrder:
        [Int] = []

    private let placeholderColors:
        [UIColor] = [
            UIColor(
                red: 0.73,
                green: 0.43,
                blue: 0.34,
                alpha: 1
            ),
            UIColor(
                red: 0.31,
                green: 0.53,
                blue: 0.62,
                alpha: 1
            ),
            UIColor(
                red: 0.62,
                green: 0.55,
                blue: 0.38,
                alpha: 1
            ),
            UIColor(
                red: 0.42,
                green: 0.60,
                blue: 0.44,
                alpha: 1
            ),
            UIColor(
                red: 0.65,
                green: 0.39,
                blue: 0.52,
                alpha: 1
            ),
            UIColor(
                red: 0.45,
                green: 0.43,
                blue: 0.64,
                alpha: 1
            ),
            UIColor(
                red: 0.72,
                green: 0.58,
                blue: 0.34,
                alpha: 1
            ),
            UIColor(
                red: 0.35,
                green: 0.58,
                blue: 0.58,
                alpha: 1
            ),
            UIColor(
                red: 0.58,
                green: 0.47,
                blue: 0.39,
                alpha: 1
            )
        ]

    override func viewDidLoad() {
        super.viewDidLoad()

        title =
            "#" +
            tag

        navigationItem.rightBarButtonItem = nil

        view.backgroundColor =
            instaLightGray()

        searchBar.placeholder =
            "Search tags"

        searchModeButton.setTitle(
            "#",
            for:
                .normal
        )

        searchModeButton.setTitleColor(
            MagnistraPostCell.magnistraBlue,
            for:
                .normal
        )

        searchModeButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize:
                    19.0
            )

        searchModeButton.backgroundColor =
            UIColor(
                white:
                    0.97,
                alpha:
                    1.0
            )

        searchModeButton.layer.cornerRadius =
            5.0

        searchModeButton.layer.borderWidth =
            1.0

        searchModeButton.layer.borderColor =
            UIColor(
                white:
                    0.78,
                alpha:
                    1.0
            ).cgColor

        searchModeButton.addTarget(
            self,
            action:
                #selector(
                    searchModeTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        view.addSubview(
            searchModeButton
        )

        searchBar.autoresizingMask = [
            .flexibleWidth
        ]

        searchBar.delegate =
            self

        searchBar.showsCancelButton =
            false

        view.addSubview(
            searchBar
        )

        searchBar.isHidden =
            true

        searchModeButton.isHidden =
            true

        scrollView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        scrollView.alwaysBounceVertical =
            true

        scrollView.delegate =
            self

        view.addSubview(
            scrollView
        )
        pullRefreshGesture.install(on: scrollView) { [weak self] in
            self?.refreshTapped()
        }

        statusLabel.backgroundColor =
            UIColor.clear

        statusLabel.textAlignment =
            .center

        statusLabel.textColor =
            UIColor(
                white: 0.48,
                alpha: 1.0
            )

        statusLabel.font =
            UIFont.systemFont(
                ofSize: 13.0
            )

        statusLabel.numberOfLines =
            2

        view.addSubview(
            statusLabel
        )

        paginationLabel.backgroundColor =
            UIColor(white: 0.10, alpha: 0.88)

        paginationLabel.textAlignment =
            .center

        paginationLabel.textColor =
            UIColor.white

        paginationLabel.font =
            UIFont.boldSystemFont(
                ofSize: 12.0
            )

        paginationLabel.text = "Loading..."

        paginationLabel.isHidden =
            true

        scrollView.addSubview(
            paginationLabel
        )

        paginationOverscrollFill.backgroundColor =
            UIColor(white: 0.10, alpha: 0.88)

        paginationOverscrollFill.isUserInteractionEnabled =
            false

        paginationOverscrollFill.isHidden =
            true

        scrollView.insertSubview(
            paginationOverscrollFill,
            belowSubview: paginationLabel
        )

        loadQueue.maxConcurrentOperationCount =
            1

        imageQueue.maxConcurrentOperationCount =
            2

        installInitialPlaceholders()

        requestPage(
            maxID: nil,
            replacing: true
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)

        let width =
            view.bounds.size.width

        searchBar.frame =
            CGRect(
                x: 0.0,
                y: 0.0,
                width: width,
                height: 44.0
            )

        let contentY:
            CGFloat = 44.0

        scrollView.frame =
            CGRect(
                x: 0.0,
                y: contentY,
                width: width,
                height: max(
                    1.0,
                    view.bounds.size.height -
                    contentY
                )
            )

        statusLabel.frame =
            CGRect(
                x: 20.0,
                y: contentY + 35.0,
                width: max(
                    1.0,
                    width - 40.0
                ),
                height: 50.0
            )

        layoutGrid()
            let searchModeWidth:
            CGFloat =
                42.0

        searchModeButton.frame =
            CGRect(
                x:
                    5.0,
                y:
                    5.0,
                width:
                    34.0,
                height:
                    34.0
            )

        searchBar.frame =
            CGRect(
                x:
                    searchModeWidth,
                y:
                    0.0,
                width:
                    max(
                        1.0,
                        view.bounds.size.width -
                        searchModeWidth
                    ),
                height:
                    44.0
            )

        scrollView.frame =
            view.bounds

        statusLabel.frame =
            CGRect(
                x:
                    20.0,
                y:
                    35.0,
                width:
                    max(
                        1.0,
                        view.bounds.size.width -
                        40.0
                    ),
                height:
                    50.0
            )

        layoutGrid()
}

    private func placeholderColor(
        for index: Int
    ) -> UIColor {
        guard
            !placeholderColors.isEmpty
        else {
            return UIColor.lightGray
        }

        if
            placeholderColorOrder.count ==
                placeholderColors.count
        {
            let slot =
                index %
                placeholderColorOrder.count

            return placeholderColors[
                placeholderColorOrder[
                    slot
                ]
            ]
        }

        return placeholderColors[
            index %
            placeholderColors.count
        ]
    }

    private func installInitialPlaceholders() {
        removeAllPlaceholders()

        placeholderColorOrder =
            Array(
                0..<placeholderColors.count
            )

        if placeholderColorOrder.count > 1 {
            var position =
                placeholderColorOrder.count -
                1

            while position > 0 {
                let swapIndex =
                    Int(
                        arc4random_uniform(
                            UInt32(
                                position +
                                1
                            )
                        )
                    )

                if swapIndex != position {
                    let temporary =
                        placeholderColorOrder[
                            position
                        ]

                    placeholderColorOrder[
                        position
                    ] =
                        placeholderColorOrder[
                            swapIndex
                        ]

                    placeholderColorOrder[
                        swapIndex
                    ] =
                        temporary
                }

                position -= 1
            }
        }

        for index in 0..<15 {
            addPlaceholder(
                for: index
            )
        }

        layoutGrid()
    }

    private func addPlaceholder(
        for index: Int
    ) {
        let tag =
            placeholderTagBase +
            index

        if
            scrollView.viewWithTag(
                tag
            ) != nil
        {
            return
        }

        let placeholder =
            UIView(
                frame: CGRect.zero
            )

        placeholder.tag =
            tag

        placeholder.backgroundColor =
            placeholderColor(
                for: index
            )

        placeholder.isUserInteractionEnabled =
            false

        placeholderViews.append(
            placeholder
        )

        scrollView.addSubview(
            placeholder
        )
    }

    private func removePlaceholder(
        for index: Int
    ) {
        let tag =
            placeholderTagBase +
            index

        if let view =
            scrollView.viewWithTag(
                tag
            )
        {
            view.removeFromSuperview()
        }

        placeholderViews =
            placeholderViews.filter {
                $0.tag != tag
            }
    }

    private func removeAllPlaceholders() {
        for view in placeholderViews {
            view.removeFromSuperview()
        }

        placeholderViews.removeAll(
            keepingCapacity: true
        )
    }

    private func requestPage(
        maxID: String?,
        replacing: Bool
    ) {
        if
            isLoadingPage ||
            (
                !replacing &&
                reachedEnd
            )
        {
            return
        }

        isLoadingPage =
            true
        unifiedLoadingBand.show(!replacing && !posts.isEmpty, on: view, tracking: scrollView, inline: paginationLabel)

        if replacing {
            statusLabel.text =
                nil
        } else {
            paginationLabel.isHidden =
                false

            layoutGrid()
        }

        loadQueue.addOperation {
            [weak self] in

            guard
                let self =
                    self
            else {
                return
            }

            do {
                let page =
                    try MagnistraHomeService
                        .loadExploreTagExplorePage(
                            tag:
                                self.tag,
                            searchSessionID:
                                self.tagSearchSessionID,
                            maxID:
                                maxID
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?
                            .applyPage(
                                page,
                                requestedMaxID:
                                    maxID,
                                replacing:
                                    replacing
                            )
                    }
            } catch {
                let message =
                    (
                        error as NSError
                    )
                        .localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.isLoadingPage =
                            false
                        self.unifiedLoadingBand.show(false, on: self.view)

                        self.reachedEnd = true
                        self.nextMaxID = nil

                        self.paginationLabel
                            .isHidden =
                                true

                        if replacing {
                            self.pullRefreshIndicator.end(on: self.navigationItem)
                            self.navigationItem
                                .rightBarButtonItem?
                                .isEnabled =
                                    true

                            self.removeAllPlaceholders()

                            self.statusLabel.text =
                                message
                        }

                        self.layoutGrid()
                    }
            }
        }
    }

    private func applyPage(
        _ page:
            MagnistraExplorePage,
        requestedMaxID:
            String?,
        replacing:
            Bool
    ) {
        isLoadingPage =
            false
        unifiedLoadingBand.show(false, on: view)

        paginationLabel.isHidden =
            true

        if replacing {
            pullRefreshIndicator.end(on: navigationItem)
            navigationItem
                .rightBarButtonItem?
                .isEnabled =
                    true

            posts.removeAll(
                keepingCapacity: true
            )

            seenMediaIDs.removeAll(
                keepingCapacity: true
            )

            for tile in tiles {
                tile.removeFromSuperview()
            }

            tiles.removeAll(
                keepingCapacity: true
            )

            removeAllPlaceholders()
        }

        var newIndexes:
            [Int] = []

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

            posts.append(
                post
            )

            let index =
                posts.count - 1

            newIndexes.append(
                index
            )

            addPlaceholder(
                for: index
            )
        }

        nextMaxID =
            page.nextMaxID

        reachedEnd =
            page.nextMaxID == nil ||
            page.nextMaxID ==
                requestedMaxID

        if posts.isEmpty {
            removeAllPlaceholders()

            statusLabel.text =
                "No Explore posts available."

            scrollView.contentSize =
                scrollView.bounds.size

            return
        }

        statusLabel.text =
            nil

        for index in newIndexes {
            enqueueImage(
                for: index
            )
        }

        layoutGrid()
    }

    private func enqueueImage(
        for index: Int
    ) {
        if
            index < 0 ||
            index >= posts.count
        {
            return
        }

        let post =
            posts[index]

        let expectedGeneration =
            contentGeneration

        let localPath =
            post.imagePath

        let remoteURL =
            post.imageURL

        let stableKey =
            post.imageCacheKey

        imageQueue.addOperation {
            [weak self] in

            var image:
                UIImage? = nil

            if !localPath.isEmpty {
                image =
                    UIImage(
                        contentsOfFile:
                            localPath
                    )
            }

            if
                image == nil,
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
                    UIImage(
                        contentsOfFile:
                            materialized
                    )
            }

            guard
                let ready =
                    image
            else {
                return
            }

            OperationQueue.main
                .addOperation {
                    [weak self] in

                    guard
                        let self =
                            self,
                        expectedGeneration ==
                            self.contentGeneration,
                        index <
                            self.posts.count
                    else {
                        return
                    }

                    self.removePlaceholder(
                        for: index
                    )

                    let tile =
                        MagnistraExploreTile(
                            frame: CGRect.zero
                        )

                    tile.postIndex =
                        index

                    tile.setImage(
                        ready,
                        for: .normal
                    )

                    let current =
                        self.posts[index]

                    MagnistraDecodedImageLoader
                        .shared
                        .storeGridPreview(
                            ready,
                            stableKey:
                                current.imageCacheKey
                        )

if current.videoURL != nil {
                        let overlay =
                            MagnistraExploreVideoCornerMark(
                                frame:
                                    CGRect(
                                        x: 6.0,
                                        y: 6.0,
                                        width: 14.0,
                                        height: 14.0
                                    )
                            )

                        tile.addSubview(
                            overlay
                        )
                    }

                    tile.addTarget(
                        self,
                        action:
                            #selector(
                                self.exploreTileTapped(
                                    _:
                                )
                            ),
                        for: .touchUpInside
                    )

                    self.tiles.append(
                        tile
                    )

                    self.scrollView.addSubview(
                        tile
                    )

                    self.layoutGrid()
                }
        }
    }

    private func gridMetrics()
        -> (
            width: CGFloat,
            spacing: CGFloat,
            tileWidth: CGFloat
        )
    {
        let width =
            max(
                1.0,
                scrollView.bounds.size.width
            )

        let spacing:
            CGFloat = 2.0

        let tileWidth =
            floor(
                (
                    width -
                    spacing * 4.0
                ) /
                3.0
            )

        return (
            width,
            spacing,
            tileWidth
        )
    }

    private func frameForGridIndex(
        _ index: Int
    ) -> CGRect {
        let metrics =
            gridMetrics()

        let row =
            index / 3

        let column =
            index % 3

        return CGRect(
            x:
                metrics.spacing +
                CGFloat(column) *
                (
                    metrics.tileWidth +
                    metrics.spacing
                ),
            y:
                metrics.spacing +
                CGFloat(row) *
                (
                    metrics.tileWidth +
                    metrics.spacing
                ),
            width:
                metrics.tileWidth,
            height:
                metrics.tileWidth
        )
    }

    private func layoutGrid() {
        let metrics =
            gridMetrics()

        for placeholder in
            placeholderViews
        {
            let index =
                placeholder.tag -
                placeholderTagBase

            placeholder.frame =
                frameForGridIndex(
                    index
                )
        }

        for tile in tiles {
            tile.frame =
                frameForGridIndex(
                    tile.postIndex
                )
        }

        let visibleCount =
            max(
                posts.count,
                placeholderViews
                    .map {
                        $0.tag -
                        placeholderTagBase +
                        1
                    }
                    .max() ?? 0
            )

        let rows =
            (
                visibleCount +
                2
            ) /
            3

        let gridHeight =
            metrics.spacing +
            CGFloat(rows) *
            (
                metrics.tileWidth +
                metrics.spacing
            )

        let footerHeight:
            CGFloat =
                paginationLabel.isHidden
                    ? 0.0
                    : 38.0

        paginationLabel.frame =
            CGRect(
                x: 0.0,
                y: gridHeight,
                width: metrics.width,
                height: footerHeight
            )

        paginationOverscrollFill.isHidden =
            paginationLabel.isHidden

        paginationOverscrollFill.frame =
            CGRect(
                x: 0.0,
                y: gridHeight + footerHeight,
                width: metrics.width,
                height: max(
                    640.0,
                    scrollView.bounds.size.height * 2.0
                )
            )

        scrollView.contentSize =
            CGSize(
                width: metrics.width,
                height:
                    max(
                        gridHeight +
                        footerHeight,
                        scrollView.bounds
                            .size.height +
                        1.0
                    )
            )
    }

    func scrollViewDidScroll(
        _ scrollView:
            UIScrollView
    ) {
        unifiedLoadingBand.refresh()
        if
            posts.isEmpty ||
            isLoadingPage ||
            reachedEnd
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
            remaining < 420.0,
            magnistraUserInitiatedPagination(scrollView),
            let cursor =
                nextMaxID,
            !cursor.isEmpty
        {
            requestPage(
                maxID: cursor,
                replacing: false
            )
        }
    }

    @objc private func reelsTapped() {
        MagnistraInlineVideoPlayer
            .shared
            .stop()

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        let controller =
            MagnistraReelsViewController()

        controller.hidesBottomBarWhenPushed =
            true

        navigationController?
            .pushViewController(
                controller,
                animated:
                    true
            )
    }

    @objc private func refreshTapped() {
        MagnistraPostCell.resetTransientFollowConfirmation()
        guard
            !isLoadingPage
        else {
            return
        }

        navigationItem
            .rightBarButtonItem?
            .isEnabled =
                false

        pullRefreshIndicator.begin(on: navigationItem, label: "Updating tag posts")

        MagnistraInlineVideoPlayer
            .shared
            .stop()

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        imageQueue
            .cancelAllOperations()

        contentGeneration +=
            1

        nextMaxID =
            nil

        reachedEnd =
            false

        seenMediaIDs.removeAll(
            keepingCapacity:
                true
        )

        posts.removeAll(
            keepingCapacity:
                true
        )

        for tile in tiles {
            tile.removeFromSuperview()
        }

        tiles.removeAll(
            keepingCapacity:
                true
        )

        scrollView.setContentOffset(
            CGPoint.zero,
            animated:
                false
        )

        statusLabel.text =
            nil

        installInitialPlaceholders()

        requestPage(
            maxID:
                nil,
            replacing:
                true
        )
    }

    @objc private func exploreTileTapped(
        _ sender:
            MagnistraExploreTile
    ) {
        let index =
            sender.postIndex

        if
            index < 0 ||
            index >= posts.count
        {
            return
        }

        let selectedPost =
            posts[index]

        if
            let preview =
                sender.image(
                    for:
                        .normal
                )
        {
            MagnistraDecodedImageLoader
                .shared
                .storeGridPreview(
                    preview,
                    stableKey:
                        selectedPost.imageCacheKey
                )
        }

let snapshot =
            posts

        let tailStart =
            index + 1

        let controller =
            MagnistraExploreTagFeedViewController(
                tag:
                    tag,
                searchSessionID:
                    tagSearchSessionID,
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
                    nextMaxID,
                reachedEnd:
                    reachedEnd
            )

        navigationController?
            .pushViewController(
                controller,
                animated: true
            )
    }

    func searchBarTextDidBeginEditing(
        _ searchBar: UISearchBar
    ) {
        searchBar.showsCancelButton =
            true
    }

    func searchBarCancelButtonClicked(
        _ searchBar: UISearchBar
    ) {
        searchBar.text = ""
        searchBar.showsCancelButton =
            false
        searchBar.resignFirstResponder()
    }

    func searchBarSearchButtonClicked(
        _ searchBar: UISearchBar
    ) {
        let raw =
            (
                searchBar.text ??
                ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard
            !raw.isEmpty
        else {
            return
        }

        let routedQuery:
            String

        if
            raw.hasPrefix(
                "#"
            ) ||
            raw.hasPrefix(
                "@"
            )
        {
            routedQuery =
                raw
        } else if
            searchModeIsTag
        {
            routedQuery =
                "#" +
                raw
        } else {
            routedQuery =
                "@" +
                raw
        }

        searchBar.resignFirstResponder()
        searchBar.showsCancelButton =
            false

        navigationController?
            .pushViewController(
                MagnistraExploreSearchResultsViewController(
                    query:
                        routedQuery
                ),
                animated:
                    true
            )
    }

    @objc private func searchModeTapped(
        _ sender: UIButton
    ) {
        searchModeIsTag.toggle()

        sender.setTitle(
            searchModeIsTag
                ? "#"
                : "@",
            for:
                .normal
        )

        searchBar.placeholder =
            searchModeIsTag
                ? "Search tags"
                : "Search users"

        if !searchBar.isFirstResponder {
            searchBar.becomeFirstResponder()
        }
    }
}

