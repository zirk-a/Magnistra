// Overview: Explore: queue for loading grid images.
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


    func enqueueImage(
        for index: Int
    ) {
        if
            index < 0 ||
            index >= posts.count
        {
            return
        }

        let post =
            posts[index]

        let expectedGeneration =
            contentGeneration

        let localPath =
            post.imagePath

        let remoteURL =
            post.imageURL

        let stableKey =
            post.imageCacheKey

        imageQueue.addOperation {
            [weak self] in

            var image:
                UIImage? = nil

            if !localPath.isEmpty {
                image =
                    MagnistraGridFastDecode.image(contentsOfFile: localPath)
            }

            if
                image == nil,
                let materialized =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                remoteURL,
                            stableKey:
                                stableKey,
                            isAvatar:
                                false
                        )
            {
                image =
                    MagnistraGridFastDecode.image(contentsOfFile: materialized)
            }

            guard
                let ready =
                    image
            else {
                OperationQueue.main.addOperation { [weak self] in
                    self?.magnistraThumbnailLoadFailed(post.mediaID,
                                                       index: index,
                                                       generation: expectedGeneration)
                }
                if !remoteURL.isEmpty {
                    MagnistraConnectionRecovery.shared.noteFailedMedia(
                        key: "explore-grid:" + post.mediaID) { [weak self] in
                        guard let owner = self, owner.view.window != nil,
                              owner.contentGeneration == expectedGeneration,
                              index < owner.posts.count,
                              owner.posts[index].mediaID == post.mediaID else { return }
                        OperationQueue.main.addOperation { [weak owner] in
                            guard let owner = owner else { return }
                            owner.magnistraThumbnailRetryCount[post.mediaID] = 0
                            owner.magnistraThumbnailRetryNotBefore[post.mediaID] = 0.0
                            owner.magnistraViewportQueuedMediaIDs.remove(post.mediaID)
                            owner.magnistraLoadNearViewportImages()
                        }
                    }
                }
                return
            }

            OperationQueue.main
                .addOperation {
                    [weak self] in

                    guard
                        let self =
                            self,
                        expectedGeneration ==
                            self.contentGeneration,
                        index <
                            self.posts.count,
                        self.posts[index].mediaID == post.mediaID
                    else {
                        return
                    }

                    self.magnistraThumbnailRetryCount.removeValue(forKey: post.mediaID)
                    self.magnistraThumbnailRetryNotBefore.removeValue(forKey: post.mediaID)
                    self.removePlaceholder(
                        for: index
                    )

                    let tile =
                        MagnistraExploreTile(
                            frame: CGRect.zero
                        )

                    tile.postIndex =
                        index

                    tile.setImage(
                        ready,
                        for: .normal
                    )

                    let current =
                        self.posts[index]

                    MagnistraDecodedImageLoader
                        .shared
                        .storeGridPreview(
                            ready,
                            stableKey:
                                current.imageCacheKey
                        )

if current.videoURL != nil || (self.magnistraSavedGrid && current.isVideo) {
                        let overlay =
                            MagnistraExploreVideoCornerMark(
                                frame:
                                    CGRect(
                                        x: 6.0,
                                        y: 6.0,
                                        width: 14.0,
                                        height: 14.0
                                    )
                            )

                        tile.addSubview(
                            overlay
                        )
                    }

                    tile.addTarget(
                        self,
                        action:
                            #selector(
                                self.exploreTileTapped(
                                    _:
                                )
                            ),
                        for: .touchUpInside
                    )

                    self.tiles.append(
                        tile
                    )

                    self.scrollView.addSubview(
                        tile
                    )

                    self.layoutGrid()
                }
        }
    }
}
