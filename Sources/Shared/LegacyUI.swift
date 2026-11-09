// Overview: Legacy iOS UI helpers: icons, navigation items, pull to refresh and connection recovery.
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

let magnistraProfileGridLoadingTag = 89431

enum MagnistraProfileIcons {
    static func png(_ name: String) -> UIImage? {
        return UIImage(named: "MagnistraProfile" + name)
    }
    static func oldPostIcon(_ name: String, color: UIColor) -> UIImage? {
        guard let original = UIImage(named: name) else { return nil }
        let size = CGSize(width: 23.0, height: 23.0)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let bounds = CGRect(origin: CGPoint.zero, size: size)
        original.draw(in: bounds)
        color.setFill()
        UIRectFillUsingBlendMode(bounds, .sourceIn)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    static func profileRepost(_ active: Bool) -> UIImage? {
        return oldPostIcon("MagnistraPostRepost", color: active
            ? UIColor(red: 0.22, green: 0.39, blue: 0.56, alpha: 1.0)
            : UIColor(white: 0.42, alpha: 1.0))
    }
    static func profileSaved(_ active: Bool) -> UIImage? {
        return oldPostIcon("MagnistraPostSaveActive", color: active
            ? UIColor(red: 0.22, green: 0.39, blue: 0.56, alpha: 1.0)
            : UIColor(white: 0.42, alpha: 1.0))
    }
    static func navbarItem(_ name: String, title: String, target: AnyObject,
                           action: Selector) -> UIBarButtonItem {
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 34.0)
        button.setImage(png(name), for: .normal)
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.accessibilityLabel = title
        button.addTarget(target, action: action, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }
}

final class MagnistraHiddenHeaderHitArea: UIView {
    weak var scrollTarget: UIScrollView?

    weak var interactiveSearchHost: UIView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled,
              let target = scrollTarget, target.window != nil else { return nil }
        if let search = interactiveSearchHost,
           search.window != nil, !search.isHidden, search.alpha > 0.01 {
            let searchPoint = convert(point, to: search)
            if search.bounds.contains(searchPoint),
               let hit = search.hitTest(searchPoint, with: event) {
                return hit
            }
        }
        let local = convert(point, to: target)
        return target.hitTest(local, with: event)
    }
}

final class MagnistraConnectionRecovery: NSObject {
    static let shared = MagnistraConnectionRecovery()
    static let recoveredNotification = Notification.Name("MagnistraConnectionRecovered")
    private var waiting: [String: () -> Void] = [:]
    private var alreadyRetried = Set<String>()
    private var reachability: SCNetworkReachability?
    private var timer: Timer?
    private var sawUnavailable = false
    private var availableTicks = 0

    private override init() {
        super.init()
        reachability = SCNetworkReachabilityCreateWithName(nil, "www.instagram.com")
        NotificationCenter.default.addObserver(self,
            selector: #selector(checkForRecovery),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func routeAvailable() -> Bool {
        guard let route = reachability else { return true }
        var flags = SCNetworkReachabilityFlags()
        if !SCNetworkReachabilityGetFlags(route, &flags) { return false }
        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }

    func noteFailedMedia(key: String, retry: @escaping () -> Void) {
        if !Thread.isMainThread {
            OperationQueue.main.addOperation { [weak self] in
                self?.noteFailedMedia(key: key, retry: retry)
            }
            return
        }
        guard !key.isEmpty, !alreadyRetried.contains(key) else { return }

        if waiting.count >= 80 { waiting.remove(at: waiting.startIndex) }
        waiting[key] = retry
        if !routeAvailable() {
            sawUnavailable = true
            availableTicks = 0
            alreadyRetried.removeAll()
        }
        if timer == nil {
            timer = Timer.scheduledTimer(timeInterval: 5.0,
                target: self, selector: #selector(checkForRecovery),
                userInfo: nil, repeats: true)
        }
    }

    @objc private func checkForRecovery() {
        guard !waiting.isEmpty else {
            timer?.invalidate(); timer = nil
            return
        }
        if !routeAvailable() {
            sawUnavailable = true
            availableTicks = 0
            alreadyRetried.removeAll()
            return
        }
        availableTicks += 1

        guard sawUnavailable || availableTicks >= 2 else { return }
        let actions = waiting
        waiting.removeAll()
        alreadyRetried.formUnion(actions.keys)
        sawUnavailable = false
        availableTicks = 0
        timer?.invalidate(); timer = nil
        NotificationCenter.default.post(
            name: MagnistraConnectionRecovery.recoveredNotification,
            object: nil)
        for key in actions.keys.sorted() { actions[key]?() }
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

final class MagnistraPullRefreshGesture: NSObject {
    private weak var scroll: UIScrollView?
    private var action: (() -> Void)?
    private var startedAtTop = false
    private var maximumPull: CGFloat = 0.0
    private var waitingForRest = false
    private var settleChecks = 0

    @objc private func finishAtRest() {
        guard waitingForRest, let view = scroll else { return }
        settleChecks += 1

        let overscroll = -(view.contentOffset.y + view.contentInset.top)
        if settleChecks < 35 &&
           (view.isDragging || view.isDecelerating || overscroll > 2.0) {
            perform(#selector(finishAtRest), with: nil, afterDelay: 0.09)
            return
        }
        waitingForRest = false
        settleChecks = 0
        action?()
    }

    func install(on view: UIScrollView, action: @escaping () -> Void) {
        scroll = view
        self.action = action
        view.alwaysBounceVertical = true
        view.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
    }

    @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
        guard let view = scroll else { return }
        switch recognizer.state {
        case .began:
            NSObject.cancelPreviousPerformRequests(withTarget: self,
                selector: #selector(finishAtRest), object: nil)
            waitingForRest = false

            startedAtTop = view.contentOffset.y + view.contentInset.top <= 4.0
            maximumPull = 0.0
        case .changed:
            if startedAtTop {
                let overscroll = max(0.0, -(view.contentOffset.y + view.contentInset.top))
                maximumPull = max(maximumPull, overscroll)
            }
        case .ended:
            let verticalTravel = recognizer.translation(in: view).y
            let refresh = startedAtTop && maximumPull >= 62.0 && verticalTravel >= 62.0
            startedAtTop = false
            maximumPull = 0.0
            if refresh {
                waitingForRest = true
                settleChecks = 0
                perform(#selector(finishAtRest), with: nil, afterDelay: 0.10)
            }
        case .cancelled, .failed:
            startedAtTop = false
            maximumPull = 0.0
        default:
            break
        }
    }
}

final class MagnistraNavigationPullIndicator {
    private var spinner: UIActivityIndicatorView?
    private var previousRightItem: UIBarButtonItem?

    func begin(on item: UINavigationItem, label: String) {
        guard spinner == nil else { return }
        previousRightItem = item.rightBarButtonItem
        let activity = UIActivityIndicatorView(style: .white)
        activity.frame = CGRect(x: 0.0, y: 0.0, width: 34.0, height: 34.0)
        activity.hidesWhenStopped = true
        activity.accessibilityLabel = label
        activity.startAnimating()
        spinner = activity
        item.rightBarButtonItem = UIBarButtonItem(customView: activity)
    }

    func end(on item: UINavigationItem) {
        guard let activity = spinner else { return }
        activity.stopAnimating()
        item.rightBarButtonItem = previousRightItem
        item.rightBarButtonItem?.isEnabled = true
        spinner = nil
        previousRightItem = nil
    }
}

enum MagnistraBottomLoading {
    private static let tag = 889930
    static func show(on host: UIView) {
        let label: UILabel
        if let old = host.viewWithTag(tag) as? UILabel {
            label = old
        } else {
            label = UILabel(frame: CGRect(x: 0.0,
                y: max(0.0, host.bounds.height - 38.0),
                width: host.bounds.width, height: 38.0))
            label.tag = tag
            label.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            label.backgroundColor = UIColor(white: 0.10, alpha: 0.88)
            label.textColor = .white
            label.textAlignment = .center
            label.font = UIFont.boldSystemFont(ofSize: 12.0)
            label.text = "Loading..."
            label.isUserInteractionEnabled = false
            host.addSubview(label)
        }
        host.bringSubviewToFront(label)
        label.isHidden = false
    }
    static func hide(on host: UIView) {
        host.viewWithTag(tag)?.removeFromSuperview()
    }
}

enum NoConnectionBanner {
    private static let tag = 889931
    static func isHTTPZero(_ message: String) -> Bool {
        return message.range(of: "(?i)\\bHTTP\\s*0(?![0-9])",
                             options: .regularExpression) != nil
    }
    @discardableResult
    static func showIfHTTPZero(_ text: String, on host: UIView,
                               bottomInset: CGFloat = 0.0) -> Bool {
        guard isHTTPZero(text) else { return false }
        show(on: host, bottomInset: bottomInset)
        return true
    }
    static func show(on host: UIView, bottomInset: CGFloat = 0.0) {
        let band: UILabel
        if let existing = host.viewWithTag(tag) as? UILabel {
            band = existing
        } else {
            band = UILabel(frame: CGRect.zero)
            band.tag = tag
            band.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            band.backgroundColor = UIColor(red: 0.72, green: 0.13,
                                           blue: 0.16, alpha: 0.94)
            band.textColor = UIColor.white
            band.textAlignment = .center
            band.font = UIFont.boldSystemFont(ofSize: 12.0)
            band.text = "No Connection"
            band.isUserInteractionEnabled = false
            host.addSubview(band)
        }
        band.frame = CGRect(x: 0.0,
            y: max(0.0, host.bounds.height - max(0.0, bottomInset) - 38.0),
            width: host.bounds.width, height: 38.0)
        host.bringSubviewToFront(band)
        band.isHidden = false
    }
    static func hide(on host: UIView) {
        host.viewWithTag(tag)?.removeFromSuperview()
    }
}

func instaBlue() -> UIColor {
    return UIColor(red: 10.0 / 255.0, green: 93.0 / 255.0,
                   blue: 144.0 / 255.0, alpha: 1.0)
}

final class MagnistraLegacyClearStatusBarRenderer: NSObject {
    static let shared = MagnistraLegacyClearStatusBarRenderer()
    private var strip: UIView? = nil
    private var photoPickerShowing = false

    func showRootStatusAbovePhotoPicker(_ showing: Bool, rootView: UIView) {
        guard photoPickerShowing != showing else { return }
        photoPickerShowing = showing
        guard let strip = strip, let window = rootView.window else { return }
        let host: UIView = showing ? window : rootView
        if strip.superview !== host {
            strip.removeFromSuperview()
            host.addSubview(strip)
        }
        strip.frame = CGRect(x: 0.0, y: 0.0, width: host.bounds.width,
                            height: strip.bounds.height)
        host.bringSubviewToFront(strip)
    }
    private override init() { super.init() }

    func apply(on host: UIView) {
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        guard major == 5 || major == 6 else { return }
        let app = UIApplication.shared
        if app.isStatusBarHidden {
            strip?.isHidden = true
            return
        }

        if app.statusBarStyle.rawValue != 1 {
            app.statusBarStyle = UIStatusBarStyle(rawValue: 1) ?? .default
        }
        let frame = app.statusBarFrame
        let height = frame.height
        guard height >= 18.0 && height <= 24.0 else { return }

        let systemSelector = NSSelectorFromString("statusBar")
        var status: UIView? = nil
        if app.responds(to: systemSelector) {
            status = app.perform(systemSelector)?.takeUnretainedValue() as? UIView
        }

        guard let bar = status,
              NSStringFromClass(type(of: bar)).contains("UIStatusBar"),
              bar.bounds.height >= 18.0 && bar.bounds.height <= 24.0,
              bar.bounds.width >= 240.0 &&
              bar.bounds.width <= UIScreen.main.bounds.width + 4.0 else { return }
        let transparent = UIColor.clear
        bar.backgroundColor = transparent
        bar.layer.backgroundColor = transparent.cgColor

        func clearBackdrops(_ view: UIView, _ depth: Int) {
            if depth > 3 { return }
            for child in view.subviews {
                let name = NSStringFromClass(type(of: child))
                let fullWidth = child.bounds.width >= bar.bounds.width - 4.0 &&
                    child.bounds.width <= bar.bounds.width + 4.0
                let statusHeight = child.bounds.height >= 18.0 &&
                    child.bounds.height <= 24.0
                if fullWidth && statusHeight &&
                    (name.contains("StatusBarBackground") ||
                     name.contains("StatusBarBack") || child is UIImageView) {
                    child.backgroundColor = transparent
                    child.layer.backgroundColor = transparent.cgColor
                    if let imageView = child as? UIImageView { imageView.image = nil }

                    if name.contains("StatusBarBackground") ||
                       name.contains("StatusBarBack") {
                        child.isHidden = true
                    }
                } else if !name.contains("StatusBarForeground") &&
                          !name.contains("StatusBarTime") &&
                          !name.contains("StatusBarData") {
                    clearBackdrops(child, depth + 1)
                }
            }
        }
        clearBackdrops(bar, 0)

        guard host.window != nil, host.bounds.width >= 240.0 else { return }
        let backingHost: UIView = photoPickerShowing ? (host.window ?? host) : host
        if let existing = strip, existing.superview !== backingHost {
            existing.removeFromSuperview()
            strip = nil
        }
        if strip == nil {
            let backing = UIView(frame: CGRect.zero)
            backing.isUserInteractionEnabled = false
            backing.isOpaque = true
            backing.backgroundColor = instaBlue()
            backing.autoresizingMask = [.flexibleWidth]
            backingHost.addSubview(backing)
            strip = backing
        }
        if let backing = strip {
            backing.backgroundColor = instaBlue()
            backing.frame = CGRect(x: 0, y: 0, width: backingHost.bounds.width,
                                   height: height)
            backing.isHidden = false
            if backingHost.subviews.last !== backing {
                backingHost.bringSubviewToFront(backing)
            }
        }
    }
}

func magnistraFlatBarImage(_ color: UIColor) -> UIImage {
    let size = CGSize(width: 2.0, height: 2.0)
    UIGraphicsBeginImageContextWithOptions(size, true, 0.0)
    color.setFill()
    UIRectFill(CGRect(origin: CGPoint.zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return image
}

private func magnistraApprovedDecodePNG(_ base64: String) -> UIImage {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var values = [Int16](repeating: -1, count: 256)
    for (i, byte) in alphabet.enumerated() { values[Int(byte)] = Int16(i) }
    var bytes = [UInt8]()
    bytes.reserveCapacity(base64.utf8.count * 3 / 4)
    var number: UInt32 = 0
    var bitCount = 0
    for byte in base64.utf8 {
        if byte == 61 { break }
        let value = values[Int(byte)]
        if value < 0 { continue }
        number = (number << 6) | UInt32(value)
        bitCount += 6
        if bitCount >= 8 {
            bitCount -= 8
            bytes.append(UInt8((number >> UInt32(bitCount)) & 0xff))
        }
    }
    return UIImage(data: Data(bytes)) ?? UIImage()
}

private func magnistraApprovedBitmap(_ image: UIImage) -> UIImage {
    guard let cg = image.cgImage else { return image }
    return UIImage(cgImage: cg, scale: 2.0, orientation: .up)
}

private func magnistraApprovedRenderIcon(_ image: UIImage, alpha: CGFloat) -> UIImage {
    let box = CGSize(width: 30.0, height: 30.0)
    UIGraphicsBeginImageContextWithOptions(box, false, 0.0)
    let ratio = min(27.0 / image.size.width, 27.0 / image.size.height)
    let width = image.size.width * ratio
    let height = image.size.height * ratio
    let rect = CGRect(x: (box.width - width) / 2.0,
                      y: (box.height - height) / 2.0,
                      width: width, height: height)
    image.draw(in: rect, blendMode: .normal, alpha: alpha)
    let output = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return output
}

enum MagnistraApprovedAssets {
    static let wordmark: UIImage = magnistraApprovedDecodePNG("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")
    static let home: UIImage = magnistraApprovedDecodePNG("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")
    static let search: UIImage = magnistraApprovedDecodePNG("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")
    static let inbox: UIImage = magnistraApprovedDecodePNG("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")
    static let activity: UIImage = magnistraApprovedDecodePNG("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")
    static let profile: UIImage = magnistraApprovedDecodePNG("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")
    static let background: UIImage = magnistraApprovedBitmap(magnistraApprovedDecodePNG("iVBORw0KGgoAAAANSUhEUgAAAoAAAABiCAYAAADA3mKDAAACRklEQVR4nO3dsVEEQQwAQaCUCC4UFll9QJ8VMRCKyAIZ0x2BvJ1S7e29fnx+7QuQ9Pv9uB6BY+8/z+sRgANv1wMAAPC/BCAAQIwABACIEYAAADECEAAgRgACAMTM9QDAJa9AARTZAAIAxMyuDQBAlTMAmmwAAQBiBCAAQIwABACIEYAAADECEAAgRgACAMQIQACAGH8CgTJPwAEk2QACAMQIQACAGAEIABDjDiCkuQQIUGQDCAAQIwABAGIEIABAzOy6AwRQ5QyAJhtAAIAYAQgAECMAAQBiBCAAQIwABACIEYAAADECEAAgRgACAMQIQACAmLkeALjkLxAARTaAAAAxAhAAIEYAAgDECEAAgBgBCAAQM7u+AgSocgZAkw0gAECMAAQAiBGAAAAxAhAAIEYAAgDECEAAgBgBCAAQM9cDAIe8AQeQZAMIABAjAAEAYgQgAECMAAQAiBGAAAAxAhAAIEYAAgDEzHoHDCDLGQBNNoAAADECEAAgRgACAMQIQACAGAEIABAz1wMAl3wBClBkAwgAECMAAQBiBCAAQIwABACIEYAAADECEAAgRgACAMQIQACAGAEIABAzu/4EAFDlDIAmG0AAgBgBCAAQIwABAGLmegDgkvtfAEU2gAAAMQIQACBGAAIAxLgDCGWuAAIk2QACAMQIQACAGAEIABAjAAEAYgQgAECMAAQAiBGAAAAxs+shMIAqZwA02QACAMT4Ewik2f4AFNkAAgDECEAAgBgBCAAQIwABAGIEIABAjAAEAIj5A+HtMzVHNdyAAAAAAElFTkSuQmCC"))
    static let darkSelection: UIImage = magnistraApprovedBitmap(magnistraApprovedDecodePNG("iVBORw0KGgoAAAANSUhEUgAAAIAAAABiCAYAAACYsttCAAABCklEQVR4nO3SQRHAIADAsDENcPhXCjJ4NFHQR8dc+3xk/a8DeMsAcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIO4CtkUCA7msTwkAAAAASUVORK5CYII="))
    static let clearSelection: UIImage = magnistraApprovedBitmap(magnistraApprovedDecodePNG("iVBORw0KGgoAAAANSUhEUgAAAIAAAABiCAYAAACYsttCAAAAR0lEQVR4nO3BAQ0AAADCoPdPbQ8HFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADwbxGIAAS3g3VwAAAAASUVORK5CYII="))
    static let normalIcons: [UIImage] = [home, search, inbox, activity, profile]
        .map { magnistraApprovedRenderIcon($0, alpha: 0.83) }
    static let activeIcons: [UIImage] = [home, search, inbox, activity, profile]
        .map { magnistraApprovedRenderIcon($0, alpha: 1.0) }
}

func magnistraApprovedTabIcon(_ index: Int, selected: Bool) -> UIImage {
    return selected
        ? MagnistraApprovedAssets.activeIcons[index]
        : MagnistraApprovedAssets.normalIcons[index]
}

private func magnistraFlatTopButtonBackground(_ selected: Bool) -> UIImage {

    UIGraphicsBeginImageContextWithOptions(
        CGSize(width: 1.0, height: 1.0), false, 0.0)
    let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return image.resizableImage(withCapInsets: .zero)
}

func magnistraProfileSettingsGear() -> UIImage {
    let pngBytes: [UInt8] = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00, 0x43, 0x08, 0x06, 0x00, 0x00, 0x00, 0x28, 0x08, 0xd3,
        0x4d, 0x00, 0x00, 0x05, 0xa1, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0xed, 0x9b, 0x5d, 0x88, 0x55,
        0x55, 0x14, 0xc7, 0x7f, 0x77, 0x52, 0x2b, 0x4b, 0x47, 0xc9, 0x24, 0xa5, 0x31, 0x41, 0x85, 0x0c,
        0x73, 0x8a, 0x32, 0x33, 0x24, 0x89, 0x09, 0x31, 0x28, 0x28, 0xa5, 0x0f, 0xcb, 0x1e, 0xa2, 0x22,
        0x08, 0x45, 0x8b, 0xcc, 0x07, 0x29, 0x7b, 0x50, 0xb2, 0x48, 0x0c, 0x13, 0x4a, 0xa2, 0xef, 0x07,
        0x13, 0xd2, 0xa0, 0x91, 0x34, 0xb5, 0x7a, 0xb0, 0xcc, 0xb2, 0x29, 0xfb, 0x70, 0xb4, 0x74, 0x4a,
        0x6d, 0xd0, 0x2c, 0x4a, 0x27, 0x1b, 0x75, 0x46, 0x9d, 0x7f, 0x0f, 0xae, 0x8b, 0x9b, 0xc3, 0x39,
        0xf7, 0x9e, 0x73, 0xee, 0xbd, 0xfb, 0x4c, 0xcc, 0x5d, 0xb0, 0x39, 0x33, 0xfb, 0xec, 0xb3, 0x3f,
        0xfe, 0x7b, 0xed, 0xb5, 0xd6, 0x5e, 0x6b, 0xdd, 0x9c, 0x24, 0xaa, 0x04, 0x35, 0x55, 0x08, 0xaa,
        0x40, 0x54, 0x81, 0xa8, 0x02, 0x51, 0x80, 0x7a, 0x65, 0x38, 0xf6, 0x35, 0xce, 0xf8, 0x27, 0x81,
        0xe3, 0xc0, 0xce, 0x9e, 0x06, 0x44, 0x03, 0xb0, 0x0a, 0xe8, 0x0f, 0x74, 0x59, 0x39, 0x1f, 0x58,
        0x03, 0x4c, 0xeb, 0x49, 0x40, 0x0c, 0x03, 0x2e, 0x0a, 0xa9, 0x1f, 0x01, 0xd4, 0x02, 0x6d, 0x3d,
        0x45, 0x46, 0xd4, 0xdb, 0xb3, 0x2b, 0x50, 0x5f, 0x0b, 0x0c, 0xe9, 0x49, 0xc2, 0xf2, 0xd2, 0x88,
        0xfa, 0x41, 0xc6, 0x15, 0x3d, 0x06, 0x88, 0xfc, 0xae, 0xe7, 0x02, 0xf5, 0x17, 0x02, 0xd7, 0xfe,
        0x1f, 0x81, 0x58, 0x0c, 0xcc, 0x4c, 0xa1, 0x2d, 0x46, 0x47, 0x00, 0x01, 0x70, 0x63, 0x8a, 0x79,
        0xdc, 0x0b, 0x5c, 0x59, 0xd2, 0x4a, 0x24, 0xa5, 0x2d, 0xcf, 0xeb, 0x2c, 0x2d, 0x88, 0xf9, 0xcd,
        0x4d, 0x92, 0xd6, 0xaa, 0x38, 0xbd, 0x26, 0x69, 0x60, 0x8c, 0xfe, 0x6a, 0x25, 0xbd, 0x6b, 0xdf,
        0xec, 0x92, 0x54, 0x97, 0x76, 0x3d, 0x69, 0x41, 0x58, 0x12, 0x32, 0xf9, 0xc6, 0x88, 0xb6, 0xe3,
        0x24, 0xad, 0x90, 0xd4, 0x24, 0xa9, 0x43, 0xf1, 0xe8, 0xb4, 0xa4, 0x56, 0x49, 0x1b, 0x25, 0xcd,
        0x89, 0xe8, 0xb7, 0x41, 0xd2, 0xaf, 0x81, 0xef, 0x5a, 0x25, 0x0d, 0xf6, 0x05, 0xc4, 0x92, 0x02,
        0x0b, 0xd8, 0x6b, 0x0b, 0x47, 0xd2, 0x78, 0x49, 0xab, 0x25, 0x1d, 0x53, 0xe9, 0xf4, 0xa7, 0xa4,
        0xb9, 0xd6, 0xef, 0x18, 0x87, 0x0b, 0xc2, 0xe8, 0x50, 0x1a, 0xce, 0xc8, 0xa5, 0xb8, 0x86, 0x6f,
        0x06, 0x26, 0x02, 0x8a, 0x38, 0xe3, 0x7f, 0x00, 0x5f, 0x9a, 0x2c, 0x18, 0xea, 0x58, 0x8e, 0xbd,
        0x53, 0x9c, 0xdc, 0x93, 0xa6, 0x62, 0xcf, 0xb5, 0xff, 0xf7, 0xda, 0x73, 0x78, 0x91, 0xef, 0x96,
        0x02, 0x8f, 0x27, 0x19, 0x28, 0x0d, 0x10, 0xf7, 0x00, 0xaf, 0x9b, 0x25, 0x18, 0x4b, 0x0c, 0x59,
        0xa9, 0x09, 0x2c, 0xf0, 0x1f, 0xe0, 0x04, 0xd0, 0x61, 0xef, 0xcf, 0x01, 0x2e, 0x30, 0xcd, 0x91,
        0xef, 0xfb, 0x94, 0xd5, 0xe7, 0x62, 0x8c, 0x73, 0xca, 0x0c, 0xc4, 0x83, 0xce, 0x06, 0x54, 0x5c,
        0x58, 0xbe, 0x99, 0x92, 0xc5, 0x5b, 0x25, 0xbd, 0x2c, 0x69, 0x52, 0xc4, 0x59, 0x1e, 0x2a, 0x69,
        0xb2, 0xa4, 0x57, 0x24, 0xed, 0x4b, 0xd1, 0xff, 0x31, 0x49, 0x77, 0xfb, 0x14, 0x96, 0x83, 0x24,
        0xfd, 0x10, 0x73, 0x72, 0x6d, 0x92, 0xde, 0x90, 0x34, 0x25, 0xc5, 0x18, 0xb3, 0x25, 0x7d, 0x95,
        0x00, 0x88, 0x55, 0xbe, 0xb5, 0x06, 0x92, 0xee, 0x97, 0xd4, 0x59, 0x64, 0x62, 0x9b, 0x25, 0x4d,
        0x28, 0x61, 0x8c, 0x7c, 0x99, 0x67, 0x02, 0xb3, 0x10, 0xed, 0x89, 0xa9, 0x72, 0xcb, 0x0e, 0x04,
        0x92, 0xbe, 0x89, 0x98, 0x54, 0x87, 0xa4, 0x45, 0x65, 0x00, 0xc0, 0x2d, 0x23, 0x24, 0x6d, 0x8b,
        0x18, 0xef, 0xa4, 0xa4, 0x59, 0xa5, 0xf4, 0x5f, 0x8a, 0x65, 0x79, 0x19, 0xd0, 0x37, 0xa4, 0xfe,
        0x38, 0xf0, 0x00, 0x30, 0xbf, 0xcc, 0x56, 0x70, 0x0b, 0x30, 0x0e, 0x68, 0x0c, 0x79, 0x77, 0x3a,
        0xe4, 0x02, 0xe7, 0xcd, 0xb2, 0x5c, 0x16, 0xb1, 0x3b, 0x33, 0xca, 0xcc, 0x09, 0x61, 0xe5, 0xc3,
        0x90, 0x71, 0x77, 0x94, 0xd2, 0x67, 0xda, 0x0f, 0x2f, 0xb6, 0x33, 0xe9, 0xb2, 0xa6, 0x24, 0x2d,
        0xf5, 0x00, 0x42, 0x5e, 0x90, 0xb6, 0x06, 0x80, 0xe8, 0x94, 0x74, 0x9f, 0x6f, 0x20, 0x1e, 0x09,
        0xd9, 0x91, 0x6d, 0x92, 0x06, 0x78, 0x02, 0x02, 0x49, 0xb7, 0x85, 0xcc, 0x61, 0xab, 0x6f, 0x19,
        0x11, 0x76, 0x43, 0x7c, 0x16, 0x38, 0xe2, 0xf1, 0xe6, 0xdc, 0x08, 0xbc, 0x15, 0xa8, 0x1b, 0x0d,
        0xdc, 0xe0, 0x4b, 0x46, 0x8c, 0x95, 0xb4, 0xdf, 0x76, 0xa0, 0xcb, 0x9e, 0x1f, 0x78, 0xe4, 0x04,
        0xb7, 0x5c, 0x2e, 0xe9, 0x48, 0x60, 0x2e, 0xef, 0xf9, 0xe2, 0x88, 0xc5, 0x40, 0x9d, 0x99, 0xc5,
        0xa7, 0xad, 0x6e, 0x55, 0x46, 0x0e, 0x9e, 0x5d, 0xc0, 0x4a, 0xfb, 0xfb, 0x84, 0x3d, 0x27, 0x01,
        0x57, 0x54, 0xda, 0x31, 0xb3, 0x08, 0xb8, 0xc5, 0xb9, 0x43, 0xf4, 0x02, 0xda, 0x81, 0x1f, 0x33,
        0x0c, 0x0b, 0x6c, 0x08, 0x38, 0xa2, 0x07, 0x01, 0x2b, 0xec, 0x59, 0xf2, 0xa5, 0x6b, 0x0c, 0x30,
        0xc5, 0x6e, 0x79, 0xa3, 0xad, 0xd3, 0x5a, 0xb3, 0x1d, 0x70, 0x1c, 0xaf, 0x35, 0x76, 0x01, 0x7b,
        0x30, 0x43, 0x20, 0x86, 0x01, 0xcd, 0x76, 0x61, 0x73, 0xe9, 0x00, 0xd0, 0x04, 0xec, 0x06, 0xfe,
        0x32, 0xf9, 0x75, 0x08, 0x58, 0x9d, 0x44, 0x46, 0x7c, 0x91, 0xc0, 0xbe, 0x7f, 0x28, 0x23, 0xf9,
        0xe0, 0x96, 0xe6, 0x98, 0x73, 0xed, 0x92, 0x74, 0x67, 0x12, 0x19, 0x91, 0x4b, 0xb0, 0x23, 0x4d,
        0xdd, 0x20, 0x62, 0xb7, 0x21, 0x86, 0x1b, 0x20, 0xbf, 0xae, 0x7e, 0x49, 0x64, 0x44, 0x9f, 0xc0,
        0x3d, 0x3f, 0x8a, 0xda, 0x8c, 0xed, 0xb2, 0xa6, 0x75, 0x45, 0xfc, 0x14, 0xa7, 0x8a, 0x05, 0xb5,
        0x8a, 0x09, 0xcb, 0x7c, 0x38, 0x2e, 0x0a, 0x8c, 0xc3, 0xc0, 0xd1, 0x6e, 0x00, 0x44, 0x92, 0xcd,
        0xc8, 0x25, 0x09, 0xf9, 0x75, 0x39, 0x40, 0xd5, 0xd0, 0xfd, 0xa3, 0xe6, 0x23, 0x0b, 0xbc, 0xeb,
        0x1d, 0xe2, 0xfe, 0x8b, 0xcd, 0x11, 0xed, 0x01, 0xb0, 0xa2, 0xda, 0x0d, 0x34, 0xd7, 0x5a, 0xd6,
        0x74, 0x7b, 0xcc, 0x76, 0x87, 0xed, 0x16, 0x1b, 0x9b, 0x23, 0x66, 0x00, 0x63, 0x81, 0xab, 0xec,
        0x59, 0x67, 0xaa, 0x74, 0x48, 0x48, 0xac, 0x72, 0x02, 0xf0, 0x5b, 0xc6, 0xea, 0xb3, 0x21, 0xe2,
        0xdd, 0xf7, 0xc0, 0x4f, 0xc0, 0xd7, 0xc0, 0x76, 0x03, 0xa1, 0xa5, 0x1c, 0x26, 0xf6, 0x72, 0xc7,
        0x94, 0xcd, 0xc7, 0x28, 0xde, 0xce, 0x58, 0x75, 0xd6, 0x87, 0xa8, 0xc9, 0xa3, 0x16, 0x4c, 0xaa,
        0x98, 0x89, 0x3d, 0x13, 0xf8, 0x28, 0x70, 0xd6, 0xc6, 0x02, 0x03, 0x32, 0xe4, 0x88, 0x7c, 0xf8,
        0xb0, 0xd3, 0xa9, 0xdb, 0x04, 0x7c, 0x5a, 0xe9, 0xd8, 0xe7, 0x6a, 0x73, 0xc1, 0xf7, 0x35, 0x6d,
        0x52, 0x9f, 0x55, 0xe0, 0xd6, 0xa8, 0x21, 0x62, 0x8e, 0x5e, 0x3c, 0x54, 0x4d, 0x4e, 0x68, 0xae,
        0x24, 0xef, 0x71, 0x89, 0xe5, 0x6a, 0x49, 0xed, 0x81, 0x63, 0xd1, 0xec, 0xd3, 0x1f, 0xb1, 0x33,
        0xc0, 0x51, 0x77, 0x01, 0xb7, 0x66, 0xc0, 0x0d, 0xd3, 0x43, 0xfc, 0xa6, 0xeb, 0x7d, 0xa6, 0x05,
        0x6c, 0x0a, 0xd1, 0xc7, 0x73, 0x3d, 0x83, 0x30, 0x06, 0x78, 0x38, 0x50, 0xd7, 0x69, 0x97, 0x40,
        0xaf, 0xce, 0xdb, 0x1d, 0x21, 0xd2, 0x7a, 0x9e, 0xc7, 0x63, 0xb1, 0x2e, 0x64, 0xfc, 0x8f, 0xb3,
        0x88, 0x6b, 0xcc, 0x76, 0x9c, 0xb6, 0x2e, 0x35, 0x78, 0x00, 0xe1, 0xb9, 0x80, 0x57, 0x2a, 0x1f,
        0x31, 0x9f, 0x98, 0x45, 0x5c, 0xe3, 0x40, 0x40, 0x65, 0xb9, 0x12, 0x7b, 0x7c, 0x05, 0x8f, 0xc4,
        0x2c, 0xe0, 0xc9, 0x90, 0x7b, 0xc3, 0x1e, 0xe0, 0xb3, 0x2c, 0xe2, 0x1a, 0x9b, 0x8b, 0xdc, 0xfb,
        0x67, 0x55, 0x80, 0x13, 0x16, 0x16, 0x49, 0x36, 0x79, 0xcc, 0xf7, 0xd1, 0x78, 0x31, 0xa6, 0x23,
        0x64, 0xa3, 0xa4, 0x51, 0x65, 0x00, 0xe0, 0x7a, 0xeb, 0x2b, 0x4e, 0x42, 0xc9, 0x50, 0x5f, 0x40,
        0x4c, 0x4b, 0x98, 0x05, 0xd3, 0x69, 0x19, 0x2e, 0x69, 0xf2, 0x9b, 0x46, 0x4a, 0x7a, 0xc9, 0x3c,
        0xd5, 0x5d, 0x31, 0xc7, 0x5b, 0x9f, 0x06, 0x88, 0xa4, 0x89, 0x22, 0x37, 0x03, 0xef, 0x00, 0x97,
        0xa4, 0x38, 0x85, 0x07, 0x81, 0x4f, 0x80, 0xad, 0xc0, 0xe7, 0xc0, 0xb7, 0x11, 0xed, 0xea, 0xcc,
        0x5f, 0x3a, 0xc1, 0xc6, 0xab, 0x73, 0x5c, 0x03, 0xb9, 0x98, 0xde, 0xb3, 0x85, 0xc0, 0x53, 0xe5,
        0x70, 0xde, 0x46, 0x51, 0x3e, 0x6d, 0x28, 0x2e, 0x45, 0xa5, 0x0c, 0xb5, 0xd9, 0xcd, 0x70, 0x2b,
        0xf0, 0xaf, 0xb5, 0x39, 0x8f, 0x33, 0x29, 0x82, 0xf5, 0x11, 0x40, 0x77, 0x5a, 0xbb, 0x5c, 0xcc,
        0x71, 0xa7, 0x27, 0x31, 0xb5, 0x93, 0x02, 0xf1, 0x0c, 0xb0, 0xa0, 0xc0, 0xfb, 0xef, 0x2c, 0xce,
        0x70, 0x1d, 0x30, 0x35, 0x66, 0x9f, 0x49, 0x76, 0xba, 0x1d, 0x78, 0x1f, 0x18, 0x0c, 0x4c, 0x2e,
        0xd0, 0x6e, 0x0f, 0x67, 0x22, 0xe7, 0x47, 0x2a, 0xa9, 0x35, 0x5e, 0x8d, 0x10, 0x52, 0x4f, 0x87,
        0xc8, 0x92, 0x34, 0xe9, 0x3f, 0x51, 0xb4, 0xcc, 0x72, 0x24, 0xdc, 0xe4, 0x91, 0xf6, 0x90, 0x76,
        0x7f, 0x5b, 0x90, 0xda, 0x8b, 0xd6, 0x58, 0xe3, 0x0c, 0xbc, 0xbc, 0x48, 0xdb, 0x47, 0xcd, 0xe2,
        0x3b, 0x98, 0x62, 0xf1, 0x2d, 0xa6, 0x12, 0x47, 0x15, 0x48, 0x38, 0x5d, 0xe9, 0xb4, 0xdf, 0x27,
        0x69, 0xb8, 0x6f, 0xcb, 0xb2, 0x51, 0xd2, 0xfc, 0x04, 0xed, 0x07, 0x5a, 0xfb, 0xfd, 0x31, 0x00,
        0xd8, 0x22, 0x69, 0x6a, 0x82, 0xbe, 0x9f, 0x30, 0xcd, 0x34, 0x3c, 0xed, 0x7a, 0xd2, 0xa4, 0x17,
        0x96, 0x4a, 0x4b, 0x81, 0x39, 0x14, 0xce, 0xd3, 0xbc, 0x03, 0xd8, 0xe2, 0x73, 0x52, 0x59, 0x78,
        0xa7, 0x5b, 0x62, 0x38, 0x58, 0x9b, 0x7d, 0x4f, 0x2a, 0x8b, 0x5f, 0xf0, 0x1c, 0x0a, 0x09, 0x1b,
        0xb8, 0x9b, 0xf2, 0x3b, 0x7e, 0xf3, 0x2c, 0x32, 0xe3, 0x88, 0x1d, 0xc6, 0xfe, 0x39, 0xce, 0x66,
        0xde, 0x76, 0x38, 0xef, 0x77, 0x67, 0xe1, 0xef, 0xcb, 0x02, 0x88, 0x66, 0xe7, 0xfc, 0xe7, 0x23,
        0x68, 0xae, 0xa0, 0xda, 0x9e, 0x05, 0x10, 0x59, 0xfd, 0xb8, 0xed, 0x17, 0x7b, 0xf6, 0x8f, 0x30,
        0xc5, 0x7b, 0x0c, 0x10, 0x2f, 0x98, 0xac, 0xe8, 0x63, 0x3e, 0xc7, 0x7e, 0xf6, 0xfc, 0x99, 0x33,
        0x3f, 0x79, 0xf4, 0x4e, 0x59, 0xa8, 0xcf, 0x6e, 0x49, 0xd5, 0x9f, 0x44, 0x57, 0x81, 0xa8, 0x02,
        0x51, 0x05, 0xa2, 0x10, 0xfd, 0x07, 0x25, 0x91, 0x3f, 0x6c, 0x7c, 0xd0, 0x05, 0xbb, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ]
    let data = Data(pngBytes)
    guard let raw = UIImage(data: data), let cg = raw.cgImage else {
        return UIImage()
    }
    return UIImage(cgImage: cg, scale: 3.0, orientation: .up)
}

func magnistraBackChevronImage() -> UIImage {
    let pngBytes: [UInt8] = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x29, 0x00, 0x00, 0x00, 0x3e, 0x08, 0x06, 0x00, 0x00, 0x00, 0xb6, 0xb3, 0x32,
        0xd5, 0x00, 0x00, 0x02, 0x92, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0xed, 0x9a, 0xcd, 0x8b, 0xcd,
        0x51, 0x18, 0xc7, 0xbf, 0xd7, 0xca, 0xca, 0x28, 0x2f, 0x49, 0x66, 0x84, 0xa6, 0x64, 0x41, 0xd8,
        0xf8, 0x27, 0x58, 0xa8, 0xb1, 0x98, 0x8d, 0x97, 0xc2, 0xa4, 0x99, 0xee, 0x8c, 0x4c, 0x23, 0xa6,
        0x10, 0xa9, 0x09, 0x2b, 0x2b, 0x69, 0x4a, 0x49, 0xb1, 0xb0, 0x90, 0x95, 0x86, 0x52, 0xf2, 0x92,
        0x50, 0xb2, 0xa1, 0x14, 0x52, 0x52, 0x14, 0x25, 0x72, 0x47, 0x73, 0x3f, 0x36, 0xbf, 0x5b, 0x57,
        0xdd, 0x7b, 0xcf, 0x79, 0x7e, 0xf7, 0x9c, 0xdf, 0xb9, 0xa3, 0xfb, 0xd4, 0xed, 0xb7, 0x38, 0x6f,
        0x9f, 0x9e, 0xe7, 0x39, 0xe7, 0x3c, 0xcf, 0x79, 0x6e, 0x09, 0x50, 0xa7, 0xcb, 0x02, 0xcd, 0x03,
        0xe9, 0x42, 0xfe, 0x0f, 0x90, 0x3d, 0x9d, 0x0c, 0xd9, 0x2f, 0xe9, 0xaa, 0xa4, 0x7b, 0x92, 0xa6,
        0x25, 0x6d, 0x70, 0x8e, 0x00, 0x8a, 0xfc, 0x6d, 0x04, 0x9e, 0xf0, 0xaf, 0xbc, 0x06, 0xb6, 0xb4,
        0x1a, 0x57, 0x24, 0xe0, 0x5a, 0xe0, 0x39, 0x8d, 0xe5, 0x15, 0xb0, 0x29, 0x35, 0xe4, 0x6a, 0xe0,
        0x69, 0x13, 0xc0, 0xb9, 0xec, 0x3b, 0x93, 0x12, 0xb2, 0x0f, 0x78, 0x8c, 0x5b, 0x2a, 0x40, 0x7f,
        0xa3, 0x39, 0x62, 0x6f, 0x9c, 0x5e, 0x49, 0xd7, 0x24, 0x6d, 0xf3, 0xe8, 0xfb, 0x49, 0xd2, 0x97,
        0xa2, 0x37, 0xce, 0x0a, 0xe0, 0x3e, 0x7e, 0x52, 0x01, 0x06, 0x8b, 0x36, 0xf7, 0x4a, 0x03, 0xe0,
        0x6f, 0x60, 0x7f, 0xd1, 0xbb, 0xbb, 0x17, 0xb8, 0x6b, 0x00, 0xdc, 0xeb, 0x9a, 0x33, 0x06, 0xe0,
        0x8c, 0x27, 0xe0, 0x1f, 0x60, 0x9f, 0xcf, 0xbc, 0x21, 0x01, 0x97, 0x1b, 0x34, 0x08, 0x30, 0xec,
        0x3b, 0x77, 0x28, 0xc0, 0x65, 0x06, 0x1f, 0x04, 0x38, 0x62, 0x99, 0x3f, 0x04, 0xe0, 0x12, 0xe0,
        0x91, 0x03, 0xaa, 0x5a, 0xf7, 0x3d, 0x6c, 0x5d, 0x23, 0x84, 0x06, 0x1f, 0x1a, 0x7c, 0xb0, 0x9c,
        0x67, 0x9d, 0x76, 0x00, 0x7b, 0x80, 0x07, 0x06, 0x13, 0x97, 0xf3, 0xae, 0x95, 0x17, 0x70, 0xa9,
        0xc1, 0x07, 0xab, 0xc0, 0x58, 0x3b, 0x16, 0xcb, 0x7b, 0x93, 0xdc, 0x31, 0x00, 0x8e, 0xb4, 0xeb,
        0xf7, 0x79, 0x7c, 0xf0, 0x76, 0x11, 0x26, 0x6e, 0x07, 0xf2, 0xa6, 0x01, 0x70, 0x22, 0xd4, 0x19,
        0x1c, 0x0b, 0xf0, 0x6c, 0xc8, 0x9b, 0xcc, 0xb7, 0xe3, 0x2d, 0x03, 0xe0, 0x85, 0xd0, 0xf1, 0x80,
        0x4f, 0xa7, 0x1b, 0x06, 0xc0, 0x8b, 0x31, 0xa2, 0x2a, 0x57, 0x87, 0x2b, 0x06, 0xc0, 0x4b, 0xb1,
        0x62, 0xd3, 0x56, 0x8d, 0x53, 0x06, 0xc0, 0xeb, 0x31, 0x53, 0x90, 0x66, 0x0d, 0x07, 0xeb, 0x12,
        0x24, 0x97, 0x4c, 0xc7, 0xce, 0x93, 0x4a, 0x4d, 0x5e, 0xd5, 0x9e, 0x49, 0xda, 0x2a, 0x09, 0x49,
        0xa5, 0x16, 0x79, 0xc9, 0x1b, 0x49, 0xeb, 0x53, 0x3d, 0xb3, 0xbc, 0xaf, 0xa5, 0x40, 0x8e, 0xf1,
        0x6b, 0x24, 0x1d, 0x8a, 0xfe, 0xe6, 0xd1, 0x44, 0xc5, 0x9b, 0x81, 0x77, 0x45, 0xdf, 0x2c, 0x79,
        0x36, 0xce, 0x0e, 0xe0, 0x87, 0x01, 0x74, 0x77, 0x0a, 0x48, 0x65, 0x49, 0x52, 0xc5, 0x13, 0x72,
        0x16, 0xd8, 0x99, 0x02, 0x52, 0xc0, 0x90, 0x01, 0xf4, 0x17, 0xb0, 0x3d, 0x05, 0xa4, 0x80, 0x3d,
        0x99, 0xa6, 0x7c, 0x35, 0x3a, 0x98, 0x02, 0x52, 0x59, 0x76, 0xe7, 0x7b, 0x76, 0xce, 0xb9, 0x12,
        0xfe, 0x98, 0xa1, 0xda, 0x90, 0x41, 0xa3, 0xe6, 0xac, 0x30, 0x64, 0x64, 0x7e, 0x20, 0xf3, 0x3d,
        0x5f, 0x19, 0x4b, 0x01, 0xa9, 0xcc, 0x94, 0x16, 0xd0, 0xd1, 0x14, 0x90, 0xb5, 0xfb, 0xfd, 0xa7,
        0x01, 0x74, 0x24, 0x05, 0x64, 0xcd, 0x47, 0xa3, 0x9b, 0x3e, 0xc4, 0xee, 0x1b, 0x35, 0x9c, 0xa3,
        0xb9, 0x36, 0x53, 0xa8, 0xb3, 0xac, 0x6c, 0x38, 0x9e, 0x00, 0x8e, 0xa7, 0x80, 0x14, 0x30, 0x89,
        0x4d, 0x26, 0x52, 0x40, 0x0a, 0x18, 0xaf, 0x7b, 0x9c, 0xf2, 0x91, 0xf1, 0x14, 0x90, 0xca, 0x4c,
        0x69, 0x91, 0xe1, 0x14, 0x90, 0x02, 0x4e, 0x18, 0x20, 0xab, 0x59, 0x6c, 0x90, 0xa4, 0x22, 0x76,
        0xda, 0x00, 0x5a, 0x01, 0x76, 0xa5, 0x2a, 0x36, 0x9d, 0xf1, 0xd4, 0x24, 0xc0, 0x5b, 0x60, 0x71,
        0x8a, 0x62, 0xd3, 0xa4, 0xa4, 0x29, 0x47, 0x9f, 0x5a, 0xa2, 0xb7, 0x48, 0xd2, 0xc2, 0x54, 0xa5,
        0xe4, 0xa3, 0x92, 0x4e, 0x79, 0x24, 0x75, 0x1f, 0x25, 0x7d, 0x4e, 0x59, 0xef, 0x3e, 0x29, 0xe9,
        0x7c, 0x8b, 0xf6, 0x59, 0x49, 0x97, 0x3b, 0xa5, 0xde, 0x7d, 0xae, 0xc1, 0xcd, 0xf4, 0xcd, 0x55,
        0x70, 0x2a, 0x1a, 0x52, 0xc0, 0x31, 0xe0, 0x03, 0xf0, 0x15, 0x78, 0x01, 0x0c, 0xe4, 0x7d, 0xc1,
        0x88, 0x2d, 0xeb, 0x24, 0xad, 0x92, 0xf4, 0x52, 0xd2, 0x77, 0x57, 0xe7, 0x54, 0x90, 0xdd, 0xbf,
        0xdc, 0x74, 0x21, 0xe7, 0x35, 0xe4, 0x5f, 0x32, 0x47, 0x0b, 0x42, 0xd3, 0xb3, 0x7c, 0xf9, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ]
    let data = Data(pngBytes)
    guard let raw = UIImage(data: data), let cg = raw.cgImage else {
        return UIImage()
    }
    return UIImage(cgImage: cg, scale: 3.0, orientation: .up)
}

func magnistraApplyFlatTopBarButtonAppearance() {
    let normal = magnistraFlatTopButtonBackground(false)
    let highlighted = magnistraFlatTopButtonBackground(true)
    let barButtons = UIBarButtonItem.appearance()
    barButtons.setBackgroundImage(normal, for: .normal, barMetrics: .default)
    barButtons.setBackgroundImage(highlighted, for: .highlighted, barMetrics: .default)
    barButtons.setBackButtonBackgroundImage(normal, for: .normal, barMetrics: .default)
    barButtons.setBackButtonBackgroundImage(highlighted, for: .highlighted, barMetrics: .default)
}

func magnistraMatchedInboxTabBackground() -> UIImage {
    let original = MagnistraApprovedAssets.background
    let size = CGSize(width: 320.0, height: 49.0)
    UIGraphicsBeginImageContextWithOptions(size, true, 2.0)
    original.draw(in: CGRect(origin: .zero, size: size))
    instaBlue().setFill()
    UIRectFill(CGRect(x: 128.0, y: 0.0, width: 64.0, height: 49.0))
    let result = UIGraphicsGetImageFromCurrentImageContext() ?? original
    UIGraphicsEndImageContext()
    return result
}

func magnistraInboxSelectedDarkImage() -> UIImage {
    let size = CGSize(width: 64.0, height: 49.0)
    UIGraphicsBeginImageContextWithOptions(size, true, 2.0)
    let blue = instaBlue()
    var r: CGFloat = 0.0
    var g: CGFloat = 0.0
    var b: CGFloat = 0.0
    var alpha: CGFloat = 0.0
    blue.getRed(&r, green: &g, blue: &b, alpha: &alpha)
    UIColor(red: r * 0.72, green: g * 0.72,
            blue: b * 0.72, alpha: 1.0).setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let result = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return result
}

func magnistraLegacyHomeWordmarkImage() -> UIImage {
    let source = MagnistraApprovedAssets.wordmark
    let targetSize = CGSize(width: 158.0, height: 31.0)
    let factor = min(targetSize.width / source.size.width,
                     targetSize.height / source.size.height)
    let fitWidth = source.size.width * factor
    let fitHeight = source.size.height * factor
    let fittedRect = CGRect(x: (targetSize.width - fitWidth) / 2.0,
                            y: (targetSize.height - fitHeight) / 2.0,
                            width: fitWidth, height: fitHeight)
    UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
    if let context = UIGraphicsGetCurrentContext() {
        context.interpolationQuality = .high
    }
    source.draw(in: fittedRect)
    let image = UIGraphicsGetImageFromCurrentImageContext() ?? source
    UIGraphicsEndImageContext()
    return image
}

private func instaDark() -> UIColor {
    return UIColor(
        red: 0.12,
        green: 0.12,
        blue: 0.12,
        alpha: 1.0
    )
}

func instaLightGray() -> UIColor {
    return UIColor(
        red: 0.94,
        green: 0.94,
        blue: 0.94,
        alpha: 1.0
    )
}

func magnistraProfileGridPlaceholderColor(
    for index: Int
) -> UIColor {
    let colors: [UIColor] = [
        UIColor(red: 0.73, green: 0.43, blue: 0.34, alpha: 1.0),
        UIColor(red: 0.31, green: 0.53, blue: 0.62, alpha: 1.0),
        UIColor(red: 0.62, green: 0.55, blue: 0.38, alpha: 1.0),
        UIColor(red: 0.42, green: 0.60, blue: 0.44, alpha: 1.0),
        UIColor(red: 0.65, green: 0.39, blue: 0.52, alpha: 1.0),
        UIColor(red: 0.45, green: 0.43, blue: 0.64, alpha: 1.0),
        UIColor(red: 0.72, green: 0.58, blue: 0.34, alpha: 1.0),
        UIColor(red: 0.35, green: 0.58, blue: 0.58, alpha: 1.0),
        UIColor(red: 0.58, green: 0.47, blue: 0.39, alpha: 1.0)
    ]

    let safeIndex =
        index < 0
            ? 0
            : index

    return colors[
        safeIndex %
        colors.count
    ]
}

private func instaTabIcon(
    _ kind: Int,
    selected: Bool = false
) -> UIImage {

    let size = CGSize(
        width: 24.0,
        height: 24.0
    )

    UIGraphicsBeginImageContextWithOptions(
        size,
        false,
        0.0
    )

    let ink: UIColor

    if selected {
        ink = UIColor.white
    } else {

        ink = UIColor(
            white: 0.66,
            alpha: 1.0
        )
    }

    ink.setStroke()
    ink.setFill()

    switch kind {

    case 0:

        let house = UIBezierPath()
        house.lineWidth = 1.8
        house.lineCapStyle = .round
        house.lineJoinStyle = .round

        house.move(
            to: CGPoint(x: 4.5, y: 11.0)
        )
        house.addLine(
            to: CGPoint(x: 12.0, y: 4.5)
        )
        house.addLine(
            to: CGPoint(x: 19.5, y: 11.0)
        )
        house.addLine(
            to: CGPoint(x: 19.5, y: 20.0)
        )
        house.addLine(
            to: CGPoint(x: 4.5, y: 20.0)
        )
        house.close()
        house.stroke()

    case 1:

        let lens = UIBezierPath(
            ovalIn: CGRect(
                x: 3.5,
                y: 3.5,
                width: 12.5,
                height: 12.5
            )
        )

        lens.lineWidth = 1.8
        lens.stroke()

        let handle = UIBezierPath()
        handle.lineWidth = 1.8
        handle.lineCapStyle = .round

        handle.move(
            to: CGPoint(
                x: 14.5,
                y: 14.5
            )
        )

        handle.addLine(
            to: CGPoint(
                x: 20.5,
                y: 20.5
            )
        )

        handle.stroke()

    case 2:

        let cameraBody = UIBezierPath(
            roundedRect: CGRect(
                x: 3.0,
                y: 6.5,
                width: 18.0,
                height: 14.0
            ),
            cornerRadius: 2.5
        )

        cameraBody.lineWidth = 1.8
        cameraBody.stroke()

        let cameraLens = UIBezierPath(
            ovalIn: CGRect(
                x: 8.5,
                y: 10.0,
                width: 7.0,
                height: 7.0
            )
        )

        cameraLens.lineWidth = 1.8
        cameraLens.stroke()

    case 3:

        let heart = UIBezierPath()
        heart.lineWidth = 1.8
        heart.lineCapStyle = .round
        heart.lineJoinStyle = .round

        heart.move(
            to: CGPoint(
                x: 12.0,
                y: 20.5
            )
        )

        heart.addCurve(
            to: CGPoint(
                x: 3.7,
                y: 10.0
            ),
            controlPoint1: CGPoint(
                x: 8.0,
                y: 17.0
            ),
            controlPoint2: CGPoint(
                x: 3.7,
                y: 13.8
            )
        )

        heart.addCurve(
            to: CGPoint(
                x: 12.0,
                y: 6.3
            ),
            controlPoint1: CGPoint(
                x: 3.7,
                y: 5.1
            ),
            controlPoint2: CGPoint(
                x: 9.1,
                y: 3.8
            )
        )

        heart.addCurve(
            to: CGPoint(
                x: 20.3,
                y: 10.0
            ),
            controlPoint1: CGPoint(
                x: 14.9,
                y: 3.8
            ),
            controlPoint2: CGPoint(
                x: 20.3,
                y: 5.1
            )
        )

        heart.addCurve(
            to: CGPoint(
                x: 12.0,
                y: 20.5
            ),
            controlPoint1: CGPoint(
                x: 20.3,
                y: 13.8
            ),
            controlPoint2: CGPoint(
                x: 16.0,
                y: 17.0
            )
        )

        heart.close()
        heart.stroke()

    default:

        let head = UIBezierPath(
            ovalIn: CGRect(
                x: 8.3,
                y: 3.2,
                width: 7.4,
                height: 7.4
            )
        )

        head.lineWidth = 1.8
        head.stroke()

        let shoulders = UIBezierPath()
        shoulders.lineWidth = 1.8
        shoulders.lineCapStyle = .round
        shoulders.lineJoinStyle = .round

        shoulders.move(
            to: CGPoint(
                x: 4.8,
                y: 20.5
            )
        )

        shoulders.addCurve(
            to: CGPoint(
                x: 19.2,
                y: 20.5
            ),
            controlPoint1: CGPoint(
                x: 5.3,
                y: 14.0
            ),
            controlPoint2: CGPoint(
                x: 18.7,
                y: 14.0
            )
        )

        shoulders.stroke()
    }

    let rendered =
        UIGraphicsGetImageFromCurrentImageContext()

    UIGraphicsEndImageContext()

    if let rendered = rendered {
        return rendered
    }

    return UIImage()
}

private func magnistraDirectTabIcon(
    selected: Bool
) -> UIImage {
    let size =
        CGSize(
            width: 30.0,
            height: 30.0
        )

    UIGraphicsBeginImageContextWithOptions(
        size,
        false,
        0.0
    )

    let color =
        selected
            ? UIColor.white
            : UIColor(
                white: 0.72,
                alpha: 1.0
            )

    color.setStroke()

    let envelope =
        UIBezierPath(
            roundedRect:
                CGRect(
                    x: 5.0,
                    y: 8.0,
                    width: 20.0,
                    height: 14.0
                ),
            cornerRadius: 2.0
        )

    envelope.lineWidth = 2.0
    envelope.stroke()

    let flap =
        UIBezierPath()

    flap.lineWidth = 2.0

    flap.move(
        to:
            CGPoint(
                x: 6.0,
                y: 9.0
            )
    )

    flap.addLine(
        to:
            CGPoint(
                x: 15.0,
                y: 16.0
            )
    )

    flap.addLine(
        to:
            CGPoint(
                x: 24.0,
                y: 9.0
            )
    )

    flap.stroke()

    let image =
        UIGraphicsGetImageFromCurrentImageContext()

    UIGraphicsEndImageContext()

    return image ?? UIImage()
}

private final class MagnistraTrackedNavigationTitle: UIView {
    private var currentText = ""
    private let font = UIFont(name: "HelveticaNeue-Bold", size: 17.0)
        ?? UIFont.boldSystemFont(ofSize: 17.0)
    private let tracking: CGFloat = 0.8

    func apply(_ value: String) {
        if currentText == value { return }
        currentText = value
        for child in subviews { child.removeFromSuperview() }
        let letters = value.uppercased().map { String($0) }
        var widths = [CGFloat]()
        var labels = [UILabel]()
        var total: CGFloat = 0.0
        for letter in letters {
            let label = UILabel(frame: .zero)
            label.backgroundColor = UIColor.clear
            label.font = font
            label.textColor = UIColor.white
            label.textAlignment = .center
            label.text = letter
            label.sizeToFit()

            let width = max(4.0, label.bounds.width)
            widths.append(width)
            labels.append(label)
            total += width
        }
        if letters.count > 1 {
            total += CGFloat(letters.count - 1) * tracking
        }
        let width: CGFloat = 200.0
        frame = CGRect(x: 0.0, y: 0.0, width: width, height: 38.0)
        clipsToBounds = true
        isUserInteractionEnabled = false
        var x = max(0.0, (width - total) / 2.0)
        for index in 0..<labels.count {
            let label = labels[index]
            let w = widths[index]
            label.frame = CGRect(x: x, y: 0.0, width: w, height: 38.0)
            addSubview(label)
            x += w + tracking
        }
        isAccessibilityElement = true
        accessibilityLabel = value
    }
}

final class MagnistraSectionNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let doubleTap = UITapGestureRecognizer(
            target: self, action: #selector(magnistraDoubleTapToTop(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        navigationBar.addGestureRecognizer(doubleTap)
    }

    @objc private func magnistraDoubleTapToTop(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended,
              let screen = topViewController,
              screen.hidesBottomBarWhenPushed,
              let content = magnistraPrimaryScroll(in: screen.view) else { return }
        let y = -content.contentInset.top
        content.setContentOffset(CGPoint(x: content.contentOffset.x, y: y),
                                 animated: true)
    }

    private func magnistraPrimaryScroll(in root: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let scroll = view as? UIScrollView,
               scroll.isScrollEnabled,
               scroll.bounds.width > root.bounds.width * 0.65,
               scroll.bounds.height > root.bounds.height * 0.45 {
                candidates.append(scroll)
            }
            for child in view.subviews { visit(child) }
        }
        visit(root)
        return candidates.max {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }
    }

    private func magnistraStyleVisibleTitle() {
        guard let screen = topViewController else { return }
        let item = screen.navigationItem

        if let existing = item.titleView,
           !(existing is MagnistraTrackedNavigationTitle) { return }
        let title = item.title ?? screen.title ?? ""
        if title.isEmpty { return }
        if let current = item.titleView as? MagnistraTrackedNavigationTitle {
            current.apply(title)
        } else {
            let custom = MagnistraTrackedNavigationTitle()
            custom.apply(title)
            item.titleView = custom
        }
    }

    private func magnistraKeepTitleOnBarMidline() {
        guard let tracked = topViewController?.navigationItem.titleView
                as? MagnistraTrackedNavigationTitle,
              let parent = tracked.superview,
              navigationBar.bounds.width > 0.0 else { return }
        let barCenter = CGPoint(x: navigationBar.bounds.midX,
                                y: navigationBar.bounds.midY)
        let midpointInParent = parent.convert(barCenter, from: navigationBar)
        let offsetX = midpointInParent.x - tracked.center.x
        let offsetY = midpointInParent.y - tracked.center.y

        let scale = UIScreen.main.scale
        let alignedY = round(offsetY * scale) / scale
        if abs(tracked.transform.tx - offsetX) > 0.25 ||
           abs(tracked.transform.ty - alignedY) > 0.25 {
            tracked.transform = CGAffineTransform(
                translationX: offsetX, y: alignedY)
        }
    }

    private func magnistraAlignLegacyEdgeButtons() {
        guard (UIDevice.current.systemVersion as NSString).integerValue >= 7,
              let item = topViewController?.navigationItem else { return }
        func align(_ barItem: UIBarButtonItem?, left: Bool) {
            guard let button = barItem?.customView as? UIButton,
                  let name = button.accessibilityLabel?.lowercased() else { return }

            guard name == "reels" || name == "new message" ||
                  name == "settings" || name.contains("menu") else { return }
            button.contentHorizontalAlignment = left ? .left : .right
        }
        align(item.leftBarButtonItem, left: true)
        align(item.rightBarButtonItem, left: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        magnistraAlignLegacyEdgeButtons()
        magnistraStyleVisibleTitle()
        navigationBar.layoutIfNeeded()
        magnistraKeepTitleOnBarMidline()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        magnistraAlignLegacyEdgeButtons()
        magnistraStyleVisibleTitle()
        navigationBar.layoutIfNeeded()
        magnistraKeepTitleOnBarMidline()
        magnistraRequestStatusBarRefresh(animated: false)
    }

    private func magnistraRequestStatusBarRefresh(animated: Bool) {
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraStatusBarNeedsRefresh"), object: nil)
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(magnistraSyncStatusBarAfterNavigation), object: nil)
        if animated {
            perform(#selector(magnistraSyncStatusBarAfterNavigation),
                    with: nil, afterDelay: 0.40)
        }
    }

    @objc private func magnistraSyncStatusBarAfterNavigation() {
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraStatusBarNeedsRefresh"), object: nil)
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        let popped = super.popViewController(animated: animated)
        if popped != nil { magnistraRequestStatusBarRefresh(animated: animated) }
        return popped
    }

    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        let popped = super.popToRootViewController(animated: animated)
        if popped != nil { magnistraRequestStatusBarRefresh(animated: animated) }
        return popped
    }

    override func popToViewController(_ viewController: UIViewController,
                                      animated: Bool) -> [UIViewController]? {
        let popped = super.popToViewController(viewController, animated: animated)
        if popped != nil { magnistraRequestStatusBarRefresh(animated: animated) }
        return popped
    }

    @objc private func magnistraBackImageTapped() {
        _ = popViewController(animated: true)
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {

        if let previous = topViewController {
            if viewController.navigationItem.leftBarButtonItem == nil {
                let button = UIButton(type: .custom)
                button.frame = CGRect(x: 0.0, y: 0.0,
                                      width: 32.0, height: 32.0)
                button.backgroundColor = UIColor.clear
                button.setImage(magnistraBackChevronImage(), for: .normal)
                button.accessibilityLabel = "Back"
                button.addTarget(self,
                    action: #selector(magnistraBackImageTapped),
                    for: .touchUpInside)
                viewController.navigationItem.leftBarButtonItem =
                    UIBarButtonItem(customView: button)
            }
            previous.navigationItem.backBarButtonItem = UIBarButtonItem(
                title: "", style: .plain, target: nil, action: nil)
        }

        let postFromRequestedGrid =
            viewController is MagnistraProfilePostViewController &&
            (topViewController is MagnistraProfileRepostsViewController ||
             topViewController is MagnistraExploreSearchResultsViewController)
        if viewController is MagnistraProfileViewController ||
           viewController is MagnistraExploreFeedViewController ||
           viewController is MagnistraExploreTagFeedViewController ||
           viewController is MagnistraExploreSearchResultsViewController ||
           viewController is MagnistraExploreTagGridViewController ||
           postFromRequestedGrid {
            viewController.hidesBottomBarWhenPushed = true
        }
        super.pushViewController(viewController, animated: animated)
        magnistraRequestStatusBarRefresh(animated: animated)
    }
}

final class MagnistraUnifiedLoadMoreBand: UIView {
    private let caption = UILabel()
    private let generatedInline = UILabel()
    private weak var trackedScroll: UIScrollView?
    private weak var trackedInline: UIView?
    private var savedBottomInset: CGFloat? = nil
    private var loading = false
    private var hasShownInline = false
    private var lastScrollOffsetY: CGFloat? = nil
    private var userScrolledBack = false
    private let overscrollFill = UIView()
    var bottomInset: CGFloat = 0.0
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0.10, alpha: 0.88)
        caption.backgroundColor = UIColor.clear
        caption.textAlignment = .center
        caption.textColor = UIColor.white
        caption.font = UIFont.boldSystemFont(ofSize: 12.0)
        caption.text = "Loading..."
        addSubview(caption)
        generatedInline.backgroundColor = UIColor(white: 0.10, alpha: 0.88)
        generatedInline.textAlignment = .center
        generatedInline.textColor = UIColor.white
        generatedInline.font = UIFont.boldSystemFont(ofSize: 12.0)
        generatedInline.text = "Loading..."
        generatedInline.isUserInteractionEnabled = false
        overscrollFill.backgroundColor = UIColor(white: 0.10, alpha: 0.88)
        overscrollFill.isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    func useCommentsGrayAppearance() {
        let gray = UIColor(white: 0.86, alpha: 0.90)
        let darkText = UIColor(white: 0.22, alpha: 1.0)
        backgroundColor = gray
        generatedInline.backgroundColor = gray
        overscrollFill.backgroundColor = gray
        caption.textColor = darkText
        generatedInline.textColor = darkText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        caption.frame = bounds
    }

    private func removeGeneratedInline() {
        if let scroll = trackedScroll {
            if let old = savedBottomInset {
                var inset = scroll.contentInset
                inset.bottom = old
                scroll.contentInset = inset
            }
        }
        savedBottomInset = nil
        generatedInline.removeFromSuperview()
        overscrollFill.removeFromSuperview()
    }

    func layout(on host: UIView) {
        frame = CGRect(x: 0.0,
                       y: max(0.0, host.bounds.height - bottomInset - 38.0),
                       width: host.bounds.width,
                       height: 38.0)
        refresh()
    }

    func show(_ visible: Bool, on host: UIView,
              tracking scroll: UIScrollView? = nil, inline: UIView? = nil) {
        if superview !== host {
            removeFromSuperview()
            host.addSubview(self)
        }
        if !visible {
            loading = false
            hasShownInline = false
            lastScrollOffsetY = nil
            userScrolledBack = false
            removeGeneratedInline()
            trackedScroll = nil
            trackedInline = nil
            isHidden = true
        } else if let nextScroll = scroll {

            removeGeneratedInline()
            trackedScroll = nextScroll
            trackedInline = inline
            loading = true
            hasShownInline = false
            lastScrollOffsetY = nextScroll.contentOffset.y
            userScrolledBack = false

            if inline == nil || nextScroll is UITableView {
                nextScroll.addSubview(overscrollFill)
                nextScroll.sendSubviewToBack(overscrollFill)
            }
            if inline == nil {
                savedBottomInset = nextScroll.contentInset.bottom
                var inset = nextScroll.contentInset
                inset.bottom += 42.0
                nextScroll.contentInset = inset
                nextScroll.addSubview(generatedInline)
            }
        }
        layout(on: host)
    }

    func refresh() {
        guard loading, let scroll = trackedScroll, let host = superview else {
            isHidden = true
            return
        }
        let inline: UIView
        if let source = trackedInline, source.superview != nil {
            inline = source
        } else if savedBottomInset != nil {

            generatedInline.frame = CGRect(x: 0.0,
                y: scroll.contentSize.height + 2.0,
                width: max(1.0, scroll.bounds.width), height: 38.0)
            inline = generatedInline
        } else {
            isHidden = true
            return
        }
        if inline.isHidden {
            overscrollFill.isHidden = true
            isHidden = true
            return
        }
        if overscrollFill.superview === scroll {
            let footer = inline.convert(inline.bounds, to: scroll)
            overscrollFill.frame = CGRect(
                x: 0.0, y: footer.maxY,
                width: max(1.0, scroll.bounds.width),
                height: max(640.0, scroll.bounds.height * 2.0)
            )
            overscrollFill.isHidden = false
        }
        let rect = inline.convert(inline.bounds, to: host)
        let viewport = scroll.convert(scroll.bounds, to: host)
        let top = max(host.bounds.minY, viewport.minY)
        let bottom = min(viewport.maxY, host.bounds.maxY - bottomInset)
        let inlineOnScreen = rect.maxY > top + 0.5 && rect.minY < bottom - 0.5
        if inlineOnScreen { hasShownInline = true }

        if let previous = lastScrollOffsetY,
           scroll.contentOffset.y < previous - 2.0 {
            userScrolledBack = true
        }
        lastScrollOffsetY = scroll.contentOffset.y

        isHidden = !(rect.minY >= bottom - 0.5 &&
                      (hasShownInline || userScrolledBack))
        if !isHidden { host.bringSubviewToFront(self) }
    }
}

func magnistraUserInitiatedPagination(_ scroll: UIScrollView) -> Bool {
    guard scroll.window != nil && scroll.isDragging else { return false }
    let firstY = -scroll.contentInset.top
    let bottomY = max(firstY,
        scroll.contentSize.height - scroll.bounds.height + scroll.contentInset.bottom)
    let pullBeyondBottom = scroll.contentOffset.y - bottomY
    let upwardFingerPull = scroll.panGestureRecognizer.translation(in: scroll).y
    return pullBeyondBottom >= 18.0 && upwardFingerPull <= -18.0
}

