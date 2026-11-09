// Overview: Home feed view controller.
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

final class HomeViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate
{

    var homeRowHeightCache: [Int: CGFloat] = [:]
    var homeRowHeightCacheWidth: CGFloat = -1.0
    var homeRequestStartedAtEpoch: Double = 0.0

    let pullRefreshGesture = MagnistraPullRefreshGesture()

    let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

    let postHeaderScroll = MagnistraPostHeaderScrollBehavior()
    let storyQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q
    }()
    var storyLoadGeneration = 0
    let storyTray = MagnistraStoryTrayView(frame: CGRect(x: 0, y: 0, width: 320, height: 88))

    var emptyFeedFreshRetryCount =
        0

    let emptyFeedFreshRetryLimit =
        0

    var transientInitialErrorRetryCount =
        0

    let transientInitialErrorRetryLimit =
        0

    var pendingInitialFreshRetry =
        false

    var tableView: UITableView!
    var statusLabel: UILabel!

    var posts:
        [MagnistraRealPost] = []

    var nextMaxID:
        String? = nil

    var didStartRealLoad = false
    var isLoadingPage = false
    var reachedEnd = false

    var preservingFeedDuringPullRefresh = false

    var homePullRefreshIsShowing = false

    var expandedPostIDs =
        Set<String>()

    var activePhotoQualityToken =
        MagnistraMediaPreferences
            .photoQuality
            .cacheToken

    let postReuseID =
        "MagnistraClassicPost"

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor =
            UIColor(
                white: 0.94,
                alpha: 1.0
            )

        configureClassicTitle()
        configureTable()
        configureStatusLabel()

        MagnistraInlineVideoPlayer
            .shared
            .onStopped = {
                [weak self] mediaID in

                self?
                    .refreshVideoControls(
                        mediaID:
                            mediaID
                    )
            }

        MagnistraPhotoMusicPlayer
            .shared
            .onStopped = {
                [weak self] mediaID in

                self?
                    .refreshPhotoMusicControl(
                        mediaID:
                            mediaID
                    )
            }

        showStatus(
            "Loading your feed…"
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)
        postHeaderScroll.restoreViewportAfterOwnerLayout()
    }

    override func viewDidAppear(
        _ animated: Bool
    ) {
        super.viewDidAppear(animated)
        postHeaderScroll.activate(tableView, navigationController: navigationController)

        let currentQualityToken =
            MagnistraMediaPreferences
                .photoQuality
                .cacheToken

        if !didStartRealLoad {
            didStartRealLoad = true
            activePhotoQualityToken =
                currentQualityToken
            refreshFeed()
        } else if
            currentQualityToken !=
                activePhotoQualityToken
        {
            activePhotoQualityToken =
                currentQualityToken
            refreshFeed()
        }

        if
            pendingInitialFreshRetry &&
            posts.isEmpty &&
            !isLoadingPage
        {
            perform(
                #selector(
                    retryEmptyInitialFeed
                ),
                with:
                    nil,
                afterDelay:
                    0.10
            )
        }
}

    override func viewWillDisappear(
        _ animated: Bool
    ) {
        super.viewWillDisappear(
            animated
        )
        postHeaderScroll.deactivate()

        MagnistraInlineVideoPlayer
            .shared
            .stop()

        MagnistraPhotoMusicPlayer
            .shared
            .stop()
    }

}

extension HomeViewController {
    func magnistraV2ReloadAfterLogin() { refreshFeed() }
}
