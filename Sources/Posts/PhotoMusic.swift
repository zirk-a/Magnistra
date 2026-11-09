// Overview: Photo music: button, image loader and player.
import Foundation
import UIKit
import AVFoundation

final class MagnistraPhotoMusicButton:
    UIButton
{
    var mediaID = ""
}

private func magnistraPhotoMusicDiagnostic(
    _ lines: [String]
) {
    _ = lines
}

final class MagnistraPhotoMusicImageLoader:
    NSObject
{
    static let shared =
        MagnistraPhotoMusicImageLoader()

    private let queue =
        OperationQueue()

    private let cache =
        NSCache<
            NSString,
            UIImage
        >()

    override init() {
        super.init()

        queue.maxConcurrentOperationCount =
            1

        cache.countLimit =
            6

        cache.totalCostLimit =
            6 * 1024 * 1024
    }

    func request(
        path: String?,
        remoteURL: String,
        fallbackURL: String?,
        stableKey: String,
        key: String,
        target: MagnistraPostCell
    ) {
        if let ready =
            cache.object(
                forKey:
                    key as NSString
            )
        {
            target
                .applyPhotoMusicImage(
                    ready,
                    key:
                        key
                )

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

                var sourceImage:
                    UIImage? = nil

                if
                    let localPath =
                        path,
                    !localPath.isEmpty
                {
                    sourceImage =
                        UIImage(
                            contentsOfFile:
                                localPath
                        )
                }

                var candidateURLs: [String] = []

                if !remoteURL.isEmpty {
                    candidateURLs.append(remoteURL)
                }

                if
                    let fallbackURL = fallbackURL,
                    !fallbackURL.isEmpty,
                    fallbackURL != remoteURL
                {
                    candidateURLs.append(fallbackURL)
                }

                if sourceImage == nil {
                    for candidateURL in candidateURLs {
                        guard
                            let data = MagnistraHomeService.photoMusicImageData(url: candidateURL),
                            let image = UIImage(data: data)
                        else {
                            continue
                        }
                        sourceImage = image
                        break
                    }
                }

                if sourceImage == nil {
                    for candidateURL in candidateURLs {
                        guard
                            let fallbackPath = MagnistraHomeService.materializeFeedImage(
                                url: candidateURL,
                                stableKey: stableKey,
                                isAvatar: false
                            ),
                            let image = UIImage(contentsOfFile: fallbackPath)
                        else {
                            continue
                        }
                        sourceImage = image
                        break
                    }
                }

                guard
                    let source = sourceImage,
                    let decoded = strongSelf.decodedImage(
                        source,
                        maximumDimension: 640.0
                    )
                else {
                    OperationQueue.main.addOperation {
                        [weak target] in
                        target?.applyPhotoMusicImageFailure(key: key)
                    }
                    return
                }

                let pixelsWide =
                    max(
                        1,
                        Int(
                            decoded.size.width *
                            decoded.scale
                        )
                    )

                let pixelsHigh =
                    max(
                        1,
                        Int(
                            decoded.size.height *
                            decoded.scale
                        )
                    )

                strongSelf.cache.setObject(
                    decoded,
                    forKey:
                        key as NSString,
                    cost:
                        pixelsWide *
                        pixelsHigh *
                        4
                )

                OperationQueue.main
                    .addOperation {
                        [weak target] in

                        target?
                            .applyPhotoMusicImage(
                                decoded,
                                key:
                                    key
                            )
                    }
            }
        }
    }

    private func decodedImage(
        _ image: UIImage,
        maximumDimension: CGFloat
    ) -> UIImage? {
        let sourceSize =
            image.size

        guard
            sourceSize.width > 0.0,
            sourceSize.height > 0.0
        else {
            return nil
        }

        let longest =
            max(
                sourceSize.width,
                sourceSize.height
            )

        let scale =
            min(
                1.0,
                maximumDimension /
                max(
                    1.0,
                    longest
                )
            )

        let targetSize =
            CGSize(
                width:
                    max(
                        1.0,
                        floor(
                            sourceSize.width *
                            scale
                        )
                    ),
                height:
                    max(
                        1.0,
                        floor(
                            sourceSize.height *
                            scale
                        )
                    )
            )

        UIGraphicsBeginImageContextWithOptions(
            targetSize,
            true,
            1.0
        )

        image.draw(
            in:
                CGRect(
                    x: 0.0,
                    y: 0.0,
                    width:
                        targetSize.width,
                    height:
                        targetSize.height
                )
        )

        let decoded =
            UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return decoded
    }
}

final class MagnistraPhotoMusicPlayer:
    NSObject
{
    static let shared =
        MagnistraPhotoMusicPlayer()

    private var player:
        AVPlayer? = nil

    private var observedItem:
        AVPlayerItem? = nil

    private(set) var activeMediaID:
        String? = nil

    private var pendingScrollStopMediaID:
        String? = nil

    private var pendingStartTimeMs = 0
    private var waitingForReady = false
    private var readyPollCount = 0

    var onStopped:
        ((String) -> Void)? = nil

    var isPlaying: Bool {
        return
            (player?.rate ?? 0.0) >
            0.01
    }

    func toggle(
        post: MagnistraRealPost
    ) -> Bool {
        guard
            post.videoURL == nil,
            post.musicAudioURL != nil
        else {
            return false
        }

        if
            activeMediaID ==
                post.mediaID,
            let player =
                player
        {
            if waitingForReady {
                return true
            }

            if player.rate > 0.01 {
                player.pause()
                return false
            }

            player.play()
            return true
        }

        return start(
            post:
                post
        )
    }

    @discardableResult
    func start(
        post: MagnistraRealPost
    ) -> Bool {
        guard
            post.videoURL == nil,
            post.musicAudioURL != nil
        else {
            return false
        }

        stop()

        guard
            let localURL =
                try? MagnistraHomeService
                    .localPhotoMusicPlaybackURL(
                        for:
                            post
                    )
        else {
            return false
        }

        let item =
            AVPlayerItem(
                url:
                    localURL
            )

        let newPlayer =
            AVPlayer(
                playerItem:
                    item
            )

        player =
            newPlayer

        observedItem =
            item

        activeMediaID =
            post.mediaID

        NotificationCenter.default
            .addObserver(
                self,
                selector:
                    #selector(
                        itemDidFinish(
                            _:
                        )
                    ),
                name:
                    .AVPlayerItemDidPlayToEndTime,
                object:
                    item
            )

        pendingStartTimeMs =
            max(
                0,
                post.musicStartTimeMs
            )

        waitingForReady = true
        readyPollCount = 0

        magnistraPhotoMusicDiagnostic(
            [
                "PHOTO_MUSIC_TAP=YES",
                "LOCAL_PROXY_URL=YES",
                "PLAYER_CREATED=YES",
                "INITIAL_SEEK=DEFERRED_UNTIL_READY",
                "START_OFFSET_PRESENT=" +
                    (
                        pendingStartTimeMs > 0
                            ? "YES"
                            : "NO"
                    )
            ]
        )

        NSObject.cancelPreviousPerformRequests(
            withTarget:
                self
        )

        perform(
            #selector(
                beginPlaybackWhenReady
            ),
            with:
                nil,
            afterDelay:
                0.05
        )

        return true
    }

    func suspendForScrollIfMediaID(
        _ mediaID:
            String
    ) {
        if
            pendingScrollStopMediaID ==
                mediaID
        {
            return
        }

        guard
            activeMediaID ==
                mediaID
        else {
            return
        }

        NSObject
            .cancelPreviousPerformRequests(
                withTarget:
                    self
            )

        waitingForReady = false
        readyPollCount = 0
        pendingStartTimeMs = 0

        player?.pause()

        pendingScrollStopMediaID =
            mediaID

        activeMediaID =
            nil
    }

    func cancelScheduledScrollStopFinish() {

        guard pendingScrollStopMediaID != nil else { return }
        NSObject
            .cancelPreviousPerformRequests(
                withTarget:
                    self,
                selector:
                    #selector(
                        runScheduledScrollStopFinish
                    ),
                object:
                    nil
            )
    }

    func scheduleScrollStopFinish() {
        guard
            pendingScrollStopMediaID !=
                nil
        else {
            return
        }

        cancelScheduledScrollStopFinish()

        perform(
            #selector(
                runScheduledScrollStopFinish
            ),
            with:
                nil,
            afterDelay:
                0.35
        )
    }

    @objc private func runScheduledScrollStopFinish() {
        finishScrollStop()
    }

    func finishScrollStop() {
        guard
            pendingScrollStopMediaID !=
                nil
        else {
            return
        }

        stop()
    }

    func stopIfMediaID(
        _ mediaID: String
    ) {
        guard
            activeMediaID ==
                mediaID
        else {
            return
        }

        stop()
    }

    func stop() {
        let stoppedMediaID =
            activeMediaID ??
            pendingScrollStopMediaID

        NSObject.cancelPreviousPerformRequests(
            withTarget:
                self
        )

        waitingForReady = false
        readyPollCount = 0
        pendingStartTimeMs = 0

        if let item =
            observedItem
        {
            NotificationCenter.default
                .removeObserver(
                    self,
                    name:
                        .AVPlayerItemDidPlayToEndTime,
                    object:
                        item
                )
        }

        player?.pause()

        player?
            .replaceCurrentItem(
                with:
                    nil
            )

        if stoppedMediaID != nil {
            StreamProxy
                .shared
                .closeCurrentStream()
        }

        player = nil
        observedItem = nil
        activeMediaID = nil
        pendingScrollStopMediaID = nil

        if let stoppedMediaID = stoppedMediaID {
            onStopped?(
                stoppedMediaID
            )
        }
    }

    @objc private func beginPlaybackWhenReady() {
        guard
            let item = observedItem,
            let player = player
        else {
            waitingForReady = false
            return
        }

        switch item.status {
        case .readyToPlay:
            waitingForReady = false

            let shouldSeek =
                pendingStartTimeMs > 0

            if shouldSeek {
                let seconds =
                    Double(
                        pendingStartTimeMs
                    ) /
                    1000.0

                player.seek(
                    to:
                        CMTimeMakeWithSeconds(
                            seconds,
                            preferredTimescale:
                                600
                        )
                )
            }

            player.play()

            magnistraPhotoMusicDiagnostic(
                [
                    "STATUS_CHECK=READY_BEFORE_PLAY",
                    "READY_GATED_START=YES",
                    "SEEK_APPLIED=" +
                        (
                            shouldSeek
                                ? "YES"
                                : "NO"
                        )
                ]
            )

            NSObject.cancelPreviousPerformRequests(
                withTarget:
                    self
            )

            perform(
                #selector(
                    diagnosticStatusCheck
                ),
                with:
                    nil,
                afterDelay:
                    1.0
            )

        case .failed:
            waitingForReady = false

            magnistraPhotoMusicDiagnostic(
                [
                    "STATUS_CHECK=FAILED_BEFORE_PLAY",
                    "READY_GATED_START=NO"
                ]
            )

            stop()

        case .unknown:
            readyPollCount += 1

            if readyPollCount >= 80 {
                waitingForReady = false

                magnistraPhotoMusicDiagnostic(
                    [
                        "STATUS_CHECK=READY_TIMEOUT",
                        "READY_GATED_START=NO"
                    ]
                )

                stop()
                return
            }

            perform(
                #selector(
                    beginPlaybackWhenReady
                ),
                with:
                    nil,
                afterDelay:
                    0.10
            )

        @unknown default:
            waitingForReady = false

            magnistraPhotoMusicDiagnostic(
                [
                    "STATUS_CHECK=OTHER_BEFORE_PLAY",
                    "READY_GATED_START=NO"
                ]
            )

            stop()
        }
    }

    @objc private func diagnosticStatusCheck() {
        guard
            let item =
                observedItem,
            let player =
                player
        else {
            magnistraPhotoMusicDiagnostic(
                [
                    "STATUS_CHECK=NO_ACTIVE_PLAYER"
                ]
            )

            return
        }

        let statusText:
            String

        switch item.status {
        case .unknown:
            statusText =
                "UNKNOWN"
        case .readyToPlay:
            statusText =
                "READY"
        case .failed:
            statusText =
                "FAILED"
        @unknown default:
            statusText =
                "OTHER"
        }

        magnistraPhotoMusicDiagnostic(
            [
                "STATUS_CHECK=YES",
                "ITEM_STATUS=" +
                    statusText,
                "PLAYER_RATE_POSITIVE=" +
                    (
                        player.rate > 0.01
                            ? "YES"
                            : "NO"
                    ),
                "ITEM_ERROR_PRESENT=" +
                    (
                        item.error == nil
                            ? "NO"
                            : "YES"
                    )
            ]
        )
    }

    @objc private func itemDidFinish(
        _ note: Notification
    ) {
        guard
            let mediaID = activeMediaID,
            let player = player,
            let item = observedItem
        else {
            return
        }

        let startTimeMs = max(0, pendingStartTimeMs)
        let targetTime: CMTime

        if startTimeMs > 0 {
            targetTime = CMTimeMakeWithSeconds(
                Double(startTimeMs) / 1000.0,
                preferredTimescale: 600
            )
        } else {
            targetTime = CMTime.zero
        }

        player.seek(
            to: targetTime,
            toleranceBefore: CMTime.zero,
            toleranceAfter: CMTime.zero
        ) {
            [weak self, weak player, weak item] finished in
            guard
                finished,
                let self = self,
                let replayPlayer = player,
                let replayItem = item,
                self.player === replayPlayer,
                self.observedItem === replayItem,
                self.activeMediaID == mediaID
            else {
                return
            }

            replayPlayer.play()
        }
    }
}
