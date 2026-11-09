// Overview: Root view controller: sets up the main tabs and handles status bar and fullscreen changes.
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

final class RootViewController:
    UITabBarController,
    UITabBarControllerDelegate
{
    private var magnistraIOS7StatusBackground: UIView? = nil
    private var nativePhotoPickerShowing = false

    func showExistingStatusAbovePhotoPicker(_ showing: Bool) {
        guard nativePhotoPickerShowing != showing else { return }
        nativePhotoPickerShowing = showing
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        if major == 5 || major == 6 {
            MagnistraLegacyClearStatusBarRenderer.shared
                .showRootStatusAbovePhotoPicker(showing, rootView: view)
            return
        }
        guard let window = view.window,
              let strip = magnistraIOS7StatusBackground else { return }
        let host: UIView = showing ? window : view
        if strip.superview !== host {
            strip.removeFromSuperview()
            host.addSubview(strip)
        }
        strip.frame = CGRect(x: 0.0, y: 0.0,
                            width: host.bounds.width, height: strip.bounds.height)
        host.bringSubviewToFront(strip)
    }

    private func magnistraSyncIOS6PlusStatusBackground() {
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        guard major >= 6 else { return }

        if major == 6 { return }

        guard let window = view.window else { return }
        let frame = UIApplication.shared.statusBarFrame
        let height = frame.height
        guard !UIApplication.shared.isStatusBarHidden,
              height >= 18.0 && height <= 24.0,
              window.bounds.width >= 240.0 else {
            magnistraIOS7StatusBackground?.isHidden = true
            return
        }
        let backingHost: UIView = nativePhotoPickerShowing ? window : view
        if let previous = magnistraIOS7StatusBackground,
           previous.superview !== backingHost {
            previous.removeFromSuperview()
            magnistraIOS7StatusBackground = nil
        }
        if magnistraIOS7StatusBackground == nil {
            let strip = UIView(frame: CGRect.zero)
            strip.backgroundColor = instaBlue()
            strip.isOpaque = true
            strip.isUserInteractionEnabled = false
            strip.autoresizingMask = [.flexibleWidth]
            backingHost.addSubview(strip)
            magnistraIOS7StatusBackground = strip
        }
        guard let strip = magnistraIOS7StatusBackground else { return }
        strip.backgroundColor = instaBlue()
        strip.frame = CGRect(x: 0, y: 0, width: backingHost.bounds.width, height: height)
        strip.isHidden = false
        if backingHost.subviews.last !== strip { backingHost.bringSubviewToFront(strip) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        MagnistraLegacyClearStatusBarRenderer.shared.apply(on: view)
        magnistraSyncIOS6PlusStatusBackground()
    }

    private var magnistraFullscreenOwners = Set<ObjectIdentifier>()

    override var prefersStatusBarHidden: Bool {
        if (UIDevice.current.systemVersion as NSString).integerValue >= 7 {
            return !magnistraFullscreenOwners.isEmpty
        }

        return false
    }

    override var childForStatusBarHidden: UIViewController? { return nil }

    @objc private func magnistraRefreshAfterFullscreen() {

    }

    @objc private func magnistraFullscreenStatusChanged(_ note: Notification) {
        guard (UIDevice.current.systemVersion as NSString).integerValue >= 7,
              let owner = note.object as? NSObject,
              let hidden = note.userInfo?["hidden"] as? Bool
        else { return }

        let identifier = ObjectIdentifier(owner)
        let wasHidden = !magnistraFullscreenOwners.isEmpty
        if hidden {
            magnistraFullscreenOwners.insert(identifier)
        } else {
            magnistraFullscreenOwners.remove(identifier)
        }
        if wasHidden != !magnistraFullscreenOwners.isEmpty {
            setNeedsStatusBarAppearanceUpdate()
            magnistraSyncIOS6PlusStatusBackground()
            if !hidden {

                NSObject.cancelPreviousPerformRequests(
                    withTarget: self,
                    selector: #selector(magnistraRefreshAfterFullscreen), object: nil)
                perform(#selector(magnistraRefreshAfterFullscreen),
                        with: nil, afterDelay: 0.35)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if Bundle.main.bundleIdentifier == "com.zirka.magnistra" {

            UIApplication.shared.setStatusBarHidden(false, with: .none)
            UIApplication.shared.statusBarStyle = .lightContent
            magnistraApplyBlueNavigationBars(viewControllers)
            MagnistraLegacyClearStatusBarRenderer.shared.apply(on: view)
            magnistraSyncIOS6PlusStatusBackground()
            _ = magnistraOpenAuthIfNeeded()
        }
    }

    private var magnistraAuthPresented = false

    private func magnistraOpenAuthIfNeeded() -> Bool {
        guard !magnistraAuthPresented,
              Bundle.main.bundleIdentifier == "com.zirka.magnistra" else {
            return presentedViewController is MagnistraInitialAuthViewController
        }
        if MagnistraV2SessionCache.snapshot() != nil { return false }
        if let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let file = (dir as NSString).appendingPathComponent("MagnistraSession.mgsession")
            if let bytes = try? Data(contentsOf: URL(fileURLWithPath: file)),
               let object = try? JSONSerialization.jsonObject(with: bytes, options: []),
               let session = object as? [String: Any],
               session["format"] as? String == "magnistra-session-v1",
               session["profile"] is [String: Any],
               let cookies = session["cookies"] as? [[String: Any]], !cookies.isEmpty {
                return false
            }
        }
        magnistraAuthPresented = true
        let screen = MagnistraInitialAuthViewController()
        let mgxSystemMajor = (UIDevice.current.systemVersion as NSString).integerValue
        if mgxSystemMajor == 5 || mgxSystemMajor == 6 {
            let setter = NSSelectorFromString("setWantsFullScreenLayout:")
            if screen.responds(to: setter) {
                screen.setValue(NSNumber(value: true), forKey: "wantsFullScreenLayout")
            }
        }
        screen.modalPresentationStyle = .fullScreen
        present(screen, animated: false, completion: nil)
        return true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 7.0, *) { return .lightContent }
        return .lightContent
    }

    override var childForStatusBarStyle: UIViewController? { return nil }

    private func applyApprovedTabBarLayout() {

        tabBar.clipsToBounds = true
        if let items = tabBar.items {
            for item in items {
                item.title = nil
                item.imageInsets = UIEdgeInsets(
                    top: 7.0, left: 0.0, bottom: -7.0, right: 0.0
                )
                item.titlePositionAdjustment = UIOffset(
                    horizontal: 0.0, vertical: 100.0
                )
            }
        }
    }

    private func updateApprovedTabSelection() {

        tabBar.selectionIndicatorImage = selectedIndex == 2
            ? magnistraInboxSelectedDarkImage()
            : MagnistraApprovedAssets.darkSelection
    }

    private var previouslySelectedTab = 0

    func tabBarController(_ tabBarController: UITabBarController,
                          didSelect viewController: UIViewController) {
        let index = tabBarController.selectedIndex
        if index == previouslySelectedTab,
           let navigation = viewController as? UINavigationController,
           navigation.viewControllers.count == 1 {
            switch index {
            case 0:
                (navigation.topViewController as? HomeViewController)?
                    .magnistraReturnToTop()
            case 1:
                (navigation.topViewController as? ExploreViewController)?
                    .magnistraReturnToTop()
            case 4:
                (navigation.topViewController as? ProfileViewController)?
                    .magnistraReturnToTop()
            default:
                break
            }
        }
        previouslySelectedTab = index
        updateApprovedTabSelection()
        magnistraApplyBlueNavigationBars(viewControllers)
        MagnistraLegacyClearStatusBarRenderer.shared.apply(on: view)
        magnistraSyncIOS6PlusStatusBackground()

    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let legacyStatusMajor = (UIDevice.current.systemVersion as NSString).integerValue
        if legacyStatusMajor == 5 || legacyStatusMajor == 6 {
            let setter = NSSelectorFromString("setWantsFullScreenLayout:")

            if responds(to: setter) {
                setValue(NSNumber(value: true), forKey: "wantsFullScreenLayout")
            } else {
                NSLog("MAGNISTRA_LEGACY_STATUS_FULLSCREEN_UNAVAILABLE")
            }
        }
        if Bundle.main.bundleIdentifier == "com.zirka.magnistra" {
            _ = MagnistraV2SessionCache.restoreIfAvailable()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(magnistraFullscreenStatusChanged(_:)),
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: nil)
        magnistraApplyFlatTopBarButtonAppearance()
        view.backgroundColor = instaBlue()

        if #available(iOS 7.0, *) {
            UIApplication.shared.statusBarStyle = .lightContent
        } else {
            UIApplication.shared.statusBarStyle =
                UIStatusBarStyle(rawValue: 1) ?? .default
        }

        let home =
            MagnistraSectionNavigationController(
                rootViewController:
                    HomeViewController()
            )

        let explore =
            MagnistraSectionNavigationController(
                rootViewController:
                    ExploreViewController()
            )

        let direct =
            MagnistraSectionNavigationController(
                rootViewController:
                    DirectViewController()
            )

        let activity =
            MagnistraSectionNavigationController(
                rootViewController:
                    ActivityViewController()
            )

        let profile =
            MagnistraSectionNavigationController(
                rootViewController:
                    ProfileViewController()
            )

        let controllers = [
            home,
            explore,
            direct,
            activity,
            profile
        ]

        let flatNavigationBackground =
            magnistraFlatBarImage(instaBlue())

        for controller in controllers {

            if #available(iOS 7.0, *) {
                controller.navigationBar.isTranslucent = false
                let magnistraIOS5BarTintCompatColor0 = instaBlue()
                if controller.navigationBar.responds(to: NSSelectorFromString("setBarTintColor:")) {
                    controller.navigationBar.barTintColor = magnistraIOS5BarTintCompatColor0
                } else if controller.navigationBar.responds(to: NSSelectorFromString("setTintColor:")) {
                    controller.navigationBar.setValue(magnistraIOS5BarTintCompatColor0, forKey: "tintColor")
                }
                controller.navigationBar.backgroundColor = instaBlue()
            }

            if #available(iOS 7.0, *) {
                controller.navigationBar.tintColor = UIColor.white
            } else {
                controller.navigationBar.tintColor = instaBlue()
            }
            controller.navigationBar.setBackgroundImage(
                flatNavigationBackground,
                for: .default
            )
        }

        home.tabBarItem =
            UITabBarItem(
                title: "Home",
                image:
                    magnistraApprovedTabIcon(0, selected: false),
                tag: 0
            )

        explore.tabBarItem =
            UITabBarItem(
                title: "Explore",
                image:
                    magnistraApprovedTabIcon(1, selected: false),
                tag: 1
            )

        direct.tabBarItem =
            UITabBarItem(
                title: "Direct",
                image:
                    magnistraApprovedTabIcon(2, selected: false),
                tag: 2
            )

        activity.tabBarItem =
            UITabBarItem(
                title: "Activity",
                image:
                    magnistraApprovedTabIcon(3, selected: false),
                tag: 3
            )

        profile.tabBarItem =
            UITabBarItem(
                title: "Profile",
                image:
                    magnistraApprovedTabIcon(4, selected: false),
                tag: 4
            )

        let finishedImageSelector =
            NSSelectorFromString(
                "setFinishedSelectedImage:withFinishedUnselectedImage:"
            )

        let labels = [
            "Home",
            "Explore",
            "Direct",
            "Activity",
            "Profile"
        ]

        for index in
            0..<controllers.count
        {
            let item =
                controllers[
                    index
                ].tabBarItem!

            let normalImage:
                UIImage

            let selectedImage:
                UIImage

            normalImage = magnistraApprovedTabIcon(index, selected: false)
            selectedImage = magnistraApprovedTabIcon(index, selected: true)

            item.title =
                labels[index]

            item.image =
                normalImage

            if item.responds(
                to:
                    finishedImageSelector
            ) {
                _ =
                    item.perform(
                        finishedImageSelector,
                        with:
                            selectedImage,
                        with:
                            normalImage
                    )
            }
        }

        viewControllers =
            controllers

        if #available(iOS 7.0, *) {

        } else {
            tabBar.barStyle =
                .black
        }

        tabBar.tintColor =
            UIColor.white

        tabBar.backgroundImage = magnistraMatchedInboxTabBackground()
        if tabBar.responds(to: NSSelectorFromString("setTranslucent:")) {
            tabBar.isTranslucent = false
        }
        applyApprovedTabBarLayout()

        selectedIndex = 0
        delegate = self
        updateApprovedTabSelection()
    }
}

