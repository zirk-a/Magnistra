// Overview: Inline video player with health checks and recovery.
import Foundation
import UIKit
import Security
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration



final class MagnistraInlineVideoPlayer:
    NSObject
{
    var pendingScrollStopMediaID:
        String? = nil

    static let shared =
        MagnistraInlineVideoPlayer()

    private let streamProxy:
        StreamProxy

    init(
        streamProxy:
            StreamProxy =
                StreamProxy.shared
    ) {
        self.streamProxy =
            streamProxy

        super.init()
        NotificationCenter.default.addObserver(self,
            selector: #selector(recoverOnConnectivityReturn),
            name: MagnistraConnectionRecovery.recoveredNotification,
            object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(videoAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }

    deinit {
        videoHealthTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private var recoveryPost: MagnistraRealPost? = nil
    private var wantsPlaybackAfterNetworkReturn = false

    private var videoHealthTimer: Timer? = nil
    private var lastHealthSeconds: Double? = nil
    private var healthStagnantTicks = 0
    private var healthHasPlayed = false
    private var healthObservedStall = false
    private var healthRecoveryMediaID: String? = nil
    private var healthRecoveryAttempts = 0
    private var healthRestartInProgress = false

    private func resetVideoHealth(mediaID: String) {
        if healthRecoveryMediaID != mediaID {
            healthRecoveryMediaID = mediaID
            healthRecoveryAttempts = 0
        }
        lastHealthSeconds = nil
        healthStagnantTicks = 0
        healthHasPlayed = false
        healthObservedStall = false
        videoHealthTimer?.invalidate()

        videoHealthTimer = Timer.scheduledTimer(
            timeInterval: 4.0, target: self,
            selector: #selector(checkVideoHealth), userInfo: nil, repeats: true)
    }

    @objc private func videoAppBecameActive() {

        lastHealthSeconds = nil
        healthStagnantTicks = 0
        guard wantsPlaybackAfterNetworkReturn else { return }
        player?.play()
    }

    @objc private func checkVideoHealth() {
        guard UIApplication.shared.applicationState == .active,
              wantsPlaybackAfterNetworkReturn,
              !healthRestartInProgress,
              let id = activeMediaID,
              let current = player,
              let item = observedItem,
              current.currentItem === item,
              (hostView?.window != nil || fullscreenOverlay != nil) else {
            lastHealthSeconds = nil
            healthStagnantTicks = 0
            return
        }
        if item.status == .failed {
            restartFailedVideoOnce(mediaID: id)
            return
        }
        let value = currentPlaybackSeconds(mediaID: id) ?? 0.0
        if let previous = lastHealthSeconds {
            if value > previous + 0.15 || value + 0.5 < previous {
                healthHasPlayed = true
                healthStagnantTicks = 0
                healthObservedStall = false
            } else {
                healthStagnantTicks += 1
            }
        }
        lastHealthSeconds = value

        let limit = healthObservedStall ? 3 : (healthHasPlayed ? 3 : 6)
        if healthStagnantTicks >= limit {
            restartFailedVideoOnce(mediaID: id)
        }
    }

    private func restartFailedVideoOnce(mediaID: String) {
        guard !healthRestartInProgress,
              healthRecoveryAttempts < 1,
              activeMediaID == mediaID,
              let post = recoveryPost,
              let host = hostView,
              host.window != nil else { return }
        healthRecoveryAttempts += 1
        healthRestartInProgress = true
        let wasFullscreen = fullscreenOverlay != nil
        let wasMuted = isMuted
        let seconds = currentPlaybackSeconds(mediaID: mediaID) ?? 0.0

        if wasFullscreen { exitFullscreen() }
        let started = start(post: post, hostView: host, frame: inlineFrame)
        if started {
            if wasMuted { _ = toggleMuted() }
            if seconds.isFinite && seconds > 1.0 {
                _ = seekActive(mediaID: mediaID, seconds: seconds)
            }
            if wasFullscreen { _ = enterFullscreen() }
        }
        healthRestartInProgress = false
    }

    @objc private func recoverOnConnectivityReturn() {
        guard wantsPlaybackAfterNetworkReturn, activeMediaID != nil else { return }
        if player?.currentItem?.status == .failed,
           fullscreenOverlay == nil,
           let post = recoveryPost, let host = hostView {
            let oldMute = isMuted
            if start(post: post, hostView: host, frame: inlineFrame) && oldMute {
                _ = toggleMuted()
            }
            return
        }

        player?.play()
    }

    @objc private func observedStreamInterrupted(_ notification: Notification) {
        if !Thread.isMainThread {
            OperationQueue.main.addOperation { [weak self] in
                self?.observedStreamInterrupted(notification)
            }
            return
        }
        guard wantsPlaybackAfterNetworkReturn,
              let key = activeMediaID,
              let item = observedItem,
              notification.object as AnyObject? === item else { return }
        healthObservedStall = true
        MagnistraConnectionRecovery.shared.noteFailedMedia(
            key: "video:" + key) { [weak self] in
                self?.recoverOnConnectivityReturn()
            }
    }

    private var player:
        AVPlayer? = nil

    private var playerLayer:
        AVPlayerLayer? = nil

    private var hostView:
        UIView? = nil

    private var inlineFrame =
        CGRect.zero

    private var fullscreenOverlay:
        MagnistraFullscreenVideoOverlay? = nil

    private var fullscreenStatusBarWasHidden:
        Bool? = nil

    private var observedItem:
        AVPlayerItem? = nil

    private var preparedReelMediaID: String? = nil
    private var preparedReelAsset: AVURLAsset? = nil

    func clearPreparedReel() {
        preparedReelAsset?.cancelLoading()
        preparedReelAsset = nil
        preparedReelMediaID = nil
    }

    func prepareNextReel(post: MagnistraRealPost) {
        guard activeMediaID != nil,
              activeMediaID != post.mediaID,
              post.videoURL != nil else { return }

        if preparedReelMediaID == post.mediaID &&
           preparedReelAsset != nil { return }

        clearPreparedReel()

        guard let localURL = try? MagnistraHomeService
            .localVideoPlaybackURL(
                for: post,
                proxy: streamProxy,
                prepareForNextReel: true
            ) else { return }

        let asset = AVURLAsset(url: localURL)
        preparedReelMediaID = post.mediaID
        preparedReelAsset = asset

        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            [weak self] in
            OperationQueue.main.addOperation {
                [weak self] in
                guard let self = self,
                      self.preparedReelAsset === asset else { return }
                var error: NSError? = nil
                let status = asset.statusOfValue(
                    forKey: "playable", error: &error
                )
                if status == .failed || status == .cancelled {
                    self.clearPreparedReel()
                }
            }
        }
    }

    private(set) var activeMediaID:
        String? = nil

    private(set) var isMuted =
        false

    var onStopped:
        ((String) -> Void)? = nil

    var isPlaying: Bool {
        return
            (player?.rate ?? 0.0) >
            0.01
    }

    func prepare(
        hostView: UIView,
        mediaID: String
    ) {
        guard
            let active = activeMediaID
        else {
            return
        }

        if
            self.hostView === hostView &&
            active != mediaID
        {
            stop()
        }
    }

    func start(
        post: MagnistraRealPost,
        hostView: UIView,
        frame: CGRect
    ) -> Bool {
        guard
            post.videoURL != nil
        else {
            return false
        }

        let warmedAsset: AVURLAsset?
        if preparedReelMediaID == post.mediaID,
           let asset = preparedReelAsset {
            var error: NSError? = nil
            let status = asset.statusOfValue(
                forKey: "playable", error: &error
            )
            warmedAsset = (status == .failed || status == .cancelled)
                ? nil : asset
            preparedReelAsset = nil
            preparedReelMediaID = nil
        } else {
            clearPreparedReel()
            warmedAsset = nil
        }

        stop()

        let item: AVPlayerItem
        if let asset = warmedAsset {
            item = AVPlayerItem(asset: asset)
        } else {
            guard let localURL = try? MagnistraHomeService
                .localVideoPlaybackURL(for: post, proxy: streamProxy)
            else { return false }
            item = AVPlayerItem(url: localURL)
        }

        let newPlayer =
            AVPlayer(
                playerItem: item
            )

        let newLayer =
            AVPlayerLayer(
                player: newPlayer
            )

        newLayer.frame = frame

        newLayer.videoGravity =
            AVLayerVideoGravity
                .resizeAspect

        newLayer.backgroundColor =
            UIColor.black.cgColor

        hostView.layer
            .addSublayer(newLayer)

        player = newPlayer
        playerLayer = newLayer
        self.hostView = hostView
        inlineFrame = frame
        activeMediaID = post.mediaID
        recoveryPost = post
        wantsPlaybackAfterNetworkReturn = true
        isMuted = false
        observedItem = item
        resetVideoHealth(mediaID: post.mediaID)

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

        NotificationCenter.default.addObserver(self,
            selector: #selector(observedStreamInterrupted(_:)),
            name: Notification.Name("AVPlayerItemPlaybackStalledNotification"),
            object: item)
        NotificationCenter.default.addObserver(self,
            selector: #selector(observedStreamInterrupted(_:)),
            name: Notification.Name("AVPlayerItemFailedToPlayToEndTimeNotification"),
            object: item)
        newPlayer.play()

        return true
    }

    func currentPlaybackSeconds(
        mediaID: String
    ) -> Double? {
        guard
            activeMediaID ==
                mediaID,
            let player =
                player
        else {
            return nil
        }

        let time =
            player.currentTime()

        guard
            time.timescale != 0
        else {
            return nil
        }

        return
            Double(
                time.value
            ) /
            Double(
                time.timescale
            )
    }

    @discardableResult
    func pauseIfMediaID(
        _ mediaID: String
    ) -> Bool {
        guard
            activeMediaID ==
                mediaID,
            let player =
                player
        else {
            return false
        }

        wantsPlaybackAfterNetworkReturn = false
        healthStagnantTicks = 0
        lastHealthSeconds = nil
        player.pause()
        return true
    }

    @discardableResult
    func resumeIfMediaID(
        _ mediaID: String
    ) -> Bool {
        guard
            activeMediaID ==
                mediaID,
            let player =
                player
        else {
            return false
        }

        wantsPlaybackAfterNetworkReturn = true
        player.play()
        return true
    }

    @discardableResult
    func reattachActive(
        mediaID: String,
        hostView: UIView,
        frame: CGRect
    ) -> Bool {
        guard
            activeMediaID ==
                mediaID,
            let layer =
                playerLayer
        else {
            return false
        }

        layer.removeFromSuperlayer()
        layer.frame = frame

        hostView.layer
            .addSublayer(
                layer
            )

        self.hostView =
            hostView

        inlineFrame =
            frame

        return true
    }

    @discardableResult
    func seekActive(
        mediaID: String,
        seconds: Double
    ) -> Bool {
        guard
            activeMediaID ==
                mediaID,
            let player =
                player,
            seconds.isFinite,
            seconds >= 0.0
        else {
            return false
        }

        player.seek(
            to:
                CMTimeMakeWithSeconds(
                    seconds,
                    preferredTimescale:
                        600
                )
        )

        return true
    }

    func hasPlaybackProgress(
        mediaID: String
    ) -> Bool {
        guard
            activeMediaID ==
                mediaID,
            let player =
                player
        else {
            return false
        }

        let time =
            player.currentTime()

        guard
            time.timescale !=
                0
        else {
            return false
        }

        return time.value >
            0
    }

    func toggle(
        mediaID: String
    ) -> Bool? {
        guard
            mediaID == activeMediaID,
            let player = player
        else {
            return nil
        }

        if player.rate > 0.01 {
            wantsPlaybackAfterNetworkReturn = false
            healthStagnantTicks = 0
            lastHealthSeconds = nil
            player.pause()
            return false
        }

        wantsPlaybackAfterNetworkReturn = true
        player.play()
        return true
    }

    func toggleMuted()
        -> Bool?
    {
        guard
            let item =
                player?.currentItem
        else {
            return nil
        }

        let nextMuted =
            !isMuted

        let tracks =
            item.asset
                .tracks(
                    withMediaType:
                        .audio
                )

        var parameters:
            [AVAudioMixInputParameters] = []

        for track in tracks {
            let input =
                AVMutableAudioMixInputParameters(
                    track: track
                )

            input.setVolume(
                nextMuted
                    ? 0.0
                    : 1.0,
                at:
                    CMTime.zero
            )

            parameters.append(input)
        }

        let mix =
            AVMutableAudioMix()

        mix.inputParameters =
            parameters

        item.audioMix =
            mix

        isMuted =
            nextMuted

        fullscreenOverlay?
            .setMuted(
                nextMuted
            )

        return nextMuted
    }

    func setCarouselFullscreenRotation(mediaID: String,
                                      hostView: UIView, rotated: Bool) {
        guard activeMediaID == mediaID, self.hostView === hostView,
              let layer = playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = hostView.bounds
        layer.bounds = CGRect(x: 0, y: 0,
            width: rotated ? bounds.height : bounds.width,
            height: rotated ? bounds.width : bounds.height)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.setAffineTransform(CGAffineTransform(
            rotationAngle: rotated ? CGFloat.pi / 2.0 : 0))
        CATransaction.commit()
    }

    func moveCarouselVideo(mediaID: String, hostView: UIView,
                           frame: CGRect) -> Bool {
        guard activeMediaID == mediaID,
              player != nil,
              let layer = playerLayer else { return false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeFromSuperlayer()
        layer.setAffineTransform(CGAffineTransform.identity)
        layer.frame = frame
        hostView.layer.addSublayer(layer)
        CATransaction.commit()
        self.hostView = hostView
        inlineFrame = frame
        return true
    }

    func enterFullscreen()
        -> Bool
    {
        guard
            fullscreenOverlay == nil,
            let layer =
                playerLayer
        else {
            return false
        }

        let app =
            UIApplication.shared

        guard
            let window =
                app.keyWindow ??
                app.windows.first
        else {
            return false
        }

        fullscreenStatusBarWasHidden =
            app.isStatusBarHidden

        app.setStatusBarHidden(
            true,
            with:
                .fade
        )
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": true])

        let overlay =
            MagnistraFullscreenVideoOverlay(
                frame:
                    window.bounds
            )

        overlay.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        overlay.videoLayer =
            layer

        overlay.onClose = {
            [weak self] in
            self?.exitFullscreen()
        }

        overlay.onMute = {
            [weak self] in
            return
                self?
                    .toggleMuted()
                ?? false
        }

        layer.removeFromSuperlayer()

        overlay.layer
            .insertSublayer(
                layer,
                at: 0
            )

        layer.frame =
            overlay.bounds

        overlay.setMuted(
            isMuted
        )

        window.addSubview(overlay)

        fullscreenOverlay =
            overlay

        overlay.setNeedsLayout()

        player?.play()

        return true
    }

    func exitFullscreen() {
        guard
            let overlay =
                fullscreenOverlay
        else {
            return
        }

        overlay.resetVideoZoom()

        playerLayer?
            .setAffineTransform(CGAffineTransform.identity)

        playerLayer?
            .removeFromSuperlayer()

        overlay.cancelAutoHide()

        overlay.removeFromSuperview()

        fullscreenOverlay =
            nil

        restoreStatusBarAfterFullscreen()

        if
            let host =
                hostView,
            let layer =
                playerLayer,
            host.window != nil
        {
            layer.frame =
                inlineFrame

            host.layer
                .addSublayer(layer)

            let inlineControlTags = [
                MagnistraVideoUITags.surface,
                MagnistraVideoUITags.status,
                MagnistraVideoUITags.mute,
                MagnistraVideoUITags.fullscreen
            ]

            for tag in inlineControlTags {
                if let control =
                    host.viewWithTag(tag)
                {
                    host.bringSubviewToFront(control)
                }
            }
        } else {
            stop()
        }
    }

    private func restoreStatusBarAfterFullscreen() {
        guard
            let wasHidden =
                fullscreenStatusBarWasHidden
        else {
            return
        }

        UIApplication.shared
            .setStatusBarHidden(
                wasHidden,
                with:
                    .fade
            )
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": false])

        fullscreenStatusBarWasHidden =
            nil
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

        cancelScheduledScrollStopFinish()

        player?.pause()

        playerLayer?
            .isHidden =
                true

        hostView =
            nil

        pendingScrollStopMediaID =
            mediaID

        activeMediaID =
            nil
    }

    func finishScrollStop() {
        guard
            pendingScrollStopMediaID !=
                nil
        else {
            return
        }

        pendingScrollStopMediaID =
            nil

        stop()
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

    func stopIfMediaID(
        _ mediaID: String
    ) {
        if activeMediaID == mediaID {
            stop()
        }
    }

    func stop() {
        videoHealthTimer?.invalidate()
        videoHealthTimer = nil
        lastHealthSeconds = nil
        healthStagnantTicks = 0
        healthObservedStall = false
        healthHasPlayed = false
        cancelScheduledScrollStopFinish()

        pendingScrollStopMediaID = nil

        let stoppedMediaID =
            activeMediaID

        if let item =
            observedItem
        {
            NotificationCenter.default.removeObserver(self,
                name: Notification.Name("AVPlayerItemPlaybackStalledNotification"),
                object: item)
            NotificationCenter.default.removeObserver(self,
                name: Notification.Name("AVPlayerItemFailedToPlayToEndTimeNotification"),
                object: item)
            NotificationCenter.default
                .removeObserver(
                    self,
                    name:
                        .AVPlayerItemDidPlayToEndTime,
                    object:
                        item
                )
        }

        observedItem = nil

        fullscreenOverlay?
            .cancelAutoHide()

        fullscreenOverlay?
            .removeFromSuperview()

        fullscreenOverlay = nil

        restoreStatusBarAfterFullscreen()

        player?.pause()

        player?
            .replaceCurrentItem(
                with: nil
            )

        playerLayer?
            .removeFromSuperlayer()

        streamProxy
            .closeCurrentStream()

        player = nil
        playerLayer = nil
        hostView = nil
        inlineFrame = CGRect.zero
        activeMediaID = nil
        recoveryPost = nil
        wantsPlaybackAfterNetworkReturn = false
        isMuted = false

        if let mediaID = stoppedMediaID, !healthRestartInProgress {
            onStopped?(mediaID)
        }
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

        player.seek(
            to: CMTime.zero,
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
