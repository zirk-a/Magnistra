// Overview: Reels: rendering the visible window of pages.
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


    func renderWindow(
        center: Int
    ) {
        guard !posts.isEmpty else {
            return
        }

        let low =
            max(
                0,
                center - 1
            )

        let high =
            min(
                posts.count - 1,
                center + 1
            )

        var keep = Set<Int>()

        if low <= high {
            for index in low...high {
                keep.insert(index)

                if renderedPages[index] == nil {
                    createPage(
                        index: index
                    )
                }
            }
        }

        let old =
            Array(
                renderedPages.keys
            )

        for index in old {
            if !keep.contains(index) {
                renderedPages[index]?
                    .removeFromSuperview()

                renderedPages[index] = nil
            }
        }
    }

    func createPage(
        index: Int
    ) {
        guard
            index >= 0,
            index < posts.count
        else {
            return
        }

        let height =
            max(
                1.0,
                scrollView.bounds.size.height
            )

        let width =
            max(
                1.0,
                scrollView.bounds.size.width
            )

        let post = posts[index]

        let page =
            MagnistraReelPageView(
                frame:
                    CGRect(
                        x: 0.0,
                        y:
                            CGFloat(index) *
                            height,
                        width: width,
                        height: height
                    )
            )

        page.configure(post: post)

        page.surfaceButton.addTarget(
            self,
            action:
                #selector(
                    reelSurfaceTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        page.muteButton.addTarget(
            self,
            action:
                #selector(
                    reelMuteTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        page.postButton.addTarget(
            self,
            action:
                #selector(
                    reelPostTapped(
                        _:
                    )
                ),
            for:
                .touchUpInside
        )

        page.onZoomGestureActive = {
            [weak self] active in

            self?
                .scrollView
                .isScrollEnabled =
                    !active
        }

        scrollView.addSubview(page)
        renderedPages[index] = page

        loadPoster(
            post: post,
            into: page
        )
    }

    func loadPoster(
        post: MagnistraRealPost,
        into page:
            MagnistraReelPageView
    ) {
        if
            !post.imagePath.isEmpty,
            FileManager.default
                .fileExists(
                    atPath:
                        post.imagePath
                ),
            let image =
                UIImage(
                    contentsOfFile:
                        post.imagePath
                )
        {
            page.posterView.image = image
            return
        }

        let remote =
            post.imageURL

        guard
            !remote.isEmpty
        else {
            return
        }

        let mediaID = post.mediaID
        let stableKey = post.imageCacheKey

        imageQueue.addOperation {
            [weak page] in

            guard
                let path =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                remote,
                            stableKey:
                                stableKey,
                            isAvatar:
                                false
                        ),
                let image =
                    UIImage(
                        contentsOfFile:
                            path
                    )
            else {
                return
            }

            OperationQueue.main
                .addOperation {
                    [weak page] in

                    guard
                        let page = page,
                        page.mediaID ==
                            mediaID
                    else {
                        return
                    }

                    page.posterView.image = image
                }
        }
    }

    func postIndex(
        mediaID: String
    ) -> Int? {
        return posts.firstIndex {
            $0.mediaID == mediaID
        }
    }
}
