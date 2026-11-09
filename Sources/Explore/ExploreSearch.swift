// Overview: Explore: search results screen (users and tags).
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

final class MagnistraExploreSearchResultsViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    UIScrollViewDelegate
{
    private let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

    private enum Mode {
        case users(String)
        case tag(String)
    }

    private let mode:
        Mode

    private let tableView =
        UITableView(
            frame:
                CGRect.zero,
            style:
                .plain
        )

    private let tagScroll =
        UIScrollView()

    private let statusLabel =
        UILabel()

    private let loadQueue =
        OperationQueue()

    private let imageQueue =
        OperationQueue()

    private var users:
        [MagnistraExploreSearchUser] =
            []

    private var tagItems:
        [MagnistraExploreTagSearchItem] =
            []

    private var tagTiles:
        [MagnistraExploreSearchTagTile] =
            []

    private var searchSessionID =
        MagnistraHomeService
            .makeExploreSearchSessionID()

    private var rankToken =
        ""

    private var nextTagCursor:
        String? =
            nil

    private var tagHasNext =
        false

    private var tagLoading =
        false

    private var seenTagIDs =
        Set<String>()

    init(
        query: String
    ) {
        var normalized =
            query.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        if normalized.hasPrefix("#") {
            normalized.removeFirst()

            while normalized.hasPrefix("#") {
                normalized.removeFirst()
            }

            mode =
                .tag(
                    normalized
                )
        } else {
            while normalized.hasPrefix("@") {
                normalized.removeFirst()
            }

            mode =
                .users(
                    normalized
                )
        }

        super.init(
            nibName:
                nil,
            bundle:
                nil
        )
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor =
            instaLightGray()

        loadQueue.maxConcurrentOperationCount =
            1
        imageQueue.maxConcurrentOperationCount =
            2

        statusLabel.backgroundColor =
            UIColor.clear
        statusLabel.textAlignment =
            .center
        statusLabel.textColor =
            UIColor(
                white:
                    0.45,
                alpha:
                    1.0
            )
        statusLabel.font =
            UIFont.systemFont(
                ofSize:
                    13.0
            )
        statusLabel.numberOfLines =
            2
        view.addSubview(
            statusLabel
        )

        switch mode {
        case .users(let query):
            title = "Users"

            tableView.dataSource =
                self
            tableView.delegate =
                self
            tableView.rowHeight =
                58.0
            tableView.autoresizingMask = [
                .flexibleWidth,
                .flexibleHeight
            ]
            view.addSubview(
                tableView
            )

            loadUsers(
                query:
                    query
            )

        case .tag(let tag):
            title =
                "#" +
                tag

            tagScroll.alwaysBounceVertical =
                true
            tagScroll.delegate =
                self
            tagScroll.backgroundColor = instaLightGray()
            tagScroll.autoresizingMask = [
                .flexibleWidth,
                .flexibleHeight
            ]
            view.addSubview(
                tagScroll
            )

            loadTagPage(
                tag:
                    tag,
                after:
                    nil
            )
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)

        tableView.frame =
            view.bounds

        tagScroll.frame =
            view.bounds

        statusLabel.frame =
            CGRect(
                x:
                    18.0,
                y:
                    38.0,
                width:
                    max(
                        1.0,
                        view.bounds.size.width -
                        36.0
                    ),
                height:
                    54.0
            )

        layoutTagTiles()
    }

    private func magnistraPresentSearchStatus(_ text: String) {
        if NoConnectionBanner.showIfHTTPZero(text, on: view) {
            statusLabel.text = nil
        } else {
            NoConnectionBanner.hide(on: view)
            statusLabel.text = text
        }
    }

    private func loadUsers(
        query: String
    ) {
        guard
            !query.isEmpty
        else {
            statusLabel.text =
                "Enter a username."
            return
        }

        statusLabel.text =
            "Searching..."

        let sessionID =
            searchSessionID

        let currentRank =
            rankToken

        loadQueue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraHomeService
                        .loadExploreUserSearch(
                            query:
                                query,
                            searchSessionID:
                                sessionID,
                            rankToken:
                                currentRank
                        )

                OperationQueue.main
                    .addOperation {
                        guard
                            let strongSelf =
                                self
                        else {
                            return
                        }

                        NoConnectionBanner.hide(on: strongSelf.view)
                        strongSelf.users =
                            page.users
                        strongSelf.rankToken =
                            page.rankToken
                        strongSelf.statusLabel.text =
                            page.users.isEmpty
                                ? "No users found."
                                : ""
                        strongSelf.tableView
                            .reloadData()
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in
                        self?.magnistraPresentSearchStatus(message)
                    }
            }
        }
    }

    private func loadTagPage(
        tag: String,
        after: String?
    ) {
        guard
            !tag.isEmpty,
            !tagLoading
        else {
            return
        }

        tagLoading =
            true
        unifiedLoadingBand.show(after != nil && !tagItems.isEmpty, on: view, tracking: tagScroll)

        if after == nil {
            statusLabel.text =
                "Loading #\(tag)..."
        }

        let sessionID =
            searchSessionID

        loadQueue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraHomeService
                        .loadExploreTagSearchPage(
                            tag:
                                tag,
                            searchSessionID:
                                sessionID,
                            after:
                                after
                        )

                OperationQueue.main
                    .addOperation {
                        guard
                            let strongSelf =
                                self
                        else {
                            return
                        }

                        NoConnectionBanner.hide(on: strongSelf.view)
                        var appended =
                            0

                        for item in page.items {
                            if
                                strongSelf
                                    .seenTagIDs
                                    .contains(
                                        item.mediaID
                                    )
                            {
                                continue
                            }

                            strongSelf
                                .seenTagIDs
                                .insert(
                                    item.mediaID
                                )

                            strongSelf
                                .tagItems
                                .append(
                                    item
                                )

                            strongSelf
                                .addTagTile(
                                    item:
                                        item,
                                    index:
                                        strongSelf
                                            .tagItems
                                            .count -
                                        1
                                )

                            appended +=
                                1
                        }

                        strongSelf.nextTagCursor =
                            page.endCursor
                        strongSelf.tagHasNext =
                            page.hasNextPage
                        strongSelf.tagLoading =
                            false
                        strongSelf.unifiedLoadingBand.show(false, on: strongSelf.view)

                        if
                            strongSelf
                                .tagItems
                                .isEmpty
                        {
                            strongSelf.statusLabel.text =
                                "No posts found for #\(tag)."
                        } else {
                            strongSelf.statusLabel.text =
                                ""
                        }

                        if appended > 0 {
                            strongSelf
                                .layoutTagTiles()
                        }
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?.tagLoading =
                            false
                        if let owner = self { owner.unifiedLoadingBand.show(false, on: owner.view) }

                        self?.tagHasNext = false
                        self?.nextTagCursor = nil
                        self?.magnistraPresentSearchStatus(message)
                    }
            }
        }
    }

    private func addTagTile(
        item: MagnistraExploreTagSearchItem,
        index: Int
    ) {
        let tile =
            MagnistraExploreSearchTagTile(
                frame:
                    CGRect.zero
            )

        tile.index =
            index

        tile.addTarget(
            self,
            action:
                #selector(
                    tagTileTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        if item.isVideo {
            let mark =
                MagnistraExploreVideoCornerMark(
                    frame:
                        CGRect(
                            x:
                                5.0,
                            y:
                                5.0,
                            width:
                                19.0,
                            height:
                                19.0
                        )
                )

            mark.autoresizingMask = [
                .flexibleRightMargin,
                .flexibleBottomMargin
            ]

            tile.addSubview(
                mark
            )
        }

        tagScroll.addSubview(
            tile
        )

        tagTiles.append(
            tile
        )

        guard
            !item.thumbnailURL.isEmpty
        else {
            return
        }

        let mediaID =
            item.mediaID
        let remoteURL =
            item.thumbnailURL

        imageQueue.addOperation {
            [weak tile] in

            guard
                let path =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                remoteURL,
                            stableKey:
                                "explore-tag-search:" +
                                mediaID,
                            isAvatar:
                                false
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
                    [weak tile] in
                    tile?
                        .imageView
                        .image =
                            image
                }
        }
    }

    private func layoutTagTiles() {
        guard
            !tagTiles.isEmpty
        else {
            tagScroll.contentSize =
                CGSize(
                    width:
                        tagScroll.bounds.size.width,
                    height:
                        max(
                            tagScroll.bounds.size.height +
                            1.0,
                            1.0
                        )
                )
            return
        }

        let width =
            tagScroll.bounds.size.width

        if width <= 0.0 {
            return
        }

        let spacing:
            CGFloat =
                2.0

        let itemWidth =
            max(
                1.0,
                (
                    width -
                    spacing * 4.0
                ) /
                3.0
            )

        for (
            index,
            tile
        ) in tagTiles.enumerated() {
            let row =
                index / 3
            let column =
                index % 3

            tile.frame =
                CGRect(
                    x:
                        spacing +
                        CGFloat(
                            column
                        ) *
                        (
                            itemWidth +
                            spacing
                        ),
                    y:
                        spacing +
                        CGFloat(
                            row
                        ) *
                        (
                            itemWidth +
                            spacing
                        ),
                    width:
                        itemWidth,
                    height:
                        itemWidth
                )
        }

        let rows =
            (
                tagTiles.count +
                2
            ) /
            3

        let contentHeight =
            spacing +
            CGFloat(
                rows
            ) *
            (
                itemWidth +
                spacing
            ) +
            42.0

        tagScroll.contentSize =
            CGSize(
                width:
                    width,
                height:
                    max(
                        tagScroll.bounds.size.height +
                        1.0,
                        contentHeight
                    )
            )
    }

    @objc private func tagTileTapped(
        _ sender:
            MagnistraExploreSearchTagTile
    ) {
        let index =
            sender.index

        guard
            index >= 0,
            index < tagItems.count
        else {
            return
        }

        let item =
            tagItems[index]

        statusLabel.text =
            "Opening post..."

        loadQueue.addOperation {
            [weak self] in

            do {
                let post =
                    try MagnistraHomeService
                        .loadActivityReferencedPost(
                            shortcode:
                                item.shortcode
                        )

                OperationQueue.main
                    .addOperation {
                        guard
                            let strongSelf =
                                self
                        else {
                            return
                        }

                        strongSelf
                            .statusLabel
                            .text =
                                ""

                        strongSelf
                            .navigationController?
                            .pushViewController(
                                MagnistraProfilePostViewController(
                                    post:
                                        post
                                ),
                                animated:
                                    true
                            )
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in
                        self?.magnistraPresentSearchStatus(message)
                    }
            }
        }
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        unifiedLoadingBand.refresh()
        guard
            scrollView === tagScroll,
            tagHasNext,
            !tagLoading,
            let cursor =
                nextTagCursor,
            !cursor.isEmpty
        else {
            return
        }

        let remaining =
            scrollView.contentSize.height -
            (
                scrollView.contentOffset.y +
                scrollView.bounds.size.height
            )

        if remaining < 320.0 &&
            magnistraUserInitiatedPagination(scrollView) {
            if
                case .tag(
                    let tag
                ) =
                    mode
            {
                loadTagPage(
                    tag:
                        tag,
                    after:
                        cursor
                )
            }
        }
    }

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection
            section: Int
    ) -> Int {
        return users.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt
            indexPath: IndexPath
    ) -> UITableViewCell {
        let reuse =
            "MagnistraExploreSearchUserCell"

        let cell =
            (
                tableView
                    .dequeueReusableCell(
                        withIdentifier:
                            reuse
                    ) as?
                    MagnistraExploreSearchUserCell
            ) ??
            MagnistraExploreSearchUserCell(
                style:
                    .default,
                reuseIdentifier:
                    reuse
            )

        let user =
            users[
                indexPath.row
            ]

        cell.representedID =
            user.userID

        cell.usernameLabel.text =
            user.username

        cell.fullNameLabel.text =
            user.fullName

        cell.avatarView.image =
            nil

        guard
            let remoteURL =
                user.avatarURL,
            !remoteURL.isEmpty
        else {
            return cell
        }

        let representedID =
            user.userID

        imageQueue.addOperation {
            [weak cell] in

            guard
                let path =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                remoteURL,
                            stableKey:
                                "explore-user-search-avatar:" +
                                representedID,
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
                    [weak cell] in

                    guard
                        let cell =
                            cell,
                        cell.representedID ==
                            representedID
                    else {
                        return
                    }

                    cell.avatarView.image =
                        image
                }
        }

        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt
            indexPath: IndexPath
    ) {
        tableView.deselectRow(
            at:
                indexPath,
            animated:
                true
        )

        guard
            indexPath.row <
                users.count
        else {
            return
        }

        let user =
            users[
                indexPath.row
            ]

        let synthetic =
            MagnistraRealPost(
                mediaID:
                    "",
                userID:
                    user.userID,
                username:
                    user.username,
                fullName:
                    user.fullName,
                caption:
                    "",
                commentCount:
                    0,
                previewComments:
                    [],
                likes:
                    0,
                location:
                    "",
                takenAt:
                    0.0,
                imagePath:
                    "",
                imageURL:
                    "",
                imageCacheKey:
                    "explore-search-profile:" +
                    user.userID,
                avatarPath:
                    nil,
                avatarURL:
                    user.avatarURL,
                avatarCacheKey:
                    "explore-search-avatar:" +
                    user.userID,
                musicTitle:
                    nil,
                musicArtist:
                    nil,
                musicAudioURL:
                    nil,
                musicStartTimeMs:
                    0,
                photoMusicImageURLFallback:
                    nil,
                videoURL:
                    nil,
                videoWidth:
                    0,
                videoHeight:
                    0
            )

        navigationController?
            .pushViewController(
                MagnistraProfileViewController(
                    post:
                        synthetic
                ),
                animated:
                    true
            )
    }
}

