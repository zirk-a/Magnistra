// Overview: Story tray and story viewer.
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

private enum MagnistraStoryImageQueue {
    static let shared: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
}

private final class MagnistraStoryRing: UIView {
    private let gradient = CAGradientLayer()
    private let maskShape = CAShapeLayer()
    private let imageView = UIImageView()
    private let label = UILabel()
    private let reel: MagnistraStoryReel
    var onOpen: ((MagnistraStoryReel) -> Void)?

    init(reel: MagnistraStoryReel, frame: CGRect, homeModuleStyle: Bool = false) {
        self.reel = reel
        super.init(frame: frame)
        backgroundColor = UIColor.clear
        clipsToBounds = false
        let ringFrame = CGRect(x: 6, y: 2, width: 60, height: 60)
        gradient.frame = ringFrame
        gradient.colors = [UIColor(red: 0.30, green: 0.45, blue: 0.96, alpha: 1).cgColor,
                           UIColor(red: 0.48, green: 0.43, blue: 0.93, alpha: 1).cgColor,
                           UIColor(red: 0.67, green: 0.40, blue: 0.93, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        let center = CGPoint(x: 30, y: 30)
        let ring = UIBezierPath(arcCenter: center, radius: 27, startAngle: 0,
                                endAngle: CGFloat.pi * 2, clockwise: true)
        maskShape.path = ring.cgPath
        maskShape.lineWidth = 3
        maskShape.fillColor = UIColor.clear.cgColor
        maskShape.strokeColor = UIColor.black.cgColor
        if reel.isSeen || reel.highlight {
            let gray = UIColor(white: 0.76, alpha: 1)
            gradient.colors = [gray.cgColor, gray.cgColor]
        }
        gradient.mask = maskShape
        layer.addSublayer(gradient)
        imageView.frame = CGRect(x: 12, y: 8, width: 48, height: 48)
        imageView.layer.cornerRadius = 24
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor(white: 0.88, alpha: 1)
        addSubview(imageView)
        label.frame = CGRect(x: 0, y: homeModuleStyle ? 62 : 65, width: bounds.width, height: 17)
        label.backgroundColor = UIColor.clear
        label.isOpaque = false
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 10)
        label.textColor = UIColor(white: 0.24, alpha: 1)
        label.text = reel.title
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
        if !reel.avatarURL.isEmpty {
            MagnistraStoryImageQueue.shared.addOperation { [weak self] in
                let image = MagnistraHomeService.loadProfileAvatar(primaryURL: reel.avatarURL, fallbackURL: nil)
                OperationQueue.main.addOperation { [weak self] in self?.imageView.image = image }
            }
        }
    }
    required init?(coder: NSCoder) { return nil }
    @objc private func openTapped() { onOpen?(reel) }
}

final class MagnistraStoryTrayView: UIView {
    private let scroller = UIScrollView()

    private let homeTopRule = UIView()
    private let homeBottomRule = UIView()
    private var entries: [MagnistraStoryReel] = []
    var onOpen: ((MagnistraStoryReel) -> Void)?
    var displayedReels: [MagnistraStoryReel] { return entries }
    private var compactHomeStories = false

    func useCompactHomeStoriesStyle() {
        compactHomeStories = true
        backgroundColor = UIColor.white
        isOpaque = true
        scroller.backgroundColor = UIColor.white
        scroller.isOpaque = true
        let ruleColor = UIColor(white: 0.86, alpha: 1)
        homeTopRule.backgroundColor = ruleColor
        homeBottomRule.backgroundColor = UIColor.clear
        homeTopRule.isUserInteractionEnabled = false
        homeBottomRule.isUserInteractionEnabled = false
        addSubview(homeTopRule)
        addSubview(homeBottomRule)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if compactHomeStories {

            homeTopRule.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 0.5)
            homeBottomRule.frame = CGRect(x: 0, y: bounds.height,
                                          width: bounds.width, height: 0)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
        scroller.backgroundColor = UIColor.clear
        scroller.frame = bounds
        scroller.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = true
        addSubview(scroller)
    }
    required init?(coder: NSCoder) { return nil }
    func show(_ reels: [MagnistraStoryReel]) {
        entries = reels
        for child in scroller.subviews { child.removeFromSuperview() }
        let step: CGFloat = compactHomeStories ? 80 : 77
        for (index, reel) in reels.enumerated() {
            let bubbleFrame = compactHomeStories
                ? CGRect(x: CGFloat(index) * step + 6, y: 6, width: 72, height: 82)
                : CGRect(x: CGFloat(index) * step + 4, y: 6, width: 72, height: 86)
            let bubble = MagnistraStoryRing(reel: reel, frame: bubbleFrame,
                                            homeModuleStyle: compactHomeStories)
            bubble.onOpen = { [weak self] item in self?.onOpen?(item) }
            scroller.addSubview(bubble)
        }
        scroller.contentSize = CGSize(width: CGFloat(reels.count) * step + 8,
                                      height: bounds.height)
    }
}

final class MagnistraStoryViewer: UIViewController, UIGestureRecognizerDelegate {
    private var reel: MagnistraStoryReel
    private let siblings: [MagnistraStoryReel]
    private var siblingIndex: Int = 0
    private let storyContentView = UIView()
    private let imageView = UIImageView()
    private let videoSurface = UIView()
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let progressHost = UIView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let queue = OperationQueue()
    private var slides: [MagnistraStorySlide] = []
    private var index = 0
    private var elapsed: Double = 0
    private var timer: Timer?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var observedItem: AVPlayerItem?
    private var isHeld = false
    private var acknowledgedStoryIDs = Set<String>()
    private var generation = 0
    private var isLoading = false
    private var wasStatusBarHidden = false
    private var statusBarSnapshotCaptured = false

    private let deferStatusBarUntilPresented: Bool
    private var presentationCompleted = false
    private var correctingLegacyStoryFrame = false

    private struct NeighborPreview {
        let slides: [MagnistraStorySlide]
        let firstImage: UIImage?
    }
    private let neighborQueue = OperationQueue()

    private var neighborCache: [String: NeighborPreview] = [:]
    private var neighborInFlight = Set<String>()

    private var neighborAttempted = Set<String>()
    private var storyCubeIncomingView: UIView?
    private var storyCubeOriginalClips = false
    private var storyCubeTargetIndex: Int?
    private var storyCubeDirection: CGFloat = 0
    private var storyCubeProgress: CGFloat = 0
    private var storyCubeAnimating = false
    private var storyCubeSettled = false
    private var cubeDisplayLink: CADisplayLink?
    private var cubeSettleStart: CFTimeInterval = 0
    private var cubeSettleDuration: CFTimeInterval = 0.2
    private var cubeSettleFrom: CGFloat = 0
    private var cubeSettleTo: CGFloat = 0
    private var cubeSettleAdvance = false

    init(reel: MagnistraStoryReel, siblings: [MagnistraStoryReel] = [],
         deferStatusBarUntilPresented: Bool = false) {
        self.deferStatusBarUntilPresented = deferStatusBarUntilPresented
        self.reel = reel

        let valid = siblings.isEmpty ? [reel] : siblings
        self.siblings = valid
        self.siblingIndex = valid.firstIndex(where: { $0.id == reel.id }) ?? 0
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen

        queue.maxConcurrentOperationCount = 3
        neighborQueue.maxConcurrentOperationCount = 2
    }
    required init?(coder: NSCoder) { return nil }
    override var prefersStatusBarHidden: Bool {

        return !deferStatusBarUntilPresented || presentationCompleted
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !statusBarSnapshotCaptured {
            wasStatusBarHidden = UIApplication.shared.isStatusBarHidden
            statusBarSnapshotCaptured = true
        }
        if !deferStatusBarUntilPresented {
            UIApplication.shared.setStatusBarHidden(true, with: .none)
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard deferStatusBarUntilPresented else { return }

        presentationCompleted = true
        UIApplication.shared.setStatusBarHidden(true, with: .none)
        if (UIDevice.current.systemVersion as NSString).integerValue >= 7 {
            setNeedsStatusBarAppearanceUpdate()
        } else {

            magnistraAlignPresentedStoryToScreen()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }
    private func magnistraAlignPresentedStoryToScreen() {
        guard deferStatusBarUntilPresented && presentationCompleted &&
              (UIDevice.current.systemVersion as NSString).integerValue < 7 &&
              UIApplication.shared.isStatusBarHidden &&
              !correctingLegacyStoryFrame,
              let parent = view.superview, let window = view.window else { return }

        let target = parent.convert(window.bounds, from: window)
        if view.frame != target {
            correctingLegacyStoryFrame = true
            view.frame = target
            correctingLegacyStoryFrame = false
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        storyContentView.frame = view.bounds
        storyContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        storyContentView.backgroundColor = UIColor.black
        storyContentView.isOpaque = true
        view.addSubview(storyContentView)
        imageView.backgroundColor = UIColor.black
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = view.bounds
        storyContentView.addSubview(imageView)
        videoSurface.frame = view.bounds
        videoSurface.backgroundColor = UIColor.clear
        videoSurface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        storyContentView.addSubview(videoSurface)
        progressHost.backgroundColor = UIColor.clear
        progressHost.isOpaque = false
        storyContentView.addSubview(progressHost)
        avatar.frame = CGRect(x: 14, y: 21, width: 27, height: 27)
        avatar.layer.cornerRadius = 13.5
        avatar.clipsToBounds = true
        avatar.backgroundColor = UIColor.darkGray
        storyContentView.addSubview(avatar)
        nameLabel.frame = CGRect(x: 48, y: 21, width: max(100, view.bounds.width - 61), height: 27)
        nameLabel.backgroundColor = UIColor.clear
        nameLabel.isOpaque = false
        nameLabel.textColor = UIColor.white
        nameLabel.font = UIFont.boldSystemFont(ofSize: 13)
        nameLabel.text = reel.title
        storyContentView.addSubview(nameLabel)
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin,
                                    .flexibleLeftMargin, .flexibleRightMargin]
        storyContentView.addSubview(spinner)
        spinner.startAnimating()
        let tap = UITapGestureRecognizer(target: self, action: #selector(screenTapped(_:)))
        view.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(screenHeld(_:)))
        hold.minimumPressDuration = 0.18
        view.addGestureRecognizer(hold)
        tap.require(toFail: hold)
        let swipeDown = UISwipeGestureRecognizer(target: self,
                                                 action: #selector(swipeDownToClose(_:)))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)
        let sidePan = UIPanGestureRecognizer(target: self,
                                             action: #selector(panAcrossReels(_:)))
        sidePan.minimumNumberOfTouches = 1
        sidePan.maximumNumberOfTouches = 1
        sidePan.delegate = self
        view.addGestureRecognizer(sidePan)
        tap.require(toFail: swipeDown)
        tap.require(toFail: sidePan)
        loadReel(reel, siblingIndex: siblingIndex)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        magnistraAlignPresentedStoryToScreen()
        storyContentView.frame = view.bounds
        imageView.frame = storyContentView.bounds
        videoSurface.frame = storyContentView.bounds
        playerLayer?.frame = videoSurface.bounds
        progressHost.frame = CGRect(x: 9, y: 6, width: max(10, view.bounds.width - 18), height: 4)
        layoutProgress()
    }
    private func loadReel(_ nextReel: MagnistraStoryReel, siblingIndex nextIndex: Int) {

        let hadSlides = !slides.isEmpty
        isLoading = true
        reel = nextReel
        siblingIndex = nextIndex
        generation += 1
        let token = generation
        timer?.invalidate()
        timer = nil
        player?.pause()

        if !storyCubeAnimating { spinner.startAnimating() }
        let key = neighborKey(for: nextReel)
        if let prepared = neighborCache[key], !prepared.slides.isEmpty {
            acceptReel(nextReel, nextIndex, prepared.slides, hadSlides, token)
            return
        }
        queue.addOperation { [weak self] in
            let loaded = (try? MagnistraHomeService.loadStorySlides(reelID: nextReel.id,
                                                                  highlight: nextReel.highlight)) ?? []
            OperationQueue.main.addOperation { [weak self] in
                self?.acceptReel(nextReel, nextIndex, loaded, hadSlides, token)
            }
        }
    }
    private func acceptReel(_ nextReel: MagnistraStoryReel, _ nextIndex: Int,
                            _ loaded: [MagnistraStorySlide], _ hadSlides: Bool, _ token: Int) {
        guard generation == token else { return }
        isLoading = false
        spinner.stopAnimating()
        guard !loaded.isEmpty else {
            discardStoryCube()

            if !hadSlides && siblings.count <= 1 { closeTapped() }
            else if hadSlides {
                if !isHeld { player?.play() }
                startTimer()
            } else {
                imageView.image = nil
                nameLabel.text = nextReel.title
            }
            return
        }
        cancelMedia()
        reel = nextReel
        siblingIndex = nextIndex
        slides = loaded
        index = 0
        isHeld = false
        nameLabel.text = nextReel.title
        avatar.image = nil
        presentSlide()

        prefetchAdjacentReels()
        let url = nextReel.avatarURL
        if !url.isEmpty {
            let avatarToken = generation
            MagnistraStoryImageQueue.shared.addOperation { [weak self] in
                let img = MagnistraHomeService.loadProfileAvatar(primaryURL: url, fallbackURL: nil)
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, self.generation == avatarToken else { return }
                    self.avatar.image = img
                }
            }
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard !storyCubeAnimating, siblings.count > 1 else { return false }
        let v = pan.velocity(in: view)
        guard abs(v.x) > abs(v.y) * 1.2 else { return false }
        return v.x < 0 ? siblingIndex + 1 < siblings.count : siblingIndex > 0
    }
    @objc private func panAcrossReels(_ gesture: UIPanGestureRecognizer) {
        let dx = gesture.translation(in: view).x
        let startingMotion = abs(dx) > 2 ? dx : gesture.velocity(in: view).x
        switch gesture.state {
        case .began:
            beginStoryCube(direction: startingMotion < 0 ? 1 : -1)
            updateStoryCube(with: dx)
        case .changed:
            if storyCubeIncomingView == nil { beginStoryCube(direction: startingMotion < 0 ? 1 : -1) }
            updateStoryCube(with: dx)
        case .ended:
            guard storyCubeIncomingView != nil else { return }
            let speed = gesture.velocity(in: view).x
            let advance = storyCubeProgress > 0.42 ||
                (storyCubeDirection > 0 ? speed < -420 : speed > 420)
            settleStoryCube(advance: advance)
        case .cancelled, .failed:
            if storyCubeIncomingView != nil { settleStoryCube(advance: false) }
        default: break
        }
    }
    private func neighborKey(for next: MagnistraStoryReel) -> String {
        return (next.highlight ? "highlight:" : "story:") + next.id
    }
    private func prefetchAdjacentReels() {
        guard !isLoading, !slides.isEmpty, view.window != nil else { return }
        let choices = [siblingIndex + 1, siblingIndex - 1].filter {
            $0 >= 0 && $0 < siblings.count
        }
        let wanted = Set(choices.map { neighborKey(for: siblings[$0]) })
        neighborCache = neighborCache.filter { wanted.contains($0.key) }
        for pos in choices {
            let item = siblings[pos]
            let key = neighborKey(for: item)
            guard neighborCache[key] == nil, !neighborInFlight.contains(key),
                  !neighborAttempted.contains(key) else { continue }
            neighborAttempted.insert(key)
            neighborInFlight.insert(key)
            neighborQueue.addOperation { [weak self] in

                let loaded = (try? MagnistraHomeService.loadStorySlides(reelID: item.id,
                                                                      highlight: item.highlight)) ?? []
                let image: UIImage?
                if let first = loaded.first, !first.imageURL.isEmpty,
                   let original = MagnistraHomeService.loadProfileAvatar(primaryURL: first.imageURL,
                                                                        fallbackURL: nil) {

                    let size = CGSize(width: 320, height: 480)
                    UIGraphicsBeginImageContextWithOptions(size, true, 2.0)
                    UIColor.black.setFill()
                    UIRectFill(CGRect(origin: .zero, size: size))
                    let ratio = min(size.width / max(1, original.size.width),
                                    size.height / max(1, original.size.height))
                    let scaled = CGSize(width: original.size.width * ratio,
                                        height: original.size.height * ratio)
                    original.draw(in: CGRect(x: (size.width - scaled.width) / 2,
                                             y: (size.height - scaled.height) / 2,
                                             width: scaled.width, height: scaled.height))
                    image = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                } else { image = nil }
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.neighborInFlight.remove(key)
                    guard !loaded.isEmpty else { return }
                    let stillAdjacent = abs(self.siblingIndex - pos) <= 1
                    if stillAdjacent {
                        self.neighborCache[key] = NeighborPreview(slides: loaded,
                                                                  firstImage: image)
                        if self.storyCubeTargetIndex == pos,
                           let face = self.storyCubeIncomingView,
                           let imageView = face.viewWithTag(6161) as? UIImageView {
                            imageView.image = image
                        }
                    }
                }
            }
        }
    }

    private func makeNeighborFace(at pos: Int) -> UIView? {
        guard pos >= 0 && pos < siblings.count else { return nil }
        let target = siblings[pos]
        let size = view.bounds.size
        guard size.width > 0 && size.height > 0 else { return nil }
        let preview = neighborCache[neighborKey(for: target)]
        let face = UIView(frame: CGRect(origin: .zero, size: size))
        face.backgroundColor = .black
        face.isOpaque = true
        face.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let picture = UIImageView(frame: face.bounds)
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        picture.backgroundColor = .black
        picture.contentMode = .scaleAspectFit
        picture.tag = 6161
        picture.image = preview?.firstImage
        face.addSubview(picture)
        let count = max(1, preview?.slides.count ?? 1)
        let gap: CGFloat = 3
        let barWidth = max(1, (size.width - 18 - CGFloat(count - 1) * gap) / CGFloat(count))
        for n in 0..<count {
            let bar = UIView(frame: CGRect(x: 9 + CGFloat(n) * (barWidth + gap),
                                           y: 6, width: barWidth, height: 3))
            bar.backgroundColor = UIColor(white: 1, alpha: 0.4)
            face.addSubview(bar)
        }
        let circle = UIImageView(frame: CGRect(x: 14, y: 21, width: 27, height: 27))
        circle.backgroundColor = UIColor.darkGray
        circle.layer.cornerRadius = 13.5
        circle.clipsToBounds = true
        face.addSubview(circle)
        let handle = UILabel(frame: CGRect(x: 48, y: 21,
                                         width: max(100, size.width - 61), height: 27))
        handle.backgroundColor = .clear
        handle.textColor = .white
        handle.font = UIFont.boldSystemFont(ofSize: 13)
        handle.text = preview?.slides.first?.username ?? target.title
        face.addSubview(handle)
        return face
    }
    private func beginStoryCube(direction: CGFloat) {
        guard !storyCubeAnimating,
              storyCubeIncomingView == nil, view.bounds.width > 0 else { return }
        let target = siblingIndex + (direction > 0 ? 1 : -1)
        guard target >= 0, target < siblings.count,
              let neighbor = makeNeighborFace(at: target) else { return }
        timer?.invalidate()
        timer = nil
        player?.pause()
        storyCubeDirection = direction
        storyCubeTargetIndex = target
        storyCubeProgress = 0
        storyCubeSettled = false
        storyCubeOriginalClips = view.layer.masksToBounds
        view.layer.masksToBounds = true
        storyContentView.layer.isDoubleSided = false
        neighbor.layer.isDoubleSided = false

        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 850.0
        view.layer.sublayerTransform = perspective
        view.addSubview(neighbor)
        storyCubeIncomingView = neighbor
        updateStoryCubeFaces(0)
    }
    private func updateStoryCube(with dx: CGFloat) {
        guard storyCubeIncomingView != nil else { return }
        let directed = dx * (storyCubeDirection > 0 ? -1 : 1)
        let progress = min(1, max(0, directed / max(1, view.bounds.width)))
        updateStoryCubeFaces(progress)
    }

    private func storyQuarterTurn(_ progress: CGFloat) -> (sine: CGFloat, cosine: CGFloat) {
        let x: CGFloat = min(1, max(0, progress)) * 1.5707963267948966
        let t = x * x

        var s: CGFloat = 0.00000000016059043836821615
        s = -0.00000002505210838544172 + t * s
        s = 0.0000027557319223985893 + t * s
        s = -0.0001984126984126984 + t * s
        s = 0.008333333333333333 + t * s
        s = -0.16666666666666666 + t * s
        let sine = x * (1 + t * s)
        var c: CGFloat = -0.000000000011470745597729725
        c = 0.00000000208767569878681 + t * c
        c = -0.0000002755731922398589 + t * c
        c = 0.0000248015873015873 + t * c
        c = -0.001388888888888889 + t * c
        c = 0.041666666666666664 + t * c
        c = -0.5 + t * c
        let cosine = 1 + t * c
        return (sine, cosine)
    }
    private func storyRotationY(cosine: CGFloat, sine: CGFloat) -> CATransform3D {
        var rotation = CATransform3DIdentity
        rotation.m11 = cosine
        rotation.m13 = -sine
        rotation.m31 = sine
        rotation.m33 = cosine
        return rotation
    }
    private func updateStoryCubeFaces(_ progress: CGFloat) {
        guard let incoming = storyCubeIncomingView else { return }
        storyCubeProgress = progress
        let values = storyQuarterTurn(progress)
        let side: CGFloat = storyCubeDirection > 0 ? 1 : -1
        let signedSine = -side * values.sine
        let cosine = values.cosine
        let depth = view.bounds.width / 2

        var current = storyRotationY(cosine: cosine, sine: signedSine)
        current.m41 = depth * signedSine
        current.m43 = depth * (cosine - 1)

        var next = storyRotationY(cosine: -side * signedSine,
                                  sine: side * cosine)
        next.m41 = side * depth * cosine
        next.m43 = -side * depth * signedSine - depth
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        storyContentView.layer.transform = current
        incoming.layer.transform = next
        CATransaction.commit()
    }
    private func settleStoryCube(advance: Bool) {
        guard storyCubeIncomingView != nil, !storyCubeAnimating else { return }
        storyCubeAnimating = true
        cubeSettleFrom = storyCubeProgress
        cubeSettleTo = advance ? 1 : 0
        cubeSettleAdvance = advance

        cubeSettleDuration = 0.14 + 0.14 * Double(abs(cubeSettleTo - cubeSettleFrom))
        cubeSettleStart = CACurrentMediaTime()
        cubeDisplayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(animateStoryCubeStep(_:)))
        cubeDisplayLink = link
        link.add(to: RunLoop.main, forMode: .common)
    }
    @objc private func animateStoryCubeStep(_ link: CADisplayLink) {
        let elapsed = min(1.0, (CACurrentMediaTime() - cubeSettleStart) / cubeSettleDuration)
        let eased = elapsed * elapsed * (3 - 2 * elapsed)
        updateStoryCubeFaces(cubeSettleFrom + (cubeSettleTo - cubeSettleFrom) * CGFloat(eased))
        if elapsed >= 1 {
            link.invalidate()
            cubeDisplayLink = nil
            if cubeSettleAdvance, let target = storyCubeTargetIndex {

                showPendingNeighbor(at: target)
            } else {
                discardStoryCube()
                if !isHeld { player?.play() }
                startTimer()
            }
        }
    }
    private func showPendingNeighbor(at target: Int) {
        guard target >= 0 && target < siblings.count else {
            discardStoryCube()
            return
        }
        let nextReel = siblings[target]
        let prepared = neighborCache[neighborKey(for: nextReel)]

        cancelMedia()
        timer?.invalidate()
        timer = nil
        slides = []
        index = 0
        elapsed = 0
        isHeld = false
        imageView.image = prepared?.firstImage
        avatar.image = nil
        nameLabel.text = nextReel.title
        for child in progressHost.subviews { child.removeFromSuperview() }
        discardStoryCube()
        loadReel(nextReel, siblingIndex: target)
    }
    private func completeStoryCubeWhenMediaReady() {
        guard storyCubeIncomingView != nil else { return }
        if storyCubeSettled { discardStoryCube() }
    }
    private func discardStoryCube() {
        cubeDisplayLink?.invalidate()
        cubeDisplayLink = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        storyContentView.layer.transform = CATransform3DIdentity
        storyCubeIncomingView?.layer.transform = CATransform3DIdentity
        view.layer.sublayerTransform = CATransform3DIdentity
        CATransaction.commit()
        storyCubeIncomingView?.removeFromSuperview()
        storyCubeIncomingView = nil
        view.layer.masksToBounds = storyCubeOriginalClips
        storyCubeTargetIndex = nil
        storyCubeDirection = 0
        storyCubeProgress = 0
        storyCubeAnimating = false
        storyCubeSettled = false
    }
    private func layoutProgress() {
        for child in progressHost.subviews { child.removeFromSuperview() }
        let count = max(1, slides.count)
        let gap: CGFloat = 3
        let segment = max(1, (progressHost.bounds.width - CGFloat(count - 1) * gap) / CGFloat(count))
        for pos in 0..<count {
            let background = UIView(frame: CGRect(x: CGFloat(pos) * (segment + gap), y: 0,
                                                 width: segment, height: 3))
            background.backgroundColor = UIColor(white: 1, alpha: 0.40)
            background.isOpaque = false
            let fill = UIView(frame: CGRect(x: 0, y: 0,
                            width: segment * CGFloat(pos < index ? 1.0 : (pos == index ? min(1, elapsed / 5.0) : 0.0)),
                            height: 3))
            fill.tag = 4000 + pos
            fill.backgroundColor = UIColor.white
            fill.isOpaque = false
            background.addSubview(fill)
            progressHost.addSubview(background)
        }
    }
    private func cancelMedia() {
        timer?.invalidate()
        timer = nil
        if let item = observedItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime,
                                                      object: item)
        }
        observedItem = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        videoSurface.isHidden = true
    }
    private func acknowledgeCurrentStory(_ item: MagnistraStorySlide) {
        guard !reel.highlight && !reel.id.hasPrefix("archiveDay:"),
              !item.mediaPK.isEmpty, !item.ownerID.isEmpty else { return }
        let id = item.mediaPK + ":" + item.ownerID
        guard !acknowledgedStoryIDs.contains(id) else { return }
        acknowledgedStoryIDs.insert(id)
        let reelID = reel.id
        queue.addOperation {
            do {
                try MagnistraHomeService.acknowledgeStoryView(
                    reelID: reelID, mediaPK: item.mediaPK,
                    ownerID: item.ownerID, timestamp: item.timestamp)
                print("MAGNISTRA_STORY_SEEN=REQUEST_OK")
            } catch {

                print("MAGNISTRA_STORY_SEEN=NOT_CONFIRMED")
            }
        }
    }

    private func presentSlide() {
        guard index >= 0 && index < slides.count else { closeTapped(); return }
        cancelMedia()
        generation += 1
        let token = generation
        let item = slides[index]
        elapsed = 0
        imageView.image = nil
        spinner.startAnimating()
        layoutProgress()
        nameLabel.text = item.username.isEmpty ? reel.title : item.username
        let cacheImage = index == 0 ? neighborCache[neighborKey(for: reel)]?.firstImage : nil
        if let ready = cacheImage {
            imageView.image = ready
            if item.videoURL.isEmpty { acknowledgeCurrentStory(item) }
            spinner.stopAnimating()
            completeStoryCubeWhenMediaReady()
            prefetchAdjacentReels()
            if item.videoURL.isEmpty { startTimer() }
        } else if !item.imageURL.isEmpty {
            queue.addOperation { [weak self] in
                let image = MagnistraHomeService.loadProfileAvatar(primaryURL: item.imageURL, fallbackURL: nil)
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, token == self.generation else { return }
                    self.imageView.image = image
                    if image != nil && item.videoURL.isEmpty {
                        self.acknowledgeCurrentStory(item)
                    }
                    self.spinner.stopAnimating()
                    self.completeStoryCubeWhenMediaReady()
                    self.prefetchAdjacentReels()
                    if item.videoURL.isEmpty { self.startTimer() }
                }
            }
        } else {
            spinner.stopAnimating()
            if item.videoURL.isEmpty { completeStoryCubeWhenMediaReady() }
            prefetchAdjacentReels()
        }
        if !item.videoURL.isEmpty {
            queue.addOperation { [weak self] in
                let remote = try? MagnistraHomeService.storyVideoLocalURL(item.videoURL)
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, token == self.generation else { return }
                    if let url = remote {
                        self.videoSurface.isHidden = false
                        let player = AVPlayer(url: url)
                        let layer = AVPlayerLayer(player: player)
                        layer.videoGravity = .resizeAspect
                        layer.frame = self.videoSurface.bounds
                        self.videoSurface.layer.addSublayer(layer)
                        self.player = player
                        self.playerLayer = layer
                        if let item = player.currentItem {
                            self.observedItem = item
                            NotificationCenter.default.addObserver(self,
                                selector: #selector(self.videoFinished(_:)),
                                name: .AVPlayerItemDidPlayToEndTime, object: item)
                        }
                        if !self.isHeld { player.play() }
                        self.acknowledgeCurrentStory(item)
                        self.spinner.stopAnimating()
                        self.completeStoryCubeWhenMediaReady()
                        self.prefetchAdjacentReels()
                        self.startTimer()
                    } else {
                        self.spinner.stopAnimating()
                        self.completeStoryCubeWhenMediaReady()
                        self.startTimer()
                    }
                }
            }
        }
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.08, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
    }
    @objc private func tick() {
        if isHeld || isLoading { return }
        let duration: Double
        if let movie = player, let item = movie.currentItem {
            let d = CMTimeGetSeconds(item.duration)
            duration = d.isFinite && d > 0 ? d : 5.0
            let current = CMTimeGetSeconds(movie.currentTime())
            elapsed = current.isFinite ? max(0, current) : 0
        } else {
            duration = 5.0
            elapsed += 0.08
        }
        for (position, segment) in progressHost.subviews.enumerated() {
            if let fill = segment.viewWithTag(4000 + position) {
                var f = fill.frame
                f.size.width = segment.bounds.width * CGFloat(position < index ? 1.0 :
                    (position == index ? min(1, elapsed / duration) : 0.0))
                fill.frame = f
            }
        }
        if player == nil && elapsed >= duration { advance(1) }
    }
    @objc private func videoFinished(_ notification: Notification) { advance(1) }
    private func advance(_ amount: Int) {
        if isLoading || storyCubeAnimating || storyCubeIncomingView != nil { return }
        let next = index + amount
        if next < 0 { index = 0 }
        else if next >= slides.count {

            if amount > 0 && siblingIndex + 1 < siblings.count {
                beginStoryCube(direction: 1)
                if storyCubeIncomingView != nil {
                    settleStoryCube(advance: true)
                    return
                }
            }

            closeTapped()
            return
        } else { index = next }
        presentSlide()
    }
    @objc private func screenTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !storyCubeAnimating else { return }
        let point = recognizer.location(in: view)
        let direction = point.x < view.bounds.width * 0.5 ? -1 : 1
        if isLoading || slides.isEmpty {

            let target = siblingIndex + direction
            if target >= 0 && target < siblings.count {
                cancelMedia()
                slides = []
                index = 0
                imageView.image = nil
                loadReel(siblings[target], siblingIndex: target)
            }
            return
        }
        advance(direction)
    }
    @objc private func screenHeld(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: isHeld = true; player?.pause()
        case .ended, .cancelled, .failed: isHeld = false; player?.play()
        default: break
        }
    }
    @objc private func swipeDownToClose(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        closeTapped()
    }
    @objc private func closeTapped() {
        discardStoryCube()
        isHeld = false
        generation += 1
        cancelMedia()
        dismiss(animated: true, completion: nil)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        generation += 1
        discardStoryCube()
        neighborQueue.cancelAllOperations()
        cancelMedia()
        if statusBarSnapshotCaptured {
            UIApplication.shared.setStatusBarHidden(wasStatusBarHidden, with: .none)
            statusBarSnapshotCaptured = false
        }
    }
    deinit { cancelMedia() }
}

