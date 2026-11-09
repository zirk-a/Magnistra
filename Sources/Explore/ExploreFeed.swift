// Overview: Explore post feed view controller and the user/tag cells used in search results.
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

final class MagnistraExploreFeedViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate
{
    let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

    var magnistraSavedFeed = false

    var magnistraRepostsUserID: String? = nil

    var bufferedPaginationPosts:
        [MagnistraRealPost] =
            []

    var paginationDrainScheduled =
        false

    var paginationScrollPaused =
        false

    let paginationHeavyVelocity:
        CGFloat =
            850.0

    let savedVideoResolveQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    var savedVideoRequested = Set<String>()
    var savedMetadataCompleted = Set<String>()
    var savedMediaUpgraded = Set<String>()
    var savedVideoPendingRows = Set<Int>()

    var posts:
        [MagnistraRealPost]

    var seenMediaIDs =
        Set<String>()

    var nextMaxID:
        String?

    var reachedEnd:
        Bool

    var isLoadingPage =
        false

    let tableView =
        UITableView(
            frame: CGRect.zero,
            style: .plain
        )

    let loadQueue =
        OperationQueue()

    let loadingFooter =
        UILabel(
            frame:
                CGRect(
                    x: 0.0,
                    y: 0.0,
                    width: 320.0,
                    height: 38.0
                )
        )

    var expandedMediaIDs =
        Set<String>()

    var prewarmedPostCells:
        [String: MagnistraPostCell] = [:]

    var prewarmCompletedMediaIDs =
        Set<String>()

    var prewarmQueueRows:
        [Int] = []

    var prewarmQueueCursor =
        0

    var prewarmAnchorRow =
        0

    let prewarmCapacity =
        1

    var deferredPostsProvider:
        (() -> [MagnistraRealPost])?

    var didScheduleDeferredPosts =
        false

    init(
        selectedPost:
            MagnistraRealPost,
        deferredPostsProvider:
            @escaping () -> [MagnistraRealPost],
        nextMaxID:
            String?,
        reachedEnd:
            Bool
    ) {
        self.posts = [
            selectedPost
        ]

        self.deferredPostsProvider =
            deferredPostsProvider

        self.nextMaxID =
            nextMaxID

        self.reachedEnd =
            reachedEnd

        seenMediaIDs.insert(
            selectedPost.mediaID
        )

        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if title == nil {
            title = "Explore"
        }

        view.backgroundColor =
            UIColor(
                white: 0.94,
                alpha: 1.0
            )

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none

        tableView.backgroundColor = UIColor(
            white: 0.94, alpha: 1.0)

        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        loadingFooter.backgroundColor =
            UIColor(white: 0.10, alpha: 0.88)

        loadingFooter.textAlignment =
            .center

        loadingFooter.textColor =
            UIColor(white: 0.45, alpha: 1.0)

        loadingFooter.font =
            UIFont.boldSystemFont(
                ofSize: 12.0
            )

        loadingFooter.text = "Loading..."

        loadQueue.maxConcurrentOperationCount = 1

        view.addSubview(tableView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)
        tableView.frame = view.bounds
    }

    override func viewDidAppear(
        _ animated:
            Bool
    ) {
        super.viewDidAppear(
            animated
        )

        guard
            !didScheduleDeferredPosts
        else {
            return
        }

        didScheduleDeferredPosts =
            true

        OperationQueue.main
            .addOperation {
                [weak self] in

                self?
                    .installDeferredPosts()

                self?
                    .scheduleSuccessorCellPrewarm()
            }
    }

    override func viewWillDisappear(
        _ animated: Bool
    ) {
        super.viewWillDisappear(animated)

        MagnistraInlineVideoPlayer
            .shared
            .stop()

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        MagnistraDecodedImageLoader
            .shared
            .setPostImageLoadsSuspended(
                false
            )

        NSObject
            .cancelPreviousPerformRequests(
                withTarget:
                    self,
                selector:
                    #selector(
                        drainBufferedPaginationPosts
                    ),
                object:
                    nil
            )

        paginationDrainScheduled =
            false
}

}

final class MagnistraExploreSearchUserCell:
    UITableViewCell
{
    let avatarView =
        UIImageView()

    let usernameLabel =
        UILabel()

    let fullNameLabel =
        UILabel()

    var representedID =
        ""

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(
            style:
                style,
            reuseIdentifier:
                reuseIdentifier
        )

        selectionStyle =
            .gray

        avatarView.backgroundColor =
            UIColor(
                white:
                    0.84,
                alpha:
                    1.0
            )
        avatarView.contentMode =
            .scaleAspectFill
        avatarView.clipsToBounds =
            true
        avatarView.layer.cornerRadius =
            22.0
        contentView.addSubview(
            avatarView
        )

        usernameLabel.font =
            UIFont.boldSystemFont(
                ofSize:
                    13.0
            )
        usernameLabel.textColor =
            MagnistraPostCell
                .magnistraBlue
        usernameLabel.backgroundColor =
            UIColor.clear
        contentView.addSubview(
            usernameLabel
        )

        fullNameLabel.font =
            UIFont.systemFont(
                ofSize:
                    12.0
            )
        fullNameLabel.textColor =
            UIColor(
                white:
                    0.38,
                alpha:
                    1.0
            )
        fullNameLabel.backgroundColor =
            UIColor.clear
        contentView.addSubview(
            fullNameLabel
        )
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        avatarView.frame =
            CGRect(
                x:
                    10.0,
                y:
                    7.0,
                width:
                    44.0,
                height:
                    44.0
            )

        usernameLabel.frame =
            CGRect(
                x:
                    64.0,
                y:
                    8.0,
                width:
                    max(
                        1.0,
                        bounds.size.width -
                        74.0
                    ),
                height:
                    21.0
            )

        fullNameLabel.frame =
            CGRect(
                x:
                    64.0,
                y:
                    29.0,
                width:
                    max(
                        1.0,
                        bounds.size.width -
                        74.0
                    ),
                height:
                    19.0
            )
    }
}

final class MagnistraExploreSearchTagTile:
    UIControl
{
    let imageView =
        UIImageView()

    var index =
        0

    override init(
        frame: CGRect
    ) {
        super.init(
            frame:
                frame
        )

        clipsToBounds =
            true
        backgroundColor =
            UIColor(
                white:
                    0.86,
                alpha:
                    1.0
            )

        imageView.frame =
            bounds
        imageView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]
        imageView.contentMode =
            .scaleAspectFill
        imageView.clipsToBounds =
            true
        imageView.isUserInteractionEnabled =
            false
        addSubview(
            imageView
        )
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }
}

