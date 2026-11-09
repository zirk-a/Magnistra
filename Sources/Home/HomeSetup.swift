// Overview: Home feed: setup (title, table, status label, pull to refresh).
import UIKit
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import Security
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration

extension HomeViewController {


    func setHomePullRefreshIndicator(_ active: Bool) {
        if active {
            if homePullRefreshIsShowing { return }
            homePullRefreshIsShowing = true
            let spinner = UIActivityIndicatorView(style: .white)
            spinner.frame = CGRect(x: 0.0, y: 0.0, width: 34.0, height: 34.0)
            spinner.hidesWhenStopped = true
            spinner.accessibilityLabel = "Updating Home feed"
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            if !homePullRefreshIsShowing { return }
            homePullRefreshIsShowing = false
            if let spinner = navigationItem.rightBarButtonItem?.customView as? UIActivityIndicatorView {
                spinner.stopAnimating()
            }
            navigationItem.rightBarButtonItem = nil
        }
    }

    func magnistraReturnToTop() {
        postHeaderScroll.revealForTabReturn()
        let y = -tableView.contentInset.top
        tableView.setContentOffset(CGPoint(x: 0.0, y: y), animated: true)
    }

    func configureClassicTitle() {

        let holder = UIView(
            frame: CGRect(x: 0.0, y: 0.0, width: 170.0, height: 36.0)
        )
        holder.backgroundColor = UIColor.clear
        holder.clipsToBounds = false
        let logo = UIImageView(
            frame: CGRect(x: 6.0, y: 2.5, width: 158.0, height: 31.0)
        )
        logo.backgroundColor = UIColor.clear
        logo.clipsToBounds = false
        logo.contentMode = .scaleAspectFit
        logo.image = magnistraLegacyHomeWordmarkImage()
        holder.addSubview(logo)
        navigationItem.titleView = holder

        navigationItem.rightBarButtonItem = nil

        tabBarItem.title = "Home"
    }

    func configureTable() {
        tableView =
            UITableView(
                frame: view.bounds,
                style: .plain
            )

        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        tableView.dataSource = self
        tableView.delegate = self
        pullRefreshGesture.install(on: tableView) { [weak self] in
            self?.refreshTapped()
        }

        tableView.backgroundColor = UIColor.white

        tableView.separatorStyle =
            .none

        tableView.rowHeight =
            467.0

        tableView.alwaysBounceVertical =
            true

        let footer =
            UIView(
                frame: CGRect(
                    x: 0.0,
                    y: 0.0,
                    width:
                        view.bounds.size.width,
                    height: 38.0
                )
            )

        footer.backgroundColor =
            UIColor.clear

        tableView.tableFooterView =
            footer

        storyTray.useCompactHomeStoriesStyle()
        storyTray.onOpen = { [weak self] reel in
            guard let self = self else { return }
            self.present(MagnistraStoryViewer(reel: reel,
                         siblings: self.storyTray.displayedReels,
                         deferStatusBarUntilPresented: true), animated: true, completion: nil)
        }
        view.addSubview(tableView)
        unifiedLoadingBand.show(false, on: view)
    }

    func configureStatusLabel() {
        statusLabel =
            UILabel(
                frame: CGRect(
                    x: 24.0,
                    y: 34.0,
                    width:
                        view.bounds.size.width -
                        48.0,
                    height: 70.0
                )
            )

        statusLabel.autoresizingMask = [
            .flexibleWidth
        ]

        statusLabel.backgroundColor =
            UIColor.clear

        statusLabel.textAlignment =
            .center

        statusLabel.textColor =
            UIColor(
                white: 0.42,
                alpha: 1.0
            )

        statusLabel.font =
            UIFont.systemFont(
                ofSize: 13.0
            )

        statusLabel.numberOfLines = 3

        view.addSubview(statusLabel)
    }

    func positionHomeStatusBelowStories() {
        var frame = statusLabel.frame
        frame.origin.y = tableView.tableHeaderView === storyTray
            ? storyTray.bounds.height + 34.0 : 34.0
        statusLabel.frame = frame
    }

    func showStatus(
        _ text: String
    ) {
        if NoConnectionBanner.showIfHTTPZero(text, on: view) {
            statusLabel.text = nil
            statusLabel.isHidden = true
            return
        }
        NoConnectionBanner.hide(on: view)
        statusLabel.text = text
        positionHomeStatusBelowStories()
        statusLabel.isHidden = false
    }

    func hideStatus() {
        NoConnectionBanner.hide(on: view)
        statusLabel.isHidden = true
    }
}
