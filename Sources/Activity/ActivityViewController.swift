// Overview: Activity (notifications) screen and its cell.
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

final class MagnistraActivityCell:
    UITableViewCell
{
    static let reuseID =
        "MagnistraActivityCell"

    let avatarView =
        UIImageView()

    let usernameButton =
        UIButton(
            type:
                .custom
        )

    let bodyLabel =
        UILabel()

    var onUsernameTap:
        (() -> Void)?

    let timeLabel =
        UILabel()

    let mediaView =
        UIImageView()

    var representedActivityID =
        ""

    override init(
        style:
            UITableViewCell.CellStyle,
        reuseIdentifier:
            String?
    ) {
        super.init(
            style:
                style,
            reuseIdentifier:
                reuseIdentifier
        )

        selectionStyle =
            .gray

        avatarView.contentMode =
            .scaleAspectFill

        avatarView.clipsToBounds =
            true

        avatarView.layer.cornerRadius =
            20.0

        avatarView.backgroundColor =
            MagnistraPostCell
                .magnistraBlue

        contentView.addSubview(
            avatarView
        )

        usernameButton.backgroundColor =
            UIColor.clear

        usernameButton.setTitleColor(
            MagnistraPostCell
                .magnistraBlue,
            for:
                .normal
        )

        usernameButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize:
                    13.0
            )

        usernameButton.contentHorizontalAlignment =
            .left

        usernameButton.addTarget(
            self,
            action:
                #selector(
                    usernameTapped
                ),
            for:
                .touchUpInside
        )

        contentView.addSubview(
            usernameButton
        )

        bodyLabel.backgroundColor =
            UIColor.clear

        bodyLabel.textColor =
            UIColor(
                white:
                    0.16,
                alpha:
                    1.0
            )

        bodyLabel.font =
            UIFont.systemFont(
                ofSize:
                    13.0
            )

        bodyLabel.numberOfLines =
            3

        contentView.addSubview(
            bodyLabel
        )

        timeLabel.backgroundColor =
            UIColor.clear

        timeLabel.textColor =
            UIColor(
                white:
                    0.58,
                alpha:
                    1.0
            )

        timeLabel.font =
            UIFont.systemFont(
                ofSize:
                    10.0
            )

        contentView.addSubview(
            timeLabel
        )

        mediaView.contentMode =
            .scaleAspectFill

        mediaView.clipsToBounds =
            true

        mediaView.backgroundColor =
            UIColor(
                white:
                    0.90,
                alpha:
                    1.0
            )

        contentView.addSubview(
            mediaView
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        representedActivityID =
            ""

        avatarView.image =
            nil

        mediaView.image =
            nil

        usernameButton.setTitle(
            nil,
            for:
                .normal
        )

        onUsernameTap =
            nil

        bodyLabel.text =
            nil

        timeLabel.text =
            nil
    }

    @objc private func usernameTapped() {
        onUsernameTap?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let side:
            CGFloat = 10.0

        avatarView.frame =
            CGRect(
                x:
                    side,
                y:
                    12.0,
                width:
                    40.0,
                height:
                    40.0
            )

        let hasMedia =
            !mediaView.isHidden

        let right:
            CGFloat =
                hasMedia
                    ? 62.0
                    : 10.0

        let textWidth =
            max(
                1.0,
                bounds.size.width -
                60.0 -
                right
            )

        let nicknameSize =
            usernameButton.titleLabel?
                .sizeThatFits(
                    CGSize(
                        width:
                            textWidth,
                        height:
                            18.0
                    )
                ) ??
            CGSize.zero

        usernameButton.frame =
            CGRect(
                x:
                    60.0,
                y:
                    7.0,
                width:
                    min(
                        textWidth,
                        max(
                            1.0,
                            nicknameSize.width +
                                4.0
                        )
                    ),
                height:
                    18.0
            )

        bodyLabel.frame =
            CGRect(
                x:
                    60.0,
                y:
                    24.0,
                width:
                    textWidth,
                height:
                    21.0
            )

        timeLabel.frame =
            CGRect(
                x:
                    60.0,
                y:
                    44.0,
                width:
                    max(
                        1.0,
                        bounds.size.width -
                        60.0 -
                        right
                    ),
                height:
                    14.0
            )

        mediaView.frame =
            CGRect(
                x:
                    bounds.size.width -
                    54.0,
                y:
                    8.0,
                width:
                    46.0,
                height:
                    46.0
            )
    }
}

final class ActivityViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate
{
    private let pullRefreshGesture = MagnistraPullRefreshGesture()
    private let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    private let rootTabHeaderScroll = MagnistraRootTabHeaderScrollBehavior()
    private let tableView =
        UITableView(
            frame:
                CGRect.zero,
            style:
                .plain
        )

    private let queue =
        OperationQueue()

    private let imageQueue =
        OperationQueue()

    private var items:
        [MagnistraActivityItem] = []

    private var isLoading =
        false

    private var openingActivityShortcode:
        String? =
            nil

    override func viewDidLoad() {
        super.viewDidLoad()

        title =
            "Activity"

        view.backgroundColor =
            instaLightGray()

        queue.maxConcurrentOperationCount =
            1

        imageQueue.maxConcurrentOperationCount =
            2

        tableView.dataSource =
            self

        tableView.delegate =
            self

        tableView.rowHeight =
            64.0

        tableView.separatorStyle =
            .singleLine

        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(
            tableView
        )
        pullRefreshGesture.install(on: tableView) { [weak self] in
            self?.refreshTapped()
        }

        navigationItem.rightBarButtonItem = nil

        showStatus(
            "Loading..."
        )

        loadActivity()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootTabHeaderScroll.activate(tableView, navigationController: navigationController)

    }

    override func viewWillDisappear(_ animated: Bool) {
        rootTabHeaderScroll.deactivate()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !rootTabHeaderScroll.managesViewport {
            tableView.frame = view.bounds
        }
        rootTabHeaderScroll.restoreViewportAfterOwnerLayout()
    }

    @objc private func refreshTapped() {
        if isLoading {
            return
        }

        pullRefreshIndicator.begin(on: navigationItem, label: "Updating Activity")
        loadActivity()
    }

    private func loadActivity() {
        if isLoading {
            return
        }

        isLoading =
            true

        navigationItem
            .rightBarButtonItem?
            .isEnabled =
                false

        queue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraHomeService
                        .loadActivity()

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.isLoading =
                            false
                        self.pullRefreshIndicator.end(on: self.navigationItem)

                        self.navigationItem
                            .rightBarButtonItem?
                            .isEnabled =
                                true

                        MagnistraBottomLoading.hide(on: self.view)
                        NoConnectionBanner.hide(on: self.view)
                        self.items =
                            page.items

                        self.tableView
                            .reloadData()

                        if self.items.isEmpty {
                            self.showStatus(
                                "No recent activity."
                            )
                        } else {
                            self.tableView
                                .backgroundView =
                                    nil
                        }
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.isLoading =
                            false
                        self.pullRefreshIndicator.end(on: self.navigationItem)

                        self.navigationItem
                            .rightBarButtonItem?
                            .isEnabled =
                                true

                        self.showStatus(
                            error.localizedDescription
                        )
                    }
            }
        }
    }

    func tableView(
        _ tableView:
            UITableView,
        numberOfRowsInSection section:
            Int
    ) -> Int {
        return items.count
    }

    func tableView(
        _ tableView:
            UITableView,
        cellForRowAt indexPath:
            IndexPath
    ) -> UITableViewCell {
        let cell =
            (
                tableView.dequeueReusableCell(
                    withIdentifier:
                        MagnistraActivityCell
                            .reuseID
                ) as?
                    MagnistraActivityCell
            ) ??
            MagnistraActivityCell(
                style:
                    .default,
                reuseIdentifier:
                    MagnistraActivityCell
                        .reuseID
            )

        let item =
            items[
                indexPath.row
            ]

        cell.representedActivityID =
            item.activityID

        cell.usernameButton.setTitle(
            item.username,
            for:
                .normal
        )

        cell.usernameButton.isHidden =
            item.username.isEmpty

        cell.bodyLabel.text =
            activityActionText(
                item.text,
                username:
                    item.username
            )

        cell.onUsernameTap = {
            [weak self] in

            self?.openProfile(
                for:
                    item
            )
        }

        cell.timeLabel.text =
            relativeTime(
                item.createdAt
            )

        cell.mediaView.isHidden =
            item.mediaImageURL == nil

        cell.avatarView.image =
            nil

        cell.mediaView.image =
            nil

        if
            let avatar =
                item.avatarURL,
            !avatar.isEmpty
        {
            requestImage(
                url:
                    avatar,
                activityID:
                    item.activityID,
                media:
                    false
            )
        }

        if
            let media =
                item.mediaImageURL,
            !media.isEmpty
        {
            requestImage(
                url:
                    media,
                activityID:
                    item.activityID,
                media:
                    true
            )
        }

        return cell
    }

    func tableView(
        _ tableView:
            UITableView,
        didSelectRowAt indexPath:
            IndexPath
    ) {
        tableView.deselectRow(
            at:
                indexPath,
            animated:
                true
        )

        let item =
            items[
                indexPath.row
            ]

        openReferencedMedia(
            for:
                item
        )
    }

    private func activityActionText(
        _ text:
            String,
        username:
            String
    ) -> String {
        guard
            !username.isEmpty,
            text.hasPrefix(
                username
            )
        else {
            return text
        }

        var action =
            String(
                text.dropFirst(
                    username.count
                )
            )

        while action.hasPrefix(" ") {
            action.removeFirst()
        }

        return action
    }

    private func openProfile(
        for item:
            MagnistraActivityItem
    ) {
        guard
            !item.userID.isEmpty ||
            !item.username.isEmpty
        else {
            return
        }

        let synthetic =
            MagnistraRealPost(
                mediaID:
                    "",
                userID:
                    item.userID,
                username:
                    item.username,
                fullName:
                    item.fullName,
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
                    "activity-profile:" +
                    item.userID,
                avatarPath:
                    nil,
                avatarURL:
                    item.avatarURL,
                avatarCacheKey:
                    "activity-avatar:" +
                    item.userID,
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

    private func openReferencedMedia(
        for item:
            MagnistraActivityItem
    ) {
        if let post = item.referencePost {
            navigationController?
                .pushViewController(
                    MagnistraProfilePostViewController(
                        post:
                            post
                    ),
                    animated:
                        true
                )
            return
        }

        guard
            let shortcode =
                item.referencedShortcode,
            !shortcode.isEmpty
        else {

            openProfile(
                for:
                    item
            )
            return
        }

        if
            openingActivityShortcode ==
                shortcode
        {
            return
        }

        openingActivityShortcode =
            shortcode

        queue.addOperation {
            [weak self] in

            do {
                let post =
                    try MagnistraHomeService
                        .loadActivityReferencedPost(
                            shortcode:
                                shortcode
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.openingActivityShortcode =
                            nil

                        self.navigationController?
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

                        self?.openingActivityShortcode =
                            nil

                        let alert =
                            UIAlertView(
                                title:
                                    "Activity",
                                message:
                                    message,
                                delegate:
                                    nil,
                                cancelButtonTitle:
                                    "OK"
                            )

                        alert.show()
                    }
            }
        }
    }

    private func requestImage(
        url: String,
        activityID: String,
        media: Bool
    ) {
        imageQueue.addOperation {
            [weak self] in

            guard
                let self =
                    self,
                let data =
                    MagnistraHomeService
                        .activityImageData(
                            url:
                                url
                        ),
                let image =
                    UIImage(
                        data:
                            data
                    )
            else {
                return
            }

            OperationQueue.main
                .addOperation {
                    [weak self] in

                    guard
                        let self =
                            self
                    else {
                        return
                    }

                    for visible in
                        self.tableView
                            .visibleCells
                    {
                        guard
                            let cell =
                                visible as?
                                    MagnistraActivityCell,
                            cell.representedActivityID ==
                                activityID
                        else {
                            continue
                        }

                        if media {
                            cell.mediaView.image =
                                image
                        } else {
                            cell.avatarView.image =
                                image
                        }
                    }
                }
        }
    }

    private func relativeTime(
        _ timestamp:
            Double
    ) -> String {
        if timestamp <= 0.0 {
            return ""
        }

        let delta =
            max(
                0.0,
                Date().timeIntervalSince1970 -
                    timestamp
            )

        if delta < 60.0 {
            return "now"
        }

        if delta < 3600.0 {
            return
                String(
                    Int(
                        delta /
                        60.0
                    )
                ) + "m"
        }

        if delta < 86400.0 {
            return
                String(
                    Int(
                        delta /
                        3600.0
                    )
                ) + "h"
        }

        return
            String(
                Int(
                    delta /
                    86400.0
                )
            ) + "d"
    }

    private func showStatus(
        _ text:
            String
    ) {
        if NoConnectionBanner.showIfHTTPZero(text, on: view) {
            MagnistraBottomLoading.hide(on: view)
            tableView.backgroundView = nil
            return
        }
        NoConnectionBanner.hide(on: view)
        if text.hasPrefix("Loading") {
            tableView.backgroundView = nil
            MagnistraBottomLoading.show(on: view)
            return
        }
        MagnistraBottomLoading.hide(on: view)

        let label =
            UILabel(
                frame:
                    tableView.bounds
            )

        label.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        label.textAlignment =
            .center

        label.textColor =
            UIColor(
                white:
                    0.55,
                alpha:
                    1.0
            )

        label.font =
            UIFont.systemFont(
                ofSize:
                    12.0
            )

        label.text =
            text

        tableView.backgroundView =
            label
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {

    }
}

