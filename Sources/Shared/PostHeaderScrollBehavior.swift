// Overview: Scroll behavior of the post header.
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

final class MagnistraPostHeaderScrollBehavior: NSObject {

    private weak var navigation: UINavigationController?
    private weak var table: UITableView?
    private weak var owner: UIView?
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
        let rect = CGRect(x: 0.0, y: -height, width: bounds.width,
                          height: bounds.height + height)
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
        bar.transform = CGAffineTransform(translationX: 0.0, y: -hidden)

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

    func revealForTabReturn() {
        guard active else { return }
        hidden = 0.0
        previousOffset = table?.contentOffset.y
        displayHeader()
    }

    func activate(_ feed: UITableView,
                  navigationController nav: UINavigationController?) {
        guard !active, let nav = nav, let ownerView = feed.superview else { return }
        navigation = nav
        table = feed
        owner = ownerView
        height = max(1.0, nav.navigationBar.bounds.height)
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
        nav.view.backgroundColor = instaBlue()
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
        previousBarMask = nil
        navigation?.view.clipsToBounds = oldNavigationClips
        navigation?.view.backgroundColor = oldNavigationColor
        if let feed = table {
            let oldY = feed.contentOffset.y
            if let inset = oldInset { feed.contentInset = inset }
            if let owner = owner { feed.frame = owner.bounds }
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
        previousOffset = nil
        hidden = 0.0
    }

    func observe(_ scrollView: UIScrollView, initialContentReady: Bool) {
        guard active, let feed = table, scrollView === feed else { return }
        let y = feed.contentOffset.y

        guard initialContentReady else {
            previousOffset = y
            if hidden != 0.0 { hidden = 0.0; displayHeader() }
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
