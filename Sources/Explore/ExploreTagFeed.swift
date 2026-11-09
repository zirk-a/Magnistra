// Overview: Tag feed view controller plus tile, video corner mark and photo-music button views.
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

final class MagnistraExploreTile:
    UIButton
{
    var postIndex = 0

    override init(
        frame: CGRect
    ) {
        super.init(
            frame:
                frame
        )

        clipsToBounds = true
        backgroundColor =
            UIColor.clear

        imageView?
            .contentMode =
                .scaleAspectFill

        adjustsImageWhenHighlighted =
            true
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }
}

final class MagnistraExploreVideoCornerMark:
    UIImageView
{
    override init(
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        backgroundColor =
            UIColor.clear

        image =
            UIImage(
                named:
                    "MagnistraExplorePlay"
            )

        contentMode =
            .scaleAspectFit

        clipsToBounds =
            false

        isUserInteractionEnabled =
            false
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }
}

final class MagnistraExplorePhotoMusicTapButton:
    UIButton
{
    var mediaID:
        String = ""

    var onLongPress:
        ((MagnistraExplorePhotoMusicTapButton) -> Void)?
        = nil

    override init(
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        installLongPress()
    }

    required init?(
        coder: NSCoder
    ) {
        super.init(
            coder: coder
        )

        installLongPress()
    }

    private func installLongPress() {
        let recognizer =
            UILongPressGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        photoMusicLongPressed(
                            _:
                        )
                    )
            )

        recognizer.minimumPressDuration =
            0.45

        recognizer.cancelsTouchesInView =
            true

        addGestureRecognizer(
            recognizer
        )
    }

    @objc private func photoMusicLongPressed(
        _ recognizer:
            UILongPressGestureRecognizer
    ) {
        guard
            recognizer.state ==
                .began
        else {
            return
        }

        onLongPress?(
            self
        )
    }
}

final class MagnistraExploreTagFeedViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate
{
    let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

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

    let tag:
        String

    let tagSearchSessionID:
        String

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
        tag:
            String,
        searchSessionID:
            String,
        selectedPost:
            MagnistraRealPost,
        deferredPostsProvider:
            @escaping () -> [MagnistraRealPost],
        nextMaxID:
            String?,
        reachedEnd:
            Bool
    ) {
        self.tag =
            tag

        self.tagSearchSessionID =
            searchSessionID

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
            title =
            "#" +
            tag
        }

        view.backgroundColor =
            UIColor(
                white: 0.94,
                alpha: 1.0
            )

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none

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

