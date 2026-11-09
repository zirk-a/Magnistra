// Overview: Reels main screen: page views and view controller.
import UIKit

final class MagnistraReelOpenPostButton:
    UIButton
{
    var mediaID = ""

    override init(
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        backgroundColor =
            UIColor.clear

        isOpaque =
            false
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func draw(
        _ rect: CGRect
    ) {
        super.draw(
            rect
        )

        let backing =
            rect.insetBy(
                dx: 1.0,
                dy: 1.0
            )

        UIColor(
            white: 0.0,
            alpha: 0.62
        ).setFill()

        UIBezierPath(
            roundedRect:
                backing,
            cornerRadius:
                6.0
        ).fill()

        UIColor(
            white: 1.0,
            alpha: 0.96
        ).setStroke()

        let path =
            UIBezierPath()

        path.lineWidth =
            2.0

        path.lineCapStyle =
            .round

        path.lineJoinStyle =
            .round

        let left =
            rect.midX -
            6.0

        let bottom =
            rect.midY +
            6.0

        let right =
            rect.midX +
            7.0

        let top =
            rect.midY -
            7.0

        path.move(
            to:
                CGPoint(
                    x: left,
                    y: bottom
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: right,
                    y: top
                )
        )

        path.move(
            to:
                CGPoint(
                    x:
                        right -
                        7.0,
                    y:
                        top
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: right,
                    y: top
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: right,
                    y:
                        top +
                        7.0
                )
        )

        path.stroke()
    }
}

final class MagnistraReelPageView:
    UIView
{
    let posterView = UIImageView()
    let videoHostView = UIView()
    let surfaceButton =
        MagnistraVideoSurfaceButton(
            frame: CGRect.zero
        )
    let muteButton =
        MagnistraVideoGlyphButton(
            frame: CGRect.zero
        )
    let postButton =
        MagnistraReelOpenPostButton(
            frame: CGRect.zero
        )

    let textScrimView =
        UIView()

    let usernameLabel = UILabel()
    let captionLabel = UILabel()

    var mediaID = ""

    var onZoomGestureActive:
        ((Bool) -> Void)? = nil

    private var reelVideoZoomScale:
        CGFloat = 1.0

    private var reelPinchStartScale:
        CGFloat = 1.0

    private var suppressSurfaceTapUntil:
        TimeInterval = 0.0

    private var reelPanStartTranslation:
        CGPoint = .zero

    private var reelPanCurrentTranslation:
        CGPoint = .zero

    private var reelPanGesture:
        UIPanGestureRecognizer? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.black

        videoHostView.backgroundColor = UIColor.black
        addSubview(videoHostView)

        posterView.backgroundColor = UIColor.black
        posterView.contentMode = .scaleAspectFit
        posterView.clipsToBounds = true
        posterView.isOpaque = true
        addSubview(posterView)

        surfaceButton.backgroundColor = UIColor.clear
        addSubview(surfaceButton)

        textScrimView.backgroundColor =
            UIColor(
                white: 0.0,
                alpha: 0.48
            )

        textScrimView.isUserInteractionEnabled =
            false

        addSubview(
            textScrimView
        )

        usernameLabel.backgroundColor =
            UIColor.clear

        usernameLabel.isOpaque =
            false

        usernameLabel.textColor = UIColor.white
        usernameLabel.font =
            UIFont.boldSystemFont(ofSize: 13.0)
        usernameLabel.shadowColor = UIColor.black
        usernameLabel.shadowOffset =
            CGSize(width: 0.0, height: 1.0)
        addSubview(usernameLabel)

        captionLabel.textColor = UIColor.white
        captionLabel.font =
            UIFont.systemFont(ofSize: 11.0)
        captionLabel.numberOfLines = 2
        captionLabel.backgroundColor = UIColor.clear

        captionLabel.isOpaque =
            false
        captionLabel.shadowColor = UIColor.black
        captionLabel.shadowOffset =
            CGSize(width: 0.0, height: 1.0)
        addSubview(captionLabel)

        muteButton.glyphKind = .volume
        addSubview(muteButton)

        let reelPinch =
            UIPinchGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        reelVideoPinched(
                            _:
                        )
                    )
            )

        reelPinch.cancelsTouchesInView =
            true

        surfaceButton.isMultipleTouchEnabled =
            true

        surfaceButton.addGestureRecognizer(
            reelPinch
        )

        let reelPan =
            UIPanGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        reelVideoPanned(
                            _:
                        )
                    )
            )

        reelPan.maximumNumberOfTouches =
            1

        reelPan.cancelsTouchesInView =
            true

        reelPan.isEnabled =
            false

        surfaceButton.addGestureRecognizer(
            reelPan
        )

        reelPanGesture =
            reelPan

        addSubview(postButton)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let zoomTransform =
            CGAffineTransform(
                scaleX:
                    reelVideoZoomScale,
                y:
                    reelVideoZoomScale
            )

        posterView.transform =
            CGAffineTransform.identity

        videoHostView.transform =
            CGAffineTransform.identity

        posterView.frame =
            bounds

        videoHostView.frame =
            bounds

        posterView.transform =
            zoomTransform

        videoHostView.transform =
            zoomTransform
        surfaceButton.frame = bounds

        let bottom = bounds.size.height

        let reelTextViews:
            [UILabel] = [
                usernameLabel,
                captionLabel
            ]

        var reelTextBottom =
            bottom - 10.0

        for label in
            reelTextViews.reversed()
        {
            let fitted =
                label.sizeThatFits(
                    CGSize(
                        width:
                            max(
                                40.0,
                                bounds.size.width -
                                24.0
                            ),
                        height:
                            200.0
                    )
                )

            let maxHeight:
                CGFloat =
                (
                    label.numberOfLines == 1
                    ? 22.0
                    : 54.0
                )

            let targetHeight =
                max(
                    label.font.lineHeight,
                    min(
                        maxHeight,
                        fitted.height
                    )
                )

            var frame =
                label.frame

            frame.size.height =
                targetHeight

            reelTextBottom -=
                targetHeight

            frame.origin.y =
                max(
                    0.0,
                    reelTextBottom
                )

            label.frame =
                frame

            reelTextBottom -=
                4.0
        }

        textScrimView.frame =
            CGRect(
                x: 0.0,
                y:
                    max(
                        0.0,
                        reelTextBottom -
                        6.0
                    ),
                width:
                    bounds.size.width,
                height:
                    bottom -
                    max(
                        0.0,
                        reelTextBottom -
                        6.0
                    )
            )

        usernameLabel.frame =
            CGRect(
                x: 14.0,
                y: max(20.0, bottom - 82.0),
                width: max(40.0, bounds.size.width - 70.0),
                height: 20.0
            )

        captionLabel.frame =
            CGRect(
                x: 14.0,
                y: max(40.0, bottom - 60.0),
                width: max(40.0, bounds.size.width - 70.0),
                height: 42.0
            )

        muteButton.frame =
            CGRect(
                x: max(4.0, bounds.size.width - 46.0),
                y: max(4.0, bottom - 44.0),
                width: 36.0,
                height: 36.0
            )

        postButton.frame =
            CGRect(
                x: max(4.0, bounds.size.width - 46.0),
                y: 8.0,
                width: 38.0,
                height: 38.0
            )

        let textWidth = max(40.0, bounds.size.width - 70.0)
        let captionFit = captionLabel.sizeThatFits(
            CGSize(width: textWidth, height: 120.0)
        )
        let captionHeight = max(
            captionLabel.font.lineHeight,
            min(34.0, captionFit.height)
        )
        let bottomInset: CGFloat = 8.0
        let captionY = max(0.0, bottom - bottomInset - captionHeight)
        captionLabel.frame = CGRect(
            x: 14.0,
            y: captionY,
            width: textWidth,
            height: captionHeight
        )
        let usernameHeight: CGFloat = 20.0
        let usernameY = max(0.0, captionY - 3.0 - usernameHeight)
        usernameLabel.frame = CGRect(
            x: 14.0,
            y: usernameY,
            width: textWidth,
            height: usernameHeight
        )
        let scrimTop = max(0.0, usernameY - 4.0)
        textScrimView.frame = CGRect(
            x: 0.0,
            y: scrimTop,
            width: bounds.size.width,
            height: bottom - scrimTop
        )
        bringSubviewToFront(usernameLabel)
        bringSubviewToFront(captionLabel)
        bringSubviewToFront(muteButton)

}

    @objc private func reelVideoPinched(
        _ recognizer: UIPinchGestureRecognizer
    ) {
        suppressSurfaceTapUntil = Date().timeIntervalSince1970 + 0.30
        switch recognizer.state {
        case .began:
            reelPinchStartScale = reelVideoZoomScale
            onZoomGestureActive?(true)
        case .changed:
            let next = reelPinchStartScale * recognizer.scale
            reelVideoZoomScale = min(4.0, max(1.0, next))
            reelPanGesture?.isEnabled = reelVideoZoomScale > 1.01
            applyReelVideoPanTransform()
        case .ended, .cancelled, .failed:
            if reelVideoZoomScale < 1.02 {
                reelVideoZoomScale = 1.0
                reelPanStartTranslation = .zero
                reelPanCurrentTranslation = .zero
            }
            let remainsZoomed = reelVideoZoomScale > 1.01
            reelPanGesture?.isEnabled = remainsZoomed
            applyReelVideoPanTransform()
            onZoomGestureActive?(remainsZoomed)
        default:
            break
        }
    }

    private func currentReelVideoZoomScale()
        -> CGFloat
    {
        let transform =
            videoHostView.transform

        let scaleX =
            sqrt(
                (transform.a * transform.a) +
                (transform.c * transform.c)
            )

        return
            max(
                1.0,
                scaleX
            )
    }

    private func applyReelVideoPanTransform() {
        let scale = reelVideoZoomScale
        if scale <= 1.01 { reelPanCurrentTranslation = .zero }
        let extraX = max(0.0, ((bounds.size.width * scale) - bounds.size.width) / 2.0)
        let extraY = max(0.0, ((bounds.size.height * scale) - bounds.size.height) / 2.0)
        let clampedX = min(max(reelPanCurrentTranslation.x, -extraX), extraX)
        let clampedY = min(max(reelPanCurrentTranslation.y, -extraY), extraY)
        reelPanCurrentTranslation = CGPoint(x: clampedX, y: clampedY)
        let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(
            x: clampedX / max(scale, 1.0),
            y: clampedY / max(scale, 1.0)
        )
        posterView.transform = transform
        videoHostView.transform = transform
    }

    @objc private func reelVideoPanned(
        _ recognizer: UIPanGestureRecognizer
    ) {
        guard reelVideoZoomScale > 1.01 else { return }
        suppressSurfaceTapUntil = Date().timeIntervalSince1970 + 0.30
        switch recognizer.state {
        case .began:
            reelPanStartTranslation = reelPanCurrentTranslation
            onZoomGestureActive?(true)
        case .changed:
            let delta = recognizer.translation(in: self)
            reelPanCurrentTranslation = CGPoint(
                x: reelPanStartTranslation.x + delta.x,
                y: reelPanStartTranslation.y + delta.y
            )
            applyReelVideoPanTransform()
        case .ended, .cancelled, .failed:
            applyReelVideoPanTransform()
            onZoomGestureActive?(true)
        default:
            break
        }
    }

    func shouldSuppressSurfaceTapAfterPinch()
        -> Bool
    {
        return
            Date()
                .timeIntervalSince1970 <
            suppressSurfaceTapUntil
    }

    func resetReelVideoZoom() {
        reelVideoZoomScale = 1.0
        reelPinchStartScale = 1.0
        reelPanStartTranslation = .zero
        reelPanCurrentTranslation = .zero
        reelPanGesture?.isEnabled = false
        posterView.transform = CGAffineTransform.identity
        videoHostView.transform = CGAffineTransform.identity
        onZoomGestureActive?(false)
    }

    func configure(post: MagnistraRealPost) {
        mediaID = post.mediaID
        surfaceButton.mediaID = post.mediaID
        muteButton.mediaID = post.mediaID
        postButton.mediaID = post.mediaID
        muteButton.glyphKind = .volume

        usernameLabel.text =
            "@" + post.username

        captionLabel.text =
            post.caption

        posterView.image = nil
        posterView.isHidden = false
        posterView.alpha = 1.0
    }
}

enum MagnistraReelsWarmState {
    static var posts: [MagnistraRealPost] = []
    static var index: Int = 0
    static var cursor: String? = nil
    static var exhausted: Bool = false
    static var updatedAt: Double = 0.0
}

final class MagnistraReelsViewController:
    UIViewController,
    UIScrollViewDelegate
{
    var magnistraReelsRetryAfter: TimeInterval = 0.0

    let scrollView = UIScrollView()
    let loadingLabel = UILabel()

    let bottomLoadingLabel = UILabel()
    let closeButton =
        MagnistraVideoGlyphButton(
            frame: CGRect.zero
        )

    let loadQueue = OperationQueue()
    let imageQueue = OperationQueue()

    let reelPlayer =
        MagnistraInlineVideoPlayer(
            streamProxy:
                StreamProxy()
        )

    var posts: [MagnistraRealPost] = []
    var seenMediaIDs = Set<String>()
    var renderedPages:
        [Int: MagnistraReelPageView] = [:]

    var nextMaxID: String? = nil
    var reachedEnd = false
    var isLoading = false
    var initialContinuationBudget = 2
    var currentIndex = 0

    var navigationBarWasHidden = false
    var statusBarWasHidden = false

    weak var hostNavigationController:
        UINavigationController?

    var posterReleaseMediaID:
        String? = nil
    var startCurrentPending = false

    var resumeFromPostMediaID:
        String? = nil

    var resumeFromPostSeconds:
        Double = 0.0

    var resumeFromPostWasPlaying =
        false

    var preservePlayerForPost =
        false

    var contentGeneration = 0

    override init(
        nibName nibNameOrNil: String?,
        bundle nibBundleOrNil: Bundle?
    ) {
        super.init(
            nibName: nibNameOrNil,
            bundle: nibBundleOrNil
        )

        loadQueue.maxConcurrentOperationCount = 1
        imageQueue.maxConcurrentOperationCount = 1
    }

    convenience init() {
        self.init(
            nibName: nil,
            bundle: nil
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black

        scrollView.backgroundColor = UIColor.black
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true

        scrollView
            .panGestureRecognizer
            .maximumNumberOfTouches =
                1
        scrollView.delegate = self
        view.addSubview(scrollView)

        loadingLabel.text = "Loading..."
        loadingLabel.backgroundColor =
            UIColor(white: 0.10, alpha: 0.88)
        loadingLabel.isOpaque =
            false
        loadingLabel.textColor = UIColor.white
        loadingLabel.font =
            UIFont.boldSystemFont(ofSize: 12.0)
        loadingLabel.textAlignment = .center
        view.addSubview(loadingLabel)

        bottomLoadingLabel.text = "Loading..."
        bottomLoadingLabel.font = UIFont.boldSystemFont(ofSize: 12.0)
        bottomLoadingLabel.textColor = UIColor.white
        bottomLoadingLabel.textAlignment = .center
        bottomLoadingLabel.backgroundColor =
            UIColor(white: 0.10, alpha: 0.88)
        bottomLoadingLabel.isHidden = true
        bottomLoadingLabel.isUserInteractionEnabled = false
        scrollView.addSubview(bottomLoadingLabel)

        closeButton.glyphKind = .close
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )
        view.addSubview(closeButton)

        if !magnistraRestoreReelsPosition() {
            requestPage(
                maxID: nil,
                replacing: true
            )
        }

        magnistraReelsInitialLoadingClearBackground()
    }

    override func viewWillAppear(
        _ animated: Bool
    ) {
        super.viewWillAppear(animated)

        hostNavigationController =
            navigationController

        navigationBarWasHidden =
            navigationController?
                .isNavigationBarHidden ??
            false

        statusBarWasHidden =
            UIApplication.shared
                .isStatusBarHidden

        navigationController?
            .setNavigationBarHidden(
                true,
                animated: false
            )

        UIApplication.shared
            .setStatusBarHidden(
                true,
                with: .none
            )
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": true])

    }

    override func viewDidAppear(
        _ animated: Bool
    ) {
        super.viewDidAppear(
            animated
        )

        resumeFromPostMediaID =
            nil

        resumeFromPostSeconds =
            0.0

        resumeFromPostWasPlaying =
            false

        preservePlayerForPost =
            false

        if !posts.isEmpty {
            scheduleStartCurrent()
        }
    }

        var magnistraReelsOpeningPostTransition = false
    weak var magnistraReelsPopTopLayer: UIView?
    var magnistraReelsPopOriginalZ: CGFloat = 0.0

override func viewWillDisappear(
        _ animated: Bool
    ) {
        magnistraSaveReelsPosition()
        NSObject
            .cancelPreviousPerformRequests(
                withTarget: self
            )

        imageQueue.cancelAllOperations()
        reelPlayer.clearPreparedReel()

        if preservePlayerForPost {
            if
                let mediaID =
                    resumeFromPostMediaID
            {
                _ =
                    reelPlayer
                        .pauseIfMediaID(
                            mediaID
                        )
            }
        } else {
            reelPlayer
                .stop()
        }

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        UIApplication.shared
            .setStatusBarHidden(
                statusBarWasHidden,
                with: .none
            )
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": false])

        hostNavigationController?
            .setNavigationBarHidden(
                navigationBarWasHidden,
                animated: false
            )

        hostNavigationController?
            .view
            .setNeedsLayout()

        hostNavigationController?
            .view
            .layoutIfNeeded()

        magnistraReelsKeepVisualAboveExploreTopbar()

        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(
        _ animated: Bool
    ) {
        super.viewDidDisappear(
            animated
        )
        magnistraReelsRestoreNormalVisualOrder()
        magnistraReelsOpeningPostTransition = false

        let nav =
            hostNavigationController

        OperationQueue.main
            .addOperation {
                nav?
                    .view
                    .setNeedsLayout()

                nav?
                    .view
                    .layoutIfNeeded()
            }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bounds = view.bounds
        scrollView.frame = bounds

        loadingLabel.frame =
            CGRect(
                x: 20.0,
                y:
                    max(
                        20.0,
                        bounds.size.height * 0.5 - 15.0
                    ),
                width:
                    max(
                        40.0,
                        bounds.size.width - 40.0
                    ),
                height: 30.0
            )

        closeButton.frame =
            CGRect(
                x: 8.0,
                y: 8.0,
                width: 38.0,
                height: 38.0
            )

        updateContentGeometry(
            preserveIndex: true
        )

        magnistraReelsInitialLoadingClearBackground()
    }
}
