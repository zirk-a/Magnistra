// Overview: Explore tab main view controller and its header scroll behavior.
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

final class MagnistraRootTabHeaderScrollBehavior: NSObject {

    private weak var navigation: UINavigationController?
    private weak var table: UIScrollView?
    private weak var owner: UIView?
    private weak var stickySearchHost: UIView?
    var managesViewport: Bool { return active }

    func attachStickySearchHost(_ host: UIView) {
        stickySearchHost = host
        hiddenHitArea.interactiveSearchHost = host
    }

    func revealForTabReturn() {
        guard active else { return }
        hidden = 0.0
        previousOffset = table?.contentOffset.y
        displayHeader()
    }

    private var originalFrame: CGRect?
    private var oldInset: UIEdgeInsets?
    private var oldAutoresizing: UIView.AutoresizingMask = []
    private var oldOwnerClips = true
    private var oldNavigationClips = true
    private var oldNavigationColor: UIColor?
    private var oldTableClips = true
    private var height: CGFloat = 44.0
    private var hidden: CGFloat = 0.0
    private var previousOffset: CGFloat?

    private var previousBarMask: CALayer?
    private let barVisibleMask = CAShapeLayer()
    private let hiddenHitArea = MagnistraHiddenHeaderHitArea()
    private var active = false

    private func layoutTable() {
        guard active, let table = table, let owner = owner else { return }
        let bounds = owner.bounds
        let originalY = originalFrame?.origin.y ?? 0.0
        let rect = CGRect(x: 0.0, y: originalY - height,
                          width: bounds.width,
                          height: bounds.height - originalY + height)
        if table.frame != rect { table.frame = rect }
    }

    private func magnistraFadeNativeButtons(in view: UIView,
                                             opacity: CGFloat,
                                             depth: Int) {
        if depth <= 0 { return }
        for child in view.subviews {
            if child is UIControl {
                child.alpha = opacity
            } else if !(child is UIImageView) {
                magnistraFadeNativeButtons(in: child,
                                           opacity: opacity,
                                           depth: depth - 1)
            }
        }
    }

    private func magnistraApplyHeaderContentOpacity(_ opacity: CGFloat) {
        guard let bar = navigation?.navigationBar else { return }
        let value = max(0.0, min(1.0, opacity))
        bar.topItem?.titleView?.alpha = value
        bar.topItem?.leftBarButtonItem?.customView?.alpha = value
        bar.topItem?.rightBarButtonItem?.customView?.alpha = value

        magnistraFadeNativeButtons(in: bar, opacity: value, depth: 5)
    }

    private func displayHeader() {
        guard active, let bar = navigation?.navigationBar else { return }
        hidden = min(height, max(0.0, hidden))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.transform = CGAffineTransform(translationX: 0.0, y: -hidden)
        stickySearchHost?.transform = CGAffineTransform(
            translationX: 0.0, y: -hidden)

        stickySearchHost?.isUserInteractionEnabled = true
        CATransaction.commit()

        let statusBottom = UIApplication.shared.statusBarFrame.maxY
        let barTop = bar.window.map {
            bar.convert(CGPoint.zero, to: $0).y
        } ?? (statusBottom - hidden)
        let cropTop = min(bar.bounds.height,
                          max(0.0, statusBottom - barTop))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barVisibleMask.frame = bar.bounds
        barVisibleMask.path = UIBezierPath(rect: CGRect(
            x: 0.0, y: cropTop, width: bar.bounds.width,
            height: max(0.0, bar.bounds.height - cropTop))).cgPath
        CATransaction.commit()
        magnistraApplyHeaderContentOpacity(1.0 - hidden / 22.0)

        bar.isUserInteractionEnabled = hidden < height - 1.0
        let fullyHidden = hidden >= height - 1.0
        hiddenHitArea.isHidden = !fullyHidden
        if fullyHidden, let nav = navigation, let window = nav.view.window {
            let top = nav.view.convert(CGPoint(x: 0.0, y: statusBottom), from: window).y
            hiddenHitArea.frame = CGRect(x: 0.0, y: top,
                width: nav.view.bounds.width, height: height)
            nav.view.bringSubviewToFront(hiddenHitArea)
        }
    }

    func activate(_ feed: UIScrollView,
                  navigationController nav: UINavigationController?) {
        guard !active, let nav = nav, let ownerView = feed.superview else { return }
        navigation = nav
        table = feed
        owner = ownerView
        height = max(1.0, nav.navigationBar.bounds.height)
        originalFrame = feed.frame
        oldInset = feed.contentInset
        oldAutoresizing = feed.autoresizingMask
        oldTableClips = feed.clipsToBounds
        oldOwnerClips = ownerView.clipsToBounds
        oldNavigationClips = nav.view.clipsToBounds
        oldNavigationColor = nav.view.backgroundColor
        previousBarMask = nav.navigationBar.layer.mask
        barVisibleMask.fillColor = UIColor.black.cgColor
        nav.navigationBar.layer.mask = barVisibleMask
        hiddenHitArea.scrollTarget = feed
        hiddenHitArea.backgroundColor = UIColor.clear
        hiddenHitArea.isHidden = true
        hiddenHitArea.isUserInteractionEnabled = true
        nav.view.addSubview(hiddenHitArea)
        hidden = 0.0
        previousOffset = nil
        nav.setNavigationBarHidden(false, animated: false)
        nav.navigationBar.transform = .identity

        active = true
        let previousY = feed.contentOffset.y
        feed.autoresizingMask = []
        feed.clipsToBounds = true
        ownerView.clipsToBounds = false
        nav.view.clipsToBounds = true

        nav.view.backgroundColor = ownerView.backgroundColor ?? UIColor.white
        var newInset = feed.contentInset
        newInset.top += height
        feed.contentInset = newInset
        layoutTable()
        feed.contentOffset = CGPoint(x: feed.contentOffset.x,
                                     y: previousY - height)
        previousOffset = feed.contentOffset.y

        if nav.navigationBar.superview === nav.view {
            nav.view.bringSubviewToFront(nav.navigationBar)
        }
        displayHeader()
    }

    func restoreViewportAfterOwnerLayout() {
        layoutTable()
    }

    func deactivate() {
        guard active else { return }
        active = false
        navigation?.navigationBar.transform = .identity
        navigation?.navigationBar.isUserInteractionEnabled = true
        hiddenHitArea.removeFromSuperview()
        hiddenHitArea.scrollTarget = nil
        magnistraApplyHeaderContentOpacity(1.0)
        navigation?.navigationBar.layer.mask = previousBarMask
        stickySearchHost?.transform = .identity
        stickySearchHost?.isUserInteractionEnabled = true
        stickySearchHost = nil
        hiddenHitArea.interactiveSearchHost = nil
        previousBarMask = nil
        navigation?.view.clipsToBounds = oldNavigationClips
        navigation?.view.backgroundColor = oldNavigationColor
        if let feed = table {
            let oldY = feed.contentOffset.y
            if let inset = oldInset { feed.contentInset = inset }
            if let original = originalFrame { feed.frame = original }
            feed.autoresizingMask = oldAutoresizing
            feed.clipsToBounds = oldTableClips
            feed.contentOffset = CGPoint(x: feed.contentOffset.x,
                                         y: oldY + height)
        }
        owner?.clipsToBounds = oldOwnerClips
        table = nil
        owner = nil
        navigation = nil
        oldInset = nil
        originalFrame = nil
        previousOffset = nil
        hidden = 0.0
    }

    func observe(_ scrollView: UIScrollView, initialContentReady: Bool) {
        guard active, let feed = table, scrollView === feed else { return }
        let y = feed.contentOffset.y

        guard initialContentReady else {

            previousOffset = y
            return
        }
        guard feed.isDragging || feed.isDecelerating else {
            previousOffset = y
            return
        }
        guard let previous = previousOffset else {
            previousOffset = y
            return
        }
        previousOffset = y
        let delta = y - previous
        guard abs(delta) > 0.001 && abs(delta) < 120.0 else { return }
        let oldHidden = hidden
        if y <= -feed.contentInset.top + 0.5 {
            hidden = 0.0
        } else {
            hidden = min(height, max(0.0, hidden + delta))
        }
        if abs(hidden - oldHidden) > 0.001 { displayHeader() }
    }
}
final class ExploreViewController:
    UIViewController,
    UIScrollViewDelegate,
    UISearchBarDelegate
{

    var magnistraSerial = 0
    var magnistraPreviewApplied = -1

    var magnistraViewportQueuedMediaIDs = Set<String>()
    var magnistraThumbnailRetryCount: [String: Int] = [:]
    var magnistraThumbnailRetryNotBefore: [String: Double] = [:]

    var exploreRequestStartedAtEpoch: Double = 0.0

    var magnistraSavedGrid = false

    var magnistraSavedOpenPending = false
    let pullRefreshGesture = MagnistraPullRefreshGesture()
    let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    var preservingGridDuringPullRefresh = false

    let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)

    let rootTabHeaderScroll = MagnistraRootTabHeaderScrollBehavior()

    let searchBarHost = UIView()
    let searchBar =
        UISearchBar()

    let searchModeButton =
        UIButton(
            type:
                .custom
        )

    var searchModeIsTag =
        true

    let ios7CancelButton = UIButton(type: .custom)

    let ios7SearchPlaceholder = UILabel()

    let ios7ClearButton = UIButton(type: .custom)
    let ios7SearchSpacer = UIView(frame: CGRect(x: 0.0, y: 0.0,
                                                       width: 28.0, height: 28.0))

    let ios8PlusIdlePlaceholder = UILabel()

    var ios8PlusSearchEditing = false
    var usesIOS8PlusFixedSearch: Bool {
        return (UIDevice.current.systemVersion as NSString).integerValue >= 8
    }
    var ios7SearchEditing = false

    var ios7QueryText = ""
    var usesIOS7SearchControls: Bool {
        return UIDevice.current.systemVersion.hasPrefix("7.")
    }

    let scrollView =
        UIScrollView()

    let statusLabel =
        UILabel()

    let paginationLabel =
        UILabel()

    let paginationOverscrollFill =
        UIView()

    let loadQueue =
        OperationQueue()

    let imageQueue =
        OperationQueue()

    var posts:
        [MagnistraRealPost] = []

    var tiles:
        [MagnistraExploreTile] = []

    var placeholderViews:
        [UIView] = []

    var seenMediaIDs =
        Set<String>()

    var nextMaxID:
        String? =
            nil

    var deferredExplorePosts: [MagnistraRealPost] = []
    var deferredExploreNextMaxID: String? = nil

    var isLoadingPage =
        false

    var reachedEnd =
        false

    var contentGeneration =
        0

    let placeholderTagBase =
        88000

    var placeholderColorOrder:
        [Int] = []

    let placeholderColors:
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

        title = magnistraSavedGrid ? "Saved" : "Explore"

        if !magnistraSavedGrid {
            navigationItem.leftBarButtonItem = MagnistraProfileIcons.navbarItem(
                "ReelsWhite", title: "Reels", target: self,
                action: #selector(reelsTapped))
        }

        navigationItem.rightBarButtonItem = nil

        view.backgroundColor =
            instaLightGray()

        searchBar.placeholder =
            "Search tags"

        if (UIDevice.current.systemVersion as NSString).integerValue >= 7 {
            searchBar.searchBarStyle = .minimal
            searchBar.backgroundColor = instaLightGray()
            searchBar.tintColor = MagnistraPostCell.magnistraBlue
        }
        if usesIOS7SearchControls {

            searchBar.placeholder = ""
        } else if usesIOS8PlusFixedSearch {

            searchBar.placeholder = ""
        }

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

        searchBar.autoresizingMask = [
            .flexibleWidth
        ]

        searchBar.delegate =
            self

        searchBar.showsCancelButton =
            false

        searchBarHost.backgroundColor = instaLightGray()
        searchBarHost.clipsToBounds = true
        searchBarHost.autoresizingMask = [.flexibleWidth]
        searchBarHost.frame = CGRect(x: 0.0, y: 0.0,
                                     width: view.bounds.width, height: 44.0)
        view.addSubview(searchBarHost)
        searchBar.frame = searchBarHost.bounds
        searchBarHost.addSubview(searchBar)

        if usesIOS7SearchControls {
            ios7SearchSpacer.isUserInteractionEnabled = false
            ios7SearchPlaceholder.font = UIFont.systemFont(ofSize: 14.0)
            ios7SearchPlaceholder.textColor = UIColor(white: 0.60, alpha: 1.0)
            ios7SearchPlaceholder.textAlignment = .left
            ios7SearchPlaceholder.backgroundColor = UIColor.clear
            ios7SearchPlaceholder.isUserInteractionEnabled = false
            ios7SearchPlaceholder.text = "Search tags"

            searchBarHost.addSubview(ios7SearchPlaceholder)

            ios7ClearButton.setImage(makeIOS7ClearGlyph(), for: .normal)
            ios7ClearButton.backgroundColor = UIColor.clear
            ios7ClearButton.imageView?.contentMode = .center
            ios7ClearButton.addTarget(self,
                                      action: #selector(ios7ClearTapped(_:)),
                                      for: .touchUpInside)
            ios7ClearButton.isHidden = true
            searchBarHost.addSubview(ios7ClearButton)
            ios7CancelButton.setTitle("Cancel", for: .normal)
            ios7CancelButton.setTitleColor(MagnistraPostCell.magnistraBlue,
                                           for: .normal)
            ios7CancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0)
            ios7CancelButton.backgroundColor = UIColor.clear
            ios7CancelButton.addTarget(self,
                                      action: #selector(ios7CancelTapped(_:)),
                                      for: .touchUpInside)
            ios7CancelButton.isHidden = true
            searchBarHost.addSubview(ios7CancelButton)
        } else if usesIOS8PlusFixedSearch {
            ios8PlusIdlePlaceholder.font = UIFont.systemFont(ofSize: 14.0)
            ios8PlusIdlePlaceholder.textColor = UIColor(white: 0.60, alpha: 1.0)
            ios8PlusIdlePlaceholder.textAlignment = .left
            ios8PlusIdlePlaceholder.backgroundColor = UIColor.clear
            ios8PlusIdlePlaceholder.isUserInteractionEnabled = false
            ios8PlusIdlePlaceholder.text = "Search tags"
            searchBarHost.addSubview(ios8PlusIdlePlaceholder)
        }

        searchModeButton.backgroundColor =
            UIColor.clear

        searchModeButton.layer.borderWidth =
            0.0

        searchModeButton.layer.cornerRadius =
            0.0

        searchModeButton.frame =
            CGRect(
                x: 0.0,
                y: 0.0,
                width: 28.0,
                height: 28.0
            )

        installSearchModeButtonInField()
        layoutIOS7SearchControls()
        layoutIOS8PlusSearchControls()

        scrollView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        scrollView.alwaysBounceVertical =
            true

        scrollView.delegate =
            self
        if #available(iOS 7.0, *) {

            if scrollView.responds(to: NSSelectorFromString("setKeyboardDismissMode:")) {
                scrollView.keyboardDismissMode = .onDrag
            }
        }

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
        if magnistraSavedGrid {

            searchBarHost.isHidden = true
            MagnistraBottomLoading.show(on: view)
        }

        requestPage(
            maxID: nil,
            replacing: true
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if magnistraSavedGrid {
            magnistraSavedOpenPending = false
            return
        }
        if let nav = navigationController {

            let navRect = view.convert(searchBarHost.frame, to: nav.view)
            searchBarHost.removeFromSuperview()
            searchBarHost.transform = .identity
            searchBarHost.frame = navRect
            nav.view.addSubview(searchBarHost)
        }
        rootTabHeaderScroll.attachStickySearchHost(searchBarHost)
        rootTabHeaderScroll.activate(scrollView, navigationController: navigationController)

        if let nav = navigationController {
            nav.view.bringSubviewToFront(searchBarHost)
        }
        layoutIOS7SearchControls()
        layoutIOS8PlusSearchControls()
    }

    override func viewWillDisappear(_ animated: Bool) {
        if magnistraSavedGrid {
            super.viewWillDisappear(animated)
            return
        }

        if usesIOS7SearchControls {
            ios7SearchEditing = false
            searchBar.resignFirstResponder()
            searchTextField(in: searchBar)?.resignFirstResponder()
            layoutIOS7SearchControls()
        }
        rootTabHeaderScroll.deactivate()

        if searchBarHost.superview !== view {
            searchBarHost.removeFromSuperview()
            searchBarHost.transform = .identity
            searchBarHost.frame = CGRect(x: 0.0, y: 0.0,
                                         width: view.bounds.width, height: 44.0)
            view.addSubview(searchBarHost)
            view.bringSubviewToFront(searchBarHost)
        }
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)
        if magnistraSavedGrid {
            scrollView.frame = view.bounds
            statusLabel.frame = CGRect(x: 20.0, y: 35.0,
                width: max(1.0, view.bounds.width - 40.0), height: 50.0)
            layoutGrid()
            return
        }

        let width =
            view.bounds.size.width

        let contentY:
            CGFloat = 44.0

        if !rootTabHeaderScroll.managesViewport {
            scrollView.frame = CGRect(x: 0.0, y: contentY,
                                      width: width,
                                      height: max(1.0, view.bounds.height - contentY))
        }

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

        if !rootTabHeaderScroll.managesViewport {
            searchBarHost.frame = CGRect(x: 0.0, y: 0.0,
                                         width: view.bounds.width, height: 44.0)
            searchBar.frame = searchBarHost.bounds
        }

        if !rootTabHeaderScroll.managesViewport {
            installSearchModeButtonInField()
        }
        layoutIOS7SearchControls()
        layoutIOS8PlusSearchControls()
        rootTabHeaderScroll.restoreViewportAfterOwnerLayout()
        magnistraLoadNearViewportImages()
}
}

extension ExploreViewController {
    func magnistraV2ReloadAfterLogin() { refreshTapped() }
}
