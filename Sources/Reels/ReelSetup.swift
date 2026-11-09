// Overview: Reels: setup, position save/restore and content geometry.
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

extension MagnistraReelsViewController {


    func magnistraSaveReelsPosition() {
        guard !posts.isEmpty else { return }

        let from = max(0, posts.count - 120)
        MagnistraReelsWarmState.posts = Array(posts[from..<posts.count])
        MagnistraReelsWarmState.index =
            max(0, min(currentIndex - from, MagnistraReelsWarmState.posts.count - 1))
        MagnistraReelsWarmState.cursor = nextMaxID
        MagnistraReelsWarmState.exhausted = reachedEnd
        MagnistraReelsWarmState.updatedAt = Date().timeIntervalSince1970
        NSLog("MAGNISTRA_REELS_WARM_SAVE index=%ld count=%ld",
              MagnistraReelsWarmState.index, MagnistraReelsWarmState.posts.count)
    }

    func magnistraRestoreReelsPosition() -> Bool {
        let cache = MagnistraReelsWarmState.posts
        guard !cache.isEmpty,
              Date().timeIntervalSince1970 - MagnistraReelsWarmState.updatedAt < 7200.0
        else { return false }
        posts = cache
        seenMediaIDs = Set(cache.map { $0.mediaID })
        nextMaxID = MagnistraReelsWarmState.cursor
        reachedEnd = MagnistraReelsWarmState.exhausted
        currentIndex = max(0, min(MagnistraReelsWarmState.index, cache.count - 1))
        initialContinuationBudget = 0
        isLoading = false
        loadingLabel.isHidden = true
        updateContentGeometry(preserveIndex: true)
        renderWindow(center: currentIndex)
        NSLog("MAGNISTRA_REELS_WARM_RESTORE index=%ld count=%ld", currentIndex, posts.count)
        return true
    }

    func magnistraReelsKeepVisualAboveExploreTopbar() {

        guard isMovingFromParent || magnistraReelsOpeningPostTransition,
              let nav = hostNavigationController ?? navigationController else { return }
        let navRoot: UIView = nav.view
        let bar = nav.navigationBar

        var barBranch: UIView = bar
        while let parent = barBranch.superview, parent !== navRoot {
            barBranch = parent
        }
        guard barBranch.superview === navRoot else { return }
        var surface: UIView = view
        while let parent = surface.superview, parent !== navRoot {
            surface = parent
        }
        guard surface.superview === navRoot,
              surface !== barBranch else { return }
        magnistraReelsPopTopLayer = surface
        magnistraReelsPopOriginalZ = surface.layer.zPosition
        surface.layer.zPosition = max(surface.layer.zPosition,
                                      barBranch.layer.zPosition) + 1.0
    }

    func magnistraReelsRestoreNormalVisualOrder() {
        if let surface = magnistraReelsPopTopLayer {
            surface.layer.zPosition = magnistraReelsPopOriginalZ
        }
        magnistraReelsPopTopLayer = nil
    }

    func updateContentGeometry(
        preserveIndex: Bool
    ) {
        let width =
            max(
                1.0,
                scrollView.bounds.size.width
            )

        let height =
            max(
                1.0,
                scrollView.bounds.size.height
            )

        scrollView.contentSize =
            CGSize(
                width: width,
                height:
                    height *
                    CGFloat(posts.count)
            )

        bottomLoadingLabel.frame = CGRect(
            x: 0.0,
            y: scrollView.contentSize.height + 8.0,
            width: width,
            height: 25.0
        )

        for (index, page) in renderedPages {
            page.frame =
                CGRect(
                    x: 0.0,
                    y:
                        CGFloat(index) *
                        height,
                    width: width,
                    height: height
                )
        }

        if preserveIndex && !posts.isEmpty {
            scrollView.contentOffset =
                CGPoint(
                    x: 0.0,
                    y:
                        CGFloat(currentIndex) *
                        height
                )
        }
    }
}
