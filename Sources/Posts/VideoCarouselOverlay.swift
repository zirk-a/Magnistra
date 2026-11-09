// Overview: Fullscreen carousel overlay.
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



final class MagnistraCarouselFullscreenOverlay: UIView,
        UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let post: MagnistraRealPost
    private var currentIndex: Int
    private let zoomScroll = UIScrollView(frame: .zero)
    private let mediaHost = UIView(frame: .zero)
    private let photoView = UIImageView(frame: .zero)
    private let counterLabel = UILabel(frame: .zero)
    private let mediaLoadingSpinner = UIActivityIndicatorView(style: .white)
    private var slideTransitionInProgress = false
    private var videoBufferChecks = 0
    private let closeButton = MagnistraVideoGlyphButton(frame: .zero)
    private let volumeButton = MagnistraVideoGlyphButton(frame: .zero)
    private let rotateButton = MagnistraVideoGlyphButton(frame: .zero)
    private var priorStatusBarHidden = false
    private var initialImage: UIImage?
    private var loadedVideoID: String? = nil
    private var onDismiss: ((Int, String?) -> Bool)? = nil
    private var imageRequestGeneration = 0
    private var quarterTurn = false
    private var controlsVisible = true
    private let autoHideDelay: TimeInterval = 2.5
    private let imageQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private init(post: MagnistraRealPost, index: Int,
                 image: UIImage?, frame: CGRect) {
        self.post = post
        currentIndex = index
        initialImage = image
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .black

        zoomScroll.delegate = self
        zoomScroll.minimumZoomScale = 1.0
        zoomScroll.maximumZoomScale = 4.0
        zoomScroll.bouncesZoom = true
        zoomScroll.showsHorizontalScrollIndicator = false
        zoomScroll.showsVerticalScrollIndicator = false
        zoomScroll.backgroundColor = .black
        zoomScroll.panGestureRecognizer.isEnabled = false
        zoomScroll.frame = bounds
        addSubview(zoomScroll)
        mediaHost.backgroundColor = .black
        mediaHost.clipsToBounds = true
        mediaHost.frame = zoomScroll.bounds
        zoomScroll.contentSize = zoomScroll.bounds.size
        zoomScroll.addSubview(mediaHost)
        photoView.backgroundColor = .black
        photoView.contentMode = .scaleAspectFit
        mediaHost.addSubview(photoView)
        photoView.frame = mediaHost.bounds

        counterLabel.textAlignment = .center
        counterLabel.textColor = .white
        counterLabel.font = UIFont.boldSystemFont(ofSize: 12.0)
        counterLabel.backgroundColor = UIColor(white: 0, alpha: 0.58)
        counterLabel.layer.cornerRadius = 6.0
        counterLabel.clipsToBounds = true
        addSubview(counterLabel)
        mediaLoadingSpinner.hidesWhenStopped = true
        mediaLoadingSpinner.stopAnimating()
        addSubview(mediaLoadingSpinner)

        closeButton.glyphKind = .close
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)
        volumeButton.glyphKind = .volume
        volumeButton.addTarget(self, action: #selector(volumeTapped), for: .touchUpInside)
        addSubview(volumeButton)
        rotateButton.glyphKind = .rotate
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        addSubview(rotateButton)

        let left = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
        left.direction = .left
        left.delegate = self
        addGestureRecognizer(left)
        let right = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
        right.direction = .right
        right.delegate = self
        addGestureRecognizer(right)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.45
        hold.cancelsTouchesInView = true
        hold.delegate = self
        addGestureRecognizer(hold)
        let tap = UITapGestureRecognizer(target: self, action: #selector(overlayTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
        renderCurrentMedia()
    }

    required init?(coder: NSCoder) { return nil }

    static func present(post: MagnistraRealPost,
                        index: Int, image: UIImage?,
                        onDismiss: ((Int, String?) -> Bool)? = nil) -> Bool {
        guard post.carouselMedia.count > 1,
              index >= 0 && index < post.carouselMedia.count,
              let window = UIApplication.shared.keyWindow ?? UIApplication.shared.windows.first
        else { return false }
        let overlay = MagnistraCarouselFullscreenOverlay(
            post: post, index: index, image: image, frame: window.bounds)
        overlay.priorStatusBarHidden = UIApplication.shared.isStatusBarHidden
        overlay.onDismiss = onDismiss
        MagnistraPhotoMusicPlayer.shared.stop()
        UIApplication.shared.setStatusBarHidden(true, with: .fade)
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: overlay, userInfo: ["hidden": true])
        window.addSubview(overlay)
        overlay.setNeedsLayout()
        return true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { refreshControlTimer() } else { cancelAutoHide() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let oldSize = zoomScroll.bounds.size
        zoomScroll.frame = bounds
        if zoomScroll.zoomScale <= 1.001 || oldSize != bounds.size {
            if zoomScroll.zoomScale > 1.001 { zoomScroll.zoomScale = 1.0 }
            mediaHost.frame = CGRect(origin: .zero, size: zoomScroll.bounds.size)
            zoomScroll.contentSize = zoomScroll.bounds.size
        }
        photoView.frame = mediaHost.bounds
        mediaLoadingSpinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        closeButton.frame = CGRect(x: 10, y: 10, width: 32, height: 32)
        counterLabel.frame = CGRect(x: bounds.width - 78, y: 12,
                                    width: 66, height: 28)
        volumeButton.frame = CGRect(x: 10, y: bounds.height - 42,
                                    width: 32, height: 32)
        rotateButton.frame = CGRect(x: bounds.width - 42, y: bounds.height - 42,
                                    width: 32, height: 32)
        updateVideoRotation()
        bringSubviewToFront(counterLabel)
        bringSubviewToFront(mediaLoadingSpinner)
        bringSubviewToFront(closeButton)
        bringSubviewToFront(volumeButton)
        bringSubviewToFront(rotateButton)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return mediaHost
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let extraX = max(0.0, (scrollView.bounds.width - scrollView.contentSize.width) / 2.0)
        let extraY = max(0.0, (scrollView.bounds.height - scrollView.contentSize.height) / 2.0)
        scrollView.contentInset = UIEdgeInsets(top: extraY, left: extraX,
                                               bottom: extraY, right: extraX)
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > 1.01
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        return !(touch.view is UIControl)
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer is UISwipeGestureRecognizer {
            return zoomScroll.zoomScale < 1.01
        }
        return true
    }

    private func cancelAutoHide() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(autoHideControls), object: nil)
    }

    private func refreshControlTimer() {
        cancelAutoHide()

        if loadedVideoID != nil && controlsVisible && window != nil {
            perform(#selector(autoHideControls), with: nil, afterDelay: autoHideDelay)
        }
    }

    private func showControls() {
        cancelAutoHide()
        controlsVisible = true
        closeButton.isHidden = false
        closeButton.isUserInteractionEnabled = true
        closeButton.alpha = 1.0
        let video = loadedVideoID != nil
        volumeButton.isHidden = !video
        rotateButton.isHidden = !video
        volumeButton.isUserInteractionEnabled = video
        rotateButton.isUserInteractionEnabled = video
        volumeButton.alpha = 1.0
        rotateButton.alpha = 1.0
        counterLabel.isHidden = false
        counterLabel.alpha = 1.0
        refreshControlTimer()
    }

    @objc private func autoHideControls() {
        guard loadedVideoID != nil && window != nil else { return }
        cancelAutoHide()
        controlsVisible = false
        closeButton.isUserInteractionEnabled = false
        volumeButton.isUserInteractionEnabled = false
        rotateButton.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.18, animations: { [weak self] in
            self?.closeButton.alpha = 0.0
            self?.volumeButton.alpha = 0.0
            self?.rotateButton.alpha = 0.0
            self?.counterLabel.alpha = 0.0
        }, completion: { [weak self] _ in
            guard let self = self, !self.controlsVisible else { return }
            self.closeButton.isHidden = true
            self.volumeButton.isHidden = true
            self.rotateButton.isHidden = true
            self.counterLabel.isHidden = true
        })
    }

    @objc private func overlayTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, loadedVideoID != nil else { return }
        if controlsVisible {
            autoHideControls()
        } else {
            showControls()
        }
    }

    private func resetZoom() {
        zoomScroll.setZoomScale(1.0, animated: false)
        zoomScroll.contentOffset = .zero
        zoomScroll.contentInset = .zero
        zoomScroll.panGestureRecognizer.isEnabled = false
    }

    private func mediaPost(_ media: MagnistraCarouselMedia) -> MagnistraRealPost {
        var item = MagnistraRealPost(
            mediaID: media.mediaID, userID: post.userID,
            username: post.username, fullName: post.fullName,
            caption: post.caption, commentCount: post.commentCount,
            previewComments: post.previewComments, likes: post.likes,
            location: post.location, takenAt: post.takenAt,
            imagePath: "", imageURL: media.imageURL,
            imageCacheKey: "carousel:" + post.mediaID + ":" + media.mediaID,
            avatarPath: post.avatarPath, avatarURL: post.avatarURL,
            avatarCacheKey: post.avatarCacheKey, musicTitle: nil,
            musicArtist: nil, musicAudioURL: nil, musicStartTimeMs: 0,
            photoMusicImageURLFallback: nil, videoURL: media.videoURL,
            videoWidth: media.videoWidth, videoHeight: media.videoHeight)
        item.isVideo = media.videoURL != nil
        return item
    }

    private func renderCurrentMedia() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(checkVideoBuffer), object: nil)
        mediaLoadingSpinner.stopAnimating()
        guard currentIndex >= 0 && currentIndex < post.carouselMedia.count else { return }
        cancelAutoHide()
        resetZoom()
        let media = post.carouselMedia[currentIndex]
        if let old = loadedVideoID {
            MagnistraInlineVideoPlayer.shared.stopIfMediaID(old)
            loadedVideoID = nil
        }
        quarterTurn = false
        imageRequestGeneration += 1
        let generation = imageRequestGeneration
        counterLabel.text = "\(currentIndex + 1) / \(post.carouselMedia.count)"
        let stable = currentIndex == 0 && media.imageURL == post.imageURL
            ? post.imageCacheKey
            : "carousel:" + post.mediaID + ":" + media.mediaID
        let cacheKey = "post:" + stable
        let decoder = MagnistraDecodedImageLoader.shared
        photoView.isHidden = false
        photoView.image = decoder.cachedImage(forKey: cacheKey)
            ?? (currentIndex == 0 ? initialImage : nil)
            ?? decoder.gridPreview(stableKey: stable)
        if photoView.image == nil && !media.imageURL.isEmpty {
            if media.videoURL == nil { mediaLoadingSpinner.startAnimating() }
            imageQueue.addOperation { [weak self] in
                let result = MagnistraHomeService.materializeVisitedProfileGridImage(
                    url: media.imageURL, stableKey: stable)
                let loaded = result.path.flatMap { UIImage(contentsOfFile: $0) }
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, self.imageRequestGeneration == generation,
                          self.window != nil else { return }
                    if let loaded = loaded { self.photoView.image = loaded }
                    if self.loadedVideoID == nil { self.mediaLoadingSpinner.stopAnimating() }
                }
            }
        }
        let isVideo = media.videoURL != nil
        if isVideo {
            MagnistraPhotoMusicPlayer.shared.stop()
            let video = mediaPost(media)
            let activeVideo = MagnistraInlineVideoPlayer.shared
            if activeVideo.moveCarouselVideo(
                mediaID: video.mediaID, hostView: mediaHost,
                frame: mediaHost.bounds) || activeVideo.start(
                post: video, hostView: mediaHost, frame: mediaHost.bounds) {
                loadedVideoID = video.mediaID

                photoView.isHidden = true
                volumeButton.glyphKind = .volume
                mediaLoadingSpinner.startAnimating()
                videoBufferChecks = 0
                perform(#selector(checkVideoBuffer), with: nil, afterDelay: 0.25)
            }
        }
        showControls()
        setNeedsLayout()
    }

    @objc private func checkVideoBuffer() {
        guard let id = loadedVideoID, window != nil else {
            mediaLoadingSpinner.stopAnimating()
            return
        }
        if MagnistraInlineVideoPlayer.shared.hasPlaybackProgress(mediaID: id) {
            mediaLoadingSpinner.stopAnimating()
            return
        }
        videoBufferChecks += 1

        if videoBufferChecks >= 48 {
            mediaLoadingSpinner.stopAnimating()
            return
        }
        perform(#selector(checkVideoBuffer), with: nil, afterDelay: 0.25)
    }

    private func updateVideoRotation() {
        guard let id = loadedVideoID else { return }
        MagnistraInlineVideoPlayer.shared.setCarouselFullscreenRotation(
            mediaID: id, hostView: mediaHost, rotated: quarterTurn)
    }

    @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
        guard zoomScroll.zoomScale < 1.01,
              !slideTransitionInProgress else { return }
        let delta = recognizer.direction == .left ? 1 : -1
        let next = currentIndex + delta
        guard next >= 0 && next < post.carouselMedia.count else { return }

        layoutIfNeeded()
        let travel = mediaHost.bounds.width * CGFloat(delta)
        let oldImage = photoView.isHidden ? nil : photoView.image
        let outgoing = UIImageView(frame: mediaHost.frame)
        outgoing.image = oldImage
        outgoing.contentMode = .scaleAspectFit
        outgoing.backgroundColor = .black
        zoomScroll.insertSubview(outgoing, belowSubview: mediaHost)
        slideTransitionInProgress = true
        currentIndex = next

        let slide = CATransition()
        slide.type = .push
        slide.subtype = recognizer.direction == .left ? .fromRight : .fromLeft
        slide.duration = 0.24
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        zoomScroll.layer.add(slide, forKey: "magnistraCarouselSlide")
        renderCurrentMedia()
        mediaHost.transform = CGAffineTransform(translationX: travel, y: 0)
        UIView.animate(withDuration: 0.18, delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: {
                self.mediaHost.transform = .identity
                outgoing.transform = CGAffineTransform(translationX: -travel, y: 0)
            }, completion: { [weak self] _ in
                outgoing.removeFromSuperview()
                self?.mediaHost.transform = .identity
                self?.slideTransitionInProgress = false
            })
    }

    @objc private func volumeTapped() {
        guard loadedVideoID != nil else { return }
        if let muted = MagnistraInlineVideoPlayer.shared.toggleMuted() {
            volumeButton.glyphKind = muted ? .muted : .volume
        }
        showControls()
    }

    @objc private func rotateTapped() {
        guard loadedVideoID != nil else { return }
        quarterTurn = !quarterTurn
        updateVideoRotation()
        showControls()
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { closeTapped() }
    }

    @objc private func closeTapped() {
        cancelAutoHide()
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(checkVideoBuffer), object: nil)
        mediaLoadingSpinner.stopAnimating()
        imageRequestGeneration += 1
        imageQueue.cancelAllOperations()
        resetZoom()
        let playingID = loadedVideoID
        let handedOff = onDismiss?(currentIndex, playingID) ?? false
        onDismiss = nil
        if let id = playingID, !handedOff {
            MagnistraInlineVideoPlayer.shared.stopIfMediaID(id)
        }
        loadedVideoID = nil
        removeFromSuperview()
        UIApplication.shared.setStatusBarHidden(priorStatusBarHidden, with: .fade)
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": priorStatusBarHidden])
    }
}