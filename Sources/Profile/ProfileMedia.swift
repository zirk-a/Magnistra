// Overview: Profile reposts grid and media opening gate.
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

final class MagnistraProfileRepostsGridTile:
    UIControl
{
    let imageView =
        UIImageView()

    var index =
        0

    override init(
        frame:
            CGRect
    ) {
        super.init(
            frame:
                frame
        )

        backgroundColor =
            UIColor(
                white:
                    0.88,
                alpha:
                    1.0
            )

        imageView.contentMode =
            .scaleAspectFill
        imageView.clipsToBounds =
            true

        addSubview(
            imageView
        )

        layer.borderWidth =
            0.5
        layer.borderColor =
            UIColor.white.cgColor
    }

    required init?(
        coder:
            NSCoder
    ) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageView.frame =
            bounds
    }
}

enum MagnistraProfileMediaOpeningGate {
    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        return q
    }()

    static func needsDetails(_ post: MagnistraRealPost) -> Bool {
        return (post.isVideo && post.videoURL == nil) ||
            (!post.isVideo && post.musicAudioURL == nil &&
             (post.musicTitle != nil || post.musicArtist != nil))
    }

    static func open(_ post: MagnistraRealPost,
                     completion: @escaping (MagnistraRealPost?) -> Void) {
        guard needsDetails(post) else { completion(post); return }
        queue.addOperation {
            let ready = try? MagnistraHomeService.loadProfileRichOpenPost(original: post)
            OperationQueue.main.addOperation { completion(ready) }
        }
    }

    static func showUnavailable() {
        UIAlertView(title: "Media unavailable",
                    message: "Instagram hasn't provided playable media for this post.",
                    delegate: nil, cancelButtonTitle: "OK").show()
    }
}

final class MagnistraProfileRepostsViewController:
    UIViewController,
    UIScrollViewDelegate
{
    private let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

    private let initialUserID:
        String?

    private let fallbackUsername:
        String

    private let isSelfProfile:
        Bool

    private let displaysSavedPosts: Bool

    private let queue =
        OperationQueue()

    private let imageQueue =
        OperationQueue()

    private let scrollView =
        UIScrollView()

    private var posts:
        [MagnistraRealPost] = []

    private var tiles:
        [MagnistraProfileRepostsGridTile] = []

    private var knownMediaIDs =
        Set<String>()

    private var resolvedUserID =
        ""

    private var nextMaxID:
        String? = nil

    private var loading =
        false

    private var reachedEnd =
        false

    init(
        userID:
            String?,
        fallbackUsername:
            String,
        isSelfProfile:
            Bool,
        savedMode:
            Bool = false
    ) {
        initialUserID =
            userID
        self.fallbackUsername =
            fallbackUsername
        self.isSelfProfile =
            isSelfProfile
        self.displaysSavedPosts = savedMode

        super.init(
            nibName:
                nil,
            bundle:
                nil
        )

        queue.maxConcurrentOperationCount =
            1
        imageQueue.maxConcurrentOperationCount =
            2
    }

    required init?(
        coder:
            NSCoder
    ) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title =
            displaysSavedPosts ? "Saved" : "Reposts"

        view.backgroundColor =
            UIColor(
                white:
                    0.96,
                alpha:
                    1.0
            )

        scrollView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        scrollView.delegate =
            self

        view.addSubview(
            scrollView
        )

        resolveAndLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)

        scrollView.frame =
            view.bounds

        let width =
            max(
                1.0,
                view.bounds
                    .size
                    .width
            )

        let gap:
            CGFloat =
                1.0

        let tileWidth =
            floor(
                (
                    width -
                    gap *
                    2.0
                ) /
                3.0
            )

        for i in
            0..<tiles.count
        {
            let row =
                CGFloat(
                    i /
                    3
                )

            let col =
                CGFloat(
                    i %
                    3
                )

            tiles[i].index =
                i

            tiles[i].frame =
                CGRect(
                    x:
                        col *
                        (
                            tileWidth +
                            gap
                        ),
                    y:
                        row *
                        (
                            tileWidth +
                            gap
                        ),
                    width:
                        tileWidth,
                    height:
                        tileWidth
                )
        }

        let rows =
            CGFloat(
                (
                    tiles.count +
                    2
                ) /
                3
            )

        scrollView.contentSize =
            CGSize(
                width:
                    width,
                height:
                    max(
                        rows *
                        (
                            tileWidth +
                            gap
                        ) +
                        8.0,
                        view.bounds
                            .size
                            .height +
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
            loading ||
            reachedEnd ||
            posts.isEmpty
        {
            return
        }

        let remaining =
            scrollView
                .contentSize
                .height -
            (
                scrollView
                    .contentOffset
                    .y +
                scrollView
                    .bounds
                    .size
                    .height
            )

        if
            remaining <
            360.0,
            magnistraUserInitiatedPagination(scrollView),
            let cursor =
                nextMaxID,
            !cursor.isEmpty
        {
            loadPage(
                maxID:
                    cursor,
                replacing:
                    false
            )
        }
    }

    private func resolveAndLoad() {

        if displaysSavedPosts {
            loadPage(maxID: nil, replacing: true)
            return
        }
        if
            let userID =
                initialUserID,
            !userID.isEmpty
        {
            resolvedUserID =
                userID

            loadPage(
                maxID:
                    nil,
                replacing:
                    true
            )

            return
        }

        if !isSelfProfile {
            showStatus(
                "Profile unavailable."
            )
            return
        }

        loading =
            true

        queue.addOperation {
            [weak self] in

            do {
                let profile =
                    try MagnistraHomeService
                        .loadCurrentProfile()

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard let self =
                            self
                        else {
                            return
                        }

                        self.loading =
                            false

                        self.resolvedUserID =
                            profile.userID

                        self.loadPage(
                            maxID:
                                nil,
                            replacing:
                                true
                        )
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?.loading =
                            false
                        self?.showStatus(
                            "Reposts unavailable."
                        )
                    }
            }
        }
    }

    private func loadPage(
        maxID:
            String?,
        replacing:
            Bool
    ) {
        if loading || (!displaysSavedPosts && resolvedUserID.isEmpty) {
            return
        }

        loading =
            true
        unifiedLoadingBand.show(!replacing && !posts.isEmpty, on: view, tracking: scrollView)

        let userID =
            resolvedUserID

        queue.addOperation {
            [weak self] in

            do {
                let page: MagnistraProfileMediaPage
                if self?.displaysSavedPosts == true {
                    page = try MagnistraHomeService.loadProfileSavedPage(maxID: maxID)
                } else {
                    page = try MagnistraHomeService.loadProfileRepostsPage(
                        userID: userID, maxID: maxID)
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?
                            .applyPage(
                                page,
                                replacing:
                                    replacing
                            )
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?.loading =
                            false
                        if let owner = self { owner.unifiedLoadingBand.show(false, on: owner.view) }
                        self?.showStatus(
                            self?.displaysSavedPosts == true
                                ? "Saved posts unavailable."
                                : "Reposts unavailable."
                        )
                    }
            }
        }
    }

    private func applyPage(
        _ page:
            MagnistraProfileMediaPage,
        replacing:
            Bool
    ) {
        loading =
            false
        unifiedLoadingBand.show(false, on: view)

        if replacing {
            for tile in tiles {
                tile.removeFromSuperview()
            }

            posts.removeAll()
            tiles.removeAll()
            knownMediaIDs.removeAll()
        }

        for post in
            page.posts
        {
            if
                knownMediaIDs.contains(
                    post.mediaID
                )
            {
                continue
            }

            knownMediaIDs.insert(
                post.mediaID
            )

            let index =
                posts.count

            posts.append(
                post
            )

            let tile =
                MagnistraProfileRepostsGridTile(
                    frame:
                        CGRect.zero
                )

            tile.index =
                index

            if post.isVideo || post.videoURL != nil {
                tile.addSubview(MagnistraExploreVideoCornerMark(
                    frame: CGRect(x: 6.0, y: 6.0, width: 14.0, height: 14.0)))
            } else if post.musicAudioURL != nil {
                let music = UILabel(frame: CGRect(x: 6.0, y: 6.0,
                                                  width: 22.0, height: 20.0))
                music.text = "♫"
                music.textColor = UIColor.white
                music.font = UIFont.boldSystemFont(ofSize: 16.0)
                music.backgroundColor = UIColor(white: 0.10, alpha: 0.60)
                music.textAlignment = .center
                music.layer.cornerRadius = 5.0
                music.clipsToBounds = true
                music.isUserInteractionEnabled = false
                tile.addSubview(music)
            }

            tile.addTarget(
                self,
                action:
                    #selector(
                        tileTapped(_:)
                    ),
                for:
                    .touchUpInside
            )

            tiles.append(
                tile
            )

            scrollView.addSubview(
                tile
            )

            loadImage(
                for:
                    post,
                tile:
                    tile
            )
        }

        nextMaxID =
            page.nextMaxID

        reachedEnd =
            page.nextMaxID ==
            nil

        if posts.isEmpty {
            showStatus(
                displaysSavedPosts ? "No saved posts." : "No reposts."
            )
        } else {
            scrollView.backgroundColor =
                UIColor.clear
        }

        view.setNeedsLayout()
    }

    private func loadImage(
        for post:
            MagnistraRealPost,
        tile:
            MagnistraProfileRepostsGridTile
    ) {
        let path =
            post.imagePath

        if
            !path.isEmpty,
            let image =
                UIImage(
                    contentsOfFile:
                        path
                )
        {
            tile.imageView.image =
                image
            return
        }

        let remote =
            post.imageURL

        guard
            !remote.isEmpty
        else {
            return
        }

        let stable =
            post.imageCacheKey

        imageQueue.addOperation {
            [weak self, weak tile] in

            guard
                let path =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                remote,
                            stableKey:
                                stable,
                            isAvatar:
                                false
                        ),
                let image =
                    UIImage(
                        contentsOfFile:
                            path
                    )
            else {
                MagnistraConnectionRecovery.shared.noteFailedMedia(
                    key: "reposts-grid:" + post.mediaID) { [weak self, weak tile] in
                    guard let owner = self, let tile = tile,
                          owner.view.window != nil, tile.superview != nil,
                          tile.imageView.image == nil else { return }
                    owner.loadImage(for: post, tile: tile)
                }
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

    @objc private func tileTapped(
        _ sender:
            MagnistraProfileRepostsGridTile
    ) {
        guard
            sender.index >= 0,
            sender.index <
                posts.count
        else {
            return
        }

        let index = sender.index
        let post = posts[index]
        if MagnistraProfileMediaOpeningGate.needsDetails(post) {
            MagnistraProfileMediaOpeningGate.open(post) { [weak self] ready in
                guard let self = self, let ready = ready,
                      index < self.posts.count,
                      self.posts[index].mediaID == post.mediaID else {
                    MagnistraProfileMediaOpeningGate.showUnavailable()
                    return
                }
                self.posts[index] = ready
                self.presentSelectedMedia(index: index)
            }
            return
        }
        presentSelectedMedia(index: index)
    }

    private func presentSelectedMedia(index: Int) {
        guard index >= 0, index < posts.count else { return }
        let selectedPost = posts[index]
        let snapshot = posts
        let tailStart = index + 1
        let controller = MagnistraExploreFeedViewController(
            selectedPost: selectedPost,
            deferredPostsProvider: {
                tailStart < snapshot.count
                    ? Array(snapshot[tailStart..<snapshot.count]) : []
            }, nextMaxID: nextMaxID, reachedEnd: reachedEnd)
        if displaysSavedPosts {
            controller.magnistraUseSavedFeed()
            controller.title = "Saved"
        } else {
            controller.magnistraUseRepostsFeed(userID: resolvedUserID)
            controller.title = "Reposts"
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func showStatus(
        _ text:
            String
    ) {
        for view in
            scrollView.subviews
        {
            if
                view.tag ==
                98761
            {
                view.removeFromSuperview()
            }
        }

        let label =
            UILabel(
                frame:
                    view.bounds
            )

        label.tag =
            98761
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

        scrollView.addSubview(
            label
        )
    }
}

func magnistraGridThumbnail(
    path: String
) -> UIImage? {
    guard
        let original =
            UIImage(
                contentsOfFile:
                    path
            )
    else {
        return nil
    }

    let sourceSize =
        original.size

    let longest =
        max(
            sourceSize.width,
            sourceSize.height
        )

    if
        longest <= 360.0 ||
        longest <= 0.0
    {
        return original
    }

    let ratio =
        360.0 /
        longest

    let targetSize =
        CGSize(
            width:
                max(
                    1.0,
                    floor(
                        sourceSize.width *
                        ratio
                    )
                ),
            height:
                max(
                    1.0,
                    floor(
                        sourceSize.height *
                        ratio
                    )
                )
        )

    UIGraphicsBeginImageContext(
        targetSize
    )

    original.draw(
        in:
            CGRect(
                x:
                    0.0,
                y:
                    0.0,
                width:
                    targetSize.width,
                height:
                    targetSize.height
            )
    )

    let resized =
        UIGraphicsGetImageFromCurrentImageContext()

    UIGraphicsEndImageContext()

    return resized
}

func magnistraProfileDisplayCount(_ value: Int) -> String {
    if value < 10000 { return String(value) }
    let million = value >= 1000000
    let unit = million ? 1000000 : 1000
    let whole = value / unit
    let tenth = (value % unit) / (unit / 10)
    let suffix = million ? "M" : "K"
    if tenth == 0 { return "\(whole)\(suffix)" }
    return "\(whole),\(tenth)\(suffix)"
}

enum MagnistraLoadFailureDiagnostic {
    static func record(_ section: String, error: Error) {
        let n = error as NSError
        let domain = n.domain.replacingOccurrences(
            of: "[^A-Za-z0-9_.-]", with: "", options: .regularExpression)
        print("MAGNISTRA_LOAD_FAILURE section=\(section) domain=\(domain) code=\(n.code)")
    }

    static func canTryAlternateProfileFeed(_ error: Error) -> Bool {
        let n = error as NSError
        if n.domain == "MagnistraProfileMedia" && n.code == 6472 { return true }
        if n.domain == "MagnistraExploreSearch" &&
            (n.code == 6802 || n.code == 6803) { return true }
        return false
    }

    static func profileGridStatus(_ error: Error) -> String {
        let n = error as NSError
        if n.domain == "MagnistraExploreSearch" && n.code >= 100 && n.code <= 599 {
            return "Posts error (HTTP \(n.code))"
        }
        if n.domain == "MagnistraProfileMedia" || n.domain == "MagnistraExploreSearch" {
            return "Posts error (E\(n.code))"
        }
        return "Posts error (E\(n.code))"
    }
}

