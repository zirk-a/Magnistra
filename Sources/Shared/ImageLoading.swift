// Overview: Decoded image loader with in-memory cache and grid previews.
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

final class MagnistraDecodedImageLoader: NSObject {
    private let gridPreviewCache =
        NSCache<NSString, UIImage>()

    private var postImageLoadsSuspended =
        false

    static let shared =
        MagnistraDecodedImageLoader()

    private let cache =
        NSCache<NSString, UIImage>()

    private let queue =
        OperationQueue()

    private override init() {
        super.init()

        cache.countLimit = 12
        cache.totalCostLimit =
            8 * 1024 * 1024

        queue.maxConcurrentOperationCount =
            2
    }

    func setPostImageLoadsSuspended(
        _ suspended: Bool
    ) {
        postImageLoadsSuspended =
            suspended
    }

    func storeGridPreview(
        _ image: UIImage,
        stableKey: String
    ) {
        guard
            !stableKey.isEmpty
        else {
            return
        }

        gridPreviewCache.countLimit =
            36

        gridPreviewCache.totalCostLimit =
            6 * 1024 * 1024

        let pixelsWide =
            max(
                1,
                Int(
                    image.size.width *
                    image.scale
                )
            )

        let pixelsHigh =
            max(
                1,
                Int(
                    image.size.height *
                    image.scale
                )
            )

        gridPreviewCache.setObject(
            image,
            forKey:
                stableKey as NSString,
            cost:
                pixelsWide *
                pixelsHigh *
                4
        )
    }

    func gridPreview(
        stableKey: String
    ) -> UIImage? {
        guard
            !stableKey.isEmpty
        else {
            return nil
        }

        return gridPreviewCache.object(
            forKey:
                stableKey as NSString
        )
    }

    func cachedImage(
        forKey key: String
    ) -> UIImage? {
        return cache.object(
            forKey:
                key as NSString
        )
    }

    func requestImage(
        path: String?,
        remoteURL: String?,
        stableKey: String,
        key: String,
        isAvatar: Bool,
        target: MagnistraPostCell
    ) {
        if let ready =
            cachedImage(
                forKey:
                    key
            )
        {
            target.applyDecodedImage(
                ready,
                key:
                    key,
                isAvatar:
                    isAvatar
            )
            return
        }

        if
            !isAvatar &&
            postImageLoadsSuspended
        {
            return
        }

        queue.addOperation {
            [weak self, weak target] in

            autoreleasepool {
                guard
                    let strongSelf =
                        self
                else {
                    return
                }

                var resolvedPath:
                    String? = nil

                var decodedLocalImage: UIImage? = nil

                if
                    let path =
                        path,
                    !path.isEmpty,
                    FileManager.default
                        .fileExists(
                            atPath:
                                path
                        ),
                    let localImage = strongSelf.forceDecodedImage(atPath: path)
                {
                    decodedLocalImage = localImage
                    resolvedPath = path
                }

                if
                    resolvedPath == nil,
                    let remoteURL =
                        remoteURL,
                    !remoteURL.isEmpty
                {
                    resolvedPath =
                        MagnistraHomeService
                            .materializeFeedImage(
                                url:
                                    remoteURL,
                                stableKey:
                                    stableKey,
                                isAvatar:
                                    isAvatar
                            )
                }

                guard
                    let finalPath =
                        resolvedPath,
                    let image = decodedLocalImage ?? strongSelf.forceDecodedImage(atPath: finalPath)
                else {
                    if remoteURL != nil {
                        MagnistraConnectionRecovery.shared.noteFailedMedia(
                            key: key) { [weak strongSelf, weak target] in
                            guard let owner = strongSelf,
                                  let cell = target, cell.window != nil else { return }
                            owner.requestImage(path: path, remoteURL: remoteURL,
                                stableKey: stableKey, key: key,
                                isAvatar: isAvatar, target: cell)
                        }
                    }
                    return
                }

                let pixelsWide =
                    max(
                        1,
                        Int(
                            image.size.width *
                            image.scale
                        )
                    )

                let pixelsHigh =
                    max(
                        1,
                        Int(
                            image.size.height *
                            image.scale
                        )
                    )

                let cost =
                    pixelsWide *
                    pixelsHigh *
                    4

                strongSelf.cache.setObject(
                    image,
                    forKey:
                        key as NSString,
                    cost:
                        cost
                )

                OperationQueue.main
                    .addOperation {
                        [weak target] in

                        target?
                            .applyDecodedImage(
                                image,
                                key:
                                    key,
                                isAvatar:
                                    isAvatar
                            )
                    }
            }
        }
    }

    private func forceDecodedImage(
        atPath path: String
    ) -> UIImage? {
        guard let source =
            UIImage(
                contentsOfFile: path
            )
        else {
            return nil
        }

        let size = source.size

        guard
            size.width > 0.0,
            size.height > 0.0
        else {
            return source
        }

        UIGraphicsBeginImageContextWithOptions(
            size,
            false,
            source.scale
        )

        source.draw(
            in: CGRect(
                x: 0.0,
                y: 0.0,
                width: size.width,
                height: size.height
            )
        )

        let decoded =
            UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return decoded ?? source
    }
}

