// Overview: Explore tab: small helpers (retry thumbnails, saved grid, return to top).
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

extension ExploreViewController {


    @objc func magnistraRetryVisibleThumbnails() {
        magnistraLoadNearViewportImages()
    }

    func magnistraThumbnailLoadFailed(_ mediaID: String,
                                              index: Int,
                                              generation: Int) {
        guard generation == contentGeneration,
              index >= 0, index < posts.count,
              posts[index].mediaID == mediaID else { return }
        magnistraViewportQueuedMediaIDs.remove(mediaID)
        let failures = (magnistraThumbnailRetryCount[mediaID] ?? 0) + 1
        magnistraThumbnailRetryCount[mediaID] = failures
        if failures <= 3 {
            let delay = Double(failures) * 4.0
            magnistraThumbnailRetryNotBefore[mediaID] =
                Date().timeIntervalSince1970 + delay
            perform(#selector(magnistraRetryVisibleThumbnails),
                    with: nil, afterDelay: delay + 0.1)
        }
        NSLog("MAGNISTRA_EXPLORE_THUMB_FAIL retry=%ld", failures)
    }

    func magnistraPrepareSavedGrid() { magnistraSavedGrid = true }

    func magnistraReturnToTop() {
        rootTabHeaderScroll.revealForTabReturn()
        let y = -scrollView.contentInset.top
        scrollView.setContentOffset(CGPoint(x: 0.0, y: y), animated: true)
    }
}
