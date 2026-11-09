// Overview: Post carousel behavior.
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

extension MagnistraPostCell {


    func resumeDeferredPhotoLoadIfNeeded() {
        guard
            let post =
                configuredPostForImageResume
        else {
            return
        }
        if carouselIndex > 0 && carouselIndex < post.carouselMedia.count {
            refreshCarouselDisplay()
            return
        }

        let photoKey =
            "post:" +
            post.imageCacheKey

        photoLoadToken =
            photoKey

        if let ready =
            MagnistraDecodedImageLoader
                .shared
                .cachedImage(
                    forKey:
                        photoKey
                )
        {
            photoView.image =
                ready
            photoView.backgroundColor = UIColor.black

            return
        }

        MagnistraDecodedImageLoader
            .shared
            .requestImage(
                path:
                    post.imagePath
                        .isEmpty
                        ? nil
                        : post.imagePath,
                remoteURL:
                    post.imageURL,
                stableKey:
                    post.imageCacheKey,
                key:
                    photoKey,
                isAvatar:
                    false,
                target:
                    self
            )
    }

    func refreshCarouselVideoControls() {
        guard let post = currentPost,
              post.carouselMedia.count > 1,
              carouselIndex >= 0,
              carouselIndex < post.carouselMedia.count else {
            carouselPlayButton.isHidden = true
            carouselMuteButton.isHidden = true
            carouselFullscreenButton.isHidden = true
            return
        }
        let item = post.carouselMedia[carouselIndex]
        let player = MagnistraInlineVideoPlayer.shared
        let active = item.videoURL != nil && player.activeMediaID == item.mediaID
        carouselPlayButton.mediaID = item.mediaID
        carouselPlayButton.glyphKind = active ? .stop : .play
        carouselPlayButton.isHidden = item.videoURL == nil
        carouselMuteButton.mediaID = item.mediaID
        carouselMuteButton.glyphKind = player.isMuted ? .muted : .volume
        carouselMuteButton.isHidden = !active
        carouselFullscreenButton.mediaID = item.mediaID
        carouselFullscreenButton.isHidden = !active
    }

    func refreshCarouselDisplay() {
        guard let post = currentPost, post.carouselMedia.count > 1 else {
            carouselLoadingSpinner.stopAnimating()
            carouselPageLabel.isHidden = true
            refreshCarouselVideoControls()
            return
        }
        carouselIndex = min(max(0, carouselIndex), post.carouselMedia.count - 1)
        let media = post.carouselMedia[carouselIndex]
        carouselPageLabel.text = String(carouselIndex + 1) + " / " +
            String(post.carouselMedia.count)
        carouselPageLabel.isHidden = false
        refreshCarouselVideoControls()

        let usePrimary = carouselIndex == 0 && media.imageURL == post.imageURL
        let stable = usePrimary
            ? post.imageCacheKey
            : "carousel:" + post.mediaID + ":" + media.mediaID
        let key = "post:" + stable
        photoLoadToken = key
        photoView.contentMode = .scaleAspectFit
        photoView.backgroundColor = carouselIndex == 0
            ? MagnistraPostCell.loadingPostColor(mediaID: post.mediaID)
            : .black
        if let cached = MagnistraDecodedImageLoader.shared.cachedImage(forKey: key) {
            photoView.image = cached
            photoView.backgroundColor = .black
            carouselLoadingSpinner.stopAnimating()
        } else {

            let preview = magnistraSavedGridPreviewEnabled && carouselIndex == 0
                ? MagnistraDecodedImageLoader.shared.gridPreview(
                    stableKey: post.imageCacheKey) : nil
            photoView.image = preview
            if preview == nil && carouselIndex > 0 {
                carouselLoadingSpinner.startAnimating()
            } else {
                carouselLoadingSpinner.stopAnimating()
            }
            if preview != nil { photoView.backgroundColor = .black }
            MagnistraDecodedImageLoader.shared.requestImage(
                path: usePrimary && !post.imagePath.isEmpty ? post.imagePath : nil,
                remoteURL: media.imageURL,
                stableKey: stable, key: key, isAvatar: false, target: self)
        }
    }

    @objc func carouselSwiped(_ gesture: UISwipeGestureRecognizer) {
        guard let post = currentPost, post.carouselMedia.count > 1,
              !carouselTransitionInProgress else { return }
        let change = gesture.direction == .left ? 1 : -1
        let next = carouselIndex + change
        guard next >= 0 && next < post.carouselMedia.count else { return }
        let previousImage = photoView.image
        if carouselIndex < post.carouselMedia.count {
            MagnistraInlineVideoPlayer.shared.stopIfMediaID(
                post.carouselMedia[carouselIndex].mediaID)
        }
        carouselIndex = next
        refreshCarouselDisplay()

        let bounds = photoView.bounds
        guard bounds.width > 1.0, bounds.height > 1.0 else { return }
        let travel = bounds.width * CGFloat(change)
        let outgoing = UIImageView(frame: bounds)
        outgoing.tag = 93210
        outgoing.image = previousImage
        outgoing.contentMode = .scaleAspectFit
        outgoing.backgroundColor = .black
        let incoming = UIImageView(frame: CGRect(
            x: travel, y: 0.0, width: bounds.width, height: bounds.height))
        incoming.tag = 93210
        incoming.image = photoView.image
        incoming.contentMode = .scaleAspectFit
        incoming.backgroundColor = .black
        photoView.addSubview(outgoing)
        photoView.addSubview(incoming)
        carouselTransitionInProgress = true
        UIView.animate(withDuration: 0.18, delay: 0.0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: {
                outgoing.frame.origin.x = -travel
                incoming.frame.origin.x = 0.0
            }, completion: { [weak self] _ in
                outgoing.removeFromSuperview()
                incoming.removeFromSuperview()
                self?.carouselTransitionInProgress = false
            })
    }

    @objc func carouselVideoSurfaceTapped(
        _ gesture: UITapGestureRecognizer
    ) {
        guard gesture.state == .ended,
              let post = currentPost,
              post.carouselMedia.count > 1,
              carouselIndex >= 0,
              carouselIndex < post.carouselMedia.count else { return }
        let item = post.carouselMedia[carouselIndex]
        guard item.videoURL != nil else { return }
        let player = MagnistraInlineVideoPlayer.shared
        if player.activeMediaID == item.mediaID {
            _ = player.toggle(mediaID: item.mediaID)
        } else {
            carouselPlayTapped()
        }
    }

    @objc func carouselPlayTapped() {
        guard let post = currentPost,
              carouselIndex >= 0,
              carouselIndex < post.carouselMedia.count else { return }
        let item = post.carouselMedia[carouselIndex]
        guard let url = item.videoURL else { return }
        let player = MagnistraInlineVideoPlayer.shared
        if player.activeMediaID == item.mediaID {
            player.stopIfMediaID(item.mediaID)
            refreshCarouselVideoControls()
            return
        }
        var videoPost = MagnistraRealPost(
            mediaID: item.mediaID, userID: post.userID,
            username: post.username, fullName: post.fullName,
            caption: post.caption, commentCount: post.commentCount,
            previewComments: post.previewComments, likes: post.likes,
            location: post.location, takenAt: post.takenAt,
            imagePath: "", imageURL: item.imageURL,
            imageCacheKey: "carousel:" + post.mediaID + ":" + item.mediaID,
            avatarPath: post.avatarPath, avatarURL: post.avatarURL,
            avatarCacheKey: post.avatarCacheKey, musicTitle: nil,
            musicArtist: nil, musicAudioURL: nil, musicStartTimeMs: 0,
            photoMusicImageURLFallback: nil, videoURL: url,
            videoWidth: item.videoWidth, videoHeight: item.videoHeight)
        videoPost.isVideo = true
        MagnistraPhotoMusicPlayer.shared.stop()
        _ = player.start(post: videoPost, hostView: photoView,
                         frame: photoView.bounds)
        refreshCarouselVideoControls()
    }

    @objc func carouselMuteTapped() {
        guard let post = currentPost,
              carouselIndex >= 0,
              carouselIndex < post.carouselMedia.count else { return }
        let item = post.carouselMedia[carouselIndex]
        let player = MagnistraInlineVideoPlayer.shared
        guard player.activeMediaID == item.mediaID else {
            refreshCarouselVideoControls()
            return
        }
        _ = player.toggleMuted()
        refreshCarouselVideoControls()
    }

    @objc func carouselFullscreenTapped() {
        guard let post = currentPost,
              carouselIndex >= 0,
              carouselIndex < post.carouselMedia.count else { return }
        let item = post.carouselMedia[carouselIndex]
        guard MagnistraInlineVideoPlayer.shared.activeMediaID == item.mediaID
        else {
            refreshCarouselVideoControls()
            return
        }
        _ = MagnistraInlineVideoPlayer.shared.enterFullscreen()
    }

    func applyDecodedImage(
        _ image: UIImage,
        key: String,
        isAvatar: Bool
    ) {
        if isAvatar {
            guard avatarLoadToken == key else {
                return
            }
            avatarView.image = image
        } else {
            guard photoLoadToken == key else {
                return
            }
            if
                currentPost?.videoURL ==
                    nil
            {
                photoView.contentMode =
                    .scaleAspectFit
            }

            photoView.image = image
            photoView.backgroundColor = UIColor.black
            if let post = currentPost, post.carouselMedia.count > 1 {
                carouselLoadingSpinner.stopAnimating()
            }
        }
    }

    func applyPhotoMusicImageFailure(
        key: String
    ) {
        guard photoLoadToken == key else {
            return
        }

        onPhotoMusicImageFailure?()
    }

    func applyPhotoMusicImage(
        _ image: UIImage,
        key: String
    ) {
        guard
            photoLoadToken ==
                key
        else {
            return
        }

        photoView.image =
            image
        photoView.backgroundColor = UIColor.black
    }

    func suspendCarouselVideoForScroll() {
        guard let post = currentPost,
              carouselIndex >= 0,
              carouselIndex < post.carouselMedia.count,
              post.carouselMedia[carouselIndex].videoURL != nil else {
            return
        }
        MagnistraInlineVideoPlayer.shared.suspendForScrollIfMediaID(
            post.carouselMedia[carouselIndex].mediaID)
        refreshCarouselVideoControls()
    }

    @objc func normalPhotoLongPressed(
        _ recognizer: UILongPressGestureRecognizer
    ) {
        guard recognizer.state == .began, !savedMetadataPending,
              let post = currentPost else { return }
        let inlinePlayer = MagnistraInlineVideoPlayer.shared
        if post.carouselMedia.count > 1 {
            _ = MagnistraCarouselFullscreenOverlay.present(
                post: post, index: carouselIndex, image: photoView.image,
                onDismiss: { [weak self] selectedIndex, activeVideoID in
                    guard let self = self,
                          let livePost = self.currentPost,
                          livePost.mediaID == post.mediaID,
                          self.window != nil,
                          selectedIndex >= 0,
                          selectedIndex < livePost.carouselMedia.count else {
                        return false
                    }
                    self.carouselIndex = selectedIndex
                    self.refreshCarouselDisplay()
                    var retainedVideo = false
                    if let activeVideoID = activeVideoID,
                       livePost.carouselMedia[selectedIndex].mediaID == activeVideoID {
                        retainedVideo = MagnistraInlineVideoPlayer.shared.moveCarouselVideo(
                            mediaID: activeVideoID, hostView: self.photoView,
                            frame: self.photoView.bounds)
                    }
                    self.refreshCarouselVideoControls()
                    return retainedVideo
                })
            return
        }
        if post.videoURL != nil {
            MagnistraPhotoMusicPlayer.shared.stop()
            if inlinePlayer.activeMediaID != post.mediaID {
                _ = inlinePlayer.start(post: post, hostView: photoView,
                                       frame: photoView.bounds)
            }
            _ = inlinePlayer.enterFullscreen()
            return
        }
        guard let image = photoView.image else { return }
        if post.musicAudioURL != nil {
            let music = MagnistraPhotoMusicPlayer.shared
            if music.activeMediaID == post.mediaID {
                if !music.isPlaying { _ = music.toggle(post: post) }
            } else {
                inlinePlayer.stop()
                _ = music.start(post: post)
            }
        }
        _ = MagnistraImageZoomOverlay.present(image: image)
    }

    @objc func photoMusicFullscreenTapped() {
        guard
            let post =
                currentPost,
            post.videoURL == nil,
            post.musicAudioURL != nil,
            let image =
                photoView.image
        else {
            return
        }

        let music =
            MagnistraPhotoMusicPlayer
                .shared

        if
            music.activeMediaID ==
                post.mediaID
        {
            if !music.isPlaying {
                _ =
                    music.toggle(
                        post:
                            post
                    )
            }
        } else {
            MagnistraInlineVideoPlayer
                .shared
                .stop()

            _ =
                music.start(
                    post:
                        post
                )
        }

        _ =
            MagnistraImageZoomOverlay
                .present(
                    image:
                        image
                )
    }

    func currentMediaImage()
        -> UIImage?
    {
        return photoView.image
    }
}
