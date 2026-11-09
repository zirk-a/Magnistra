// Overview: Explore: taps (reels, refresh, tiles) and opening posts from the grid.
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


    @objc func reelsTapped() {
        MagnistraInlineVideoPlayer
            .shared
            .stop()

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        let controller =
            MagnistraReelsViewController()

        controller.hidesBottomBarWhenPushed =
            true

        navigationController?
            .pushViewController(
                controller,
                animated:
                    true
            )
    }

    @objc func refreshTapped() {
        MagnistraPostCell.resetTransientFollowConfirmation()
        guard
            !isLoadingPage
        else {
            return
        }

        navigationItem
            .rightBarButtonItem?
            .isEnabled =
                false

        pullRefreshIndicator.begin(on: navigationItem, label: "Updating Explore")

        MagnistraInlineVideoPlayer
            .shared
            .stop()

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        preservingGridDuringPullRefresh = !posts.isEmpty
        if !preservingGridDuringPullRefresh {

            imageQueue.cancelAllOperations()
            contentGeneration += 1
            nextMaxID = nil
            reachedEnd = false
            seenMediaIDs.removeAll(keepingCapacity: true)
            posts.removeAll(keepingCapacity: true)
            for tile in tiles { tile.removeFromSuperview() }
            tiles.removeAll(keepingCapacity: true)
            statusLabel.text = nil
            installInitialPlaceholders()
        }

        requestPage(
            maxID:
                nil,
            replacing:
                true
        )
    }

    @objc func exploreTileTapped(
        _ sender:
            MagnistraExploreTile
    ) {
        let index =
            sender.postIndex

        if
            index < 0 ||
            index >= posts.count
        {
            return
        }

        let selectedPost = posts[index]
        if magnistraSavedGrid {
            guard !magnistraSavedOpenPending,
                  navigationController?.topViewController === self else { return }
            magnistraSavedOpenPending = true
        }
        let preview = sender.image(for: .normal)
        if magnistraSavedGrid && MagnistraProfileMediaOpeningGate.needsDetails(selectedPost) {
            let generation = contentGeneration
            MagnistraProfileMediaOpeningGate.open(selectedPost) { [weak self] ready in
                guard let self = self else { return }
                guard self.contentGeneration == generation,
                      index < self.posts.count,
                      self.posts[index].mediaID == selectedPost.mediaID else {
                    self.magnistraSavedOpenPending = false
                    return
                }
                guard let ready = ready else {
                    self.magnistraSavedOpenPending = false
                    MagnistraProfileMediaOpeningGate.showUnavailable()
                    return
                }
                self.posts[index] = ready
                self.openExploreGridPost(index: index, preview: preview)
            }
            return
        }
        openExploreGridPost(index: index, preview: preview)
    }

    func openExploreGridPost(index: Int, preview: UIImage?) {
        guard index >= 0 && index < posts.count else {
            if magnistraSavedGrid { magnistraSavedOpenPending = false }
            return
        }
        if magnistraSavedGrid && !(navigationController?.topViewController === self) {
            magnistraSavedOpenPending = false
            return
        }
        let selectedPost = posts[index]
        if
            let preview = preview
        {
            MagnistraDecodedImageLoader
                .shared
                .storeGridPreview(
                    preview,
                    stableKey:
                        selectedPost.imageCacheKey
                )
        }

let snapshot =
            posts

        let tailStart =
            index + 1

        let controller =
            MagnistraExploreFeedViewController(
                selectedPost:
                    selectedPost,
                deferredPostsProvider: {
                    if
                        tailStart >=
                        snapshot.count
                    {
                        return []
                    }

                    return Array(
                        snapshot[
                            tailStart..<snapshot.count
                        ]
                    )
                },
                nextMaxID:
                    nextMaxID,
                reachedEnd:
                    reachedEnd
            )

        if magnistraSavedGrid {
            controller.magnistraUseSavedFeed()
            controller.title = "Saved"
        }
        navigationController?
            .pushViewController(
                controller,
                animated: true
            )
    }
}
