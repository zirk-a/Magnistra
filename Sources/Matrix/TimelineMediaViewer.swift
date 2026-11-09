// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: opening files, videos and animated WebP.
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

extension RoomTimelineVC {


    func handleFileTap(mxc: String, filename: String, mimeType: String,
                               animatedVideo: Bool = false) {
        if animatedVideo {
            openVideoBackedAnimatedWebP(mxc: mxc, filename: filename, mimeType: mimeType)
            return
        }
        if let path = MediaCache.shared.downloadedFilePath(mxc: mxc, filename: filename, mimeType: mimeType) {
            cacheVideoPosterIfPossible(mxc: mxc, path: path, filename: filename, mimeType: mimeType)
            openDownloadedFile(path: path, filename: filename, mimeType: mimeType,
                               animatedVideo: animatedVideo)
            return
        }
        guard fileProgress[mxc] == nil else { return }

        fileProgress[mxc] = 0
        visibleAttachmentCell(for: mxc)?.setProgress(0)
        MediaCache.shared.downloadFile(mxc: mxc, filename: filename, mimeType: mimeType,
                                       progress: { [weak self] fraction in
            guard let self = self else { return }

            let previous = self.fileProgress[mxc] ?? -1
            guard Int(fraction * 100) != Int(previous * 100) else { return }
            self.fileProgress[mxc] = fraction
            self.visibleAttachmentCell(for: mxc)?.setProgress(fraction)
        }) { [weak self] path in
            guard let self = self else { return }
            self.fileProgress.removeValue(forKey: mxc)
            let cell = self.visibleAttachmentCell(for: mxc)
            if let path = path {
                cell?.markDownloaded()
                self.cacheVideoPosterIfPossible(
                    mxc: mxc,
                    path: path,
                    filename: filename,
                    mimeType: mimeType
                )

                if self.view.window != nil {
                    self.openDownloadedFile(path: path, filename: filename, mimeType: mimeType,
                                            animatedVideo: animatedVideo)
                }
            } else {
                cell?.setProgress(nil)
                self.showAlert(title: "Download failed", message: filename)
            }
        }
    }

    func cacheVideoPosterIfPossible(mxc: String, path: String,
                                            filename: String, mimeType: String) {
        guard isVideo(filename: filename, mimeType: mimeType),
              let poster = videoThumbnail(path: path) else { return }

        var sourceWidth = Int(poster.size.width)
        var sourceHeight = Int(poster.size.height)
        for event in events {
            if case .video(_, let video) = event.kind, video.mxc == mxc {
                if video.width > 0 { sourceWidth = video.width }
                if video.height > 0 { sourceHeight = video.height }
                break
            }
        }

        let (reqW, reqH) = ImageEventCell.thumbnailRequestSize(
            imageWidth: sourceWidth,
            imageHeight: sourceHeight
        )
        MediaCache.shared.storeThumbnail(poster, mxc: mxc, width: reqW, height: reqH)
    }

    func openVideoBackedAnimatedWebP(
        mxc: String,
        filename: String,
        mimeType: String
    ) {
        MediaCache.shared.loadVideoBackedAnimatedWebP(
            mxc: mxc,
            filename: filename,
            mimeType: mimeType
        ) { [weak self] image, error in
            guard let self = self, let image = image else {
                self?.showAlert(
                    title: "GIF",
                    message: "Could not prepare animation (" + (error ?? "unknown") + ")."
                )
                return
            }

            let viewer = UIViewController()
            viewer.view.backgroundColor = .black
            let imageView = UIImageView(frame: viewer.view.bounds)
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .black
            viewer.view.addSubview(imageView)

            let frames = image.images ?? []
            if frames.count > 1 {
                imageView.image = frames[0]
                imageView.animationImages = frames
                imageView.animationDuration = max(0.05, image.duration)
                imageView.animationRepeatCount = 0
                imageView.startAnimating()
            } else {
                imageView.image = image
            }

            magnistraMediaTrace(
                "VIDEO_WEBP_FULLSCREEN frames=\(frames.count) duration=\(image.duration)"
            )
            self.navigationController?.pushViewController(viewer, animated: true)
        }
    }

    func openDownloadedFile(path: String, filename: String, mimeType: String,
                                    animatedVideo: Bool = false) {
        if isVideo(filename: filename, mimeType: mimeType) {
            if isWebMVideo(filename: filename, mimeType: mimeType) {
                showAlert(title: "WebM video",
                          message: "This Telegram video uses WebM, which iOS 5 cannot decode natively yet.")
                return
            }
            let playbackPath = MediaCache.legacyVideoPlaybackPath(
                path: path, mimeType: mimeType, animated: false
            )
            playVideo(path: playbackPath)
            return
        }

        if isText(filename: filename, mimeType: mimeType) {
            let viewer = TextFileViewerVC(path: path, filename: filename)
            navigationController?.pushViewController(viewer, animated: true)
            return
        }

        let controller = UIDocumentInteractionController(url: URL(fileURLWithPath: path))
        controller.delegate = self
        controller.name = filename
        docController = controller
        if controller.presentPreview(animated: true) { return }
        if controller.presentOpenInMenu(from: view.bounds, in: view, animated: true) { return }
        docController = nil
        showAlert(title: "Can't open",
                      message: "No app on this device can open \(filename). It's saved at:\n\n\(path)")
    }

    func logVideoProbe(path: String, label: String) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let videoTracks = asset.tracks(withMediaType: .video).count
        let audioTracks = asset.tracks(withMediaType: .audio).count
        let seconds = CMTimeGetSeconds(asset.duration)
        let durationText = seconds.isFinite ? String(format: "%.3f", seconds) : "nan"
        let ext = RoomTimelineVC.fileExtension(of: path)
        magnistraMediaTrace(
            "VIDEO_PROBE label=\(label) ext=\(ext) playable=\(asset.isPlayable ? "YES" : "NO") vtracks=\(videoTracks) atracks=\(audioTracks) duration=\(durationText)"
        )
    }

    func observeMovieFinish(_ movie: MPMoviePlayerController, label: String) {
        _ = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: "MPMoviePlayerPlaybackDidFinishNotification"),
            object: movie,
            queue: OperationQueue.main
        ) { [weak self] note in
            let infoText = String(describing: note.userInfo ?? [:])
            magnistraMediaTrace("VIDEO_FINISH label=\(label) info=\(infoText)")

            DispatchQueue.main.async {
                self?.tableView.reloadData()
            }
        }
    }

    func playVideo(path: String) {

        logVideoProbe(path: path, label: "normal")
        stopAudioPlayback()
        startVideoPlaybackSession()
        guard let player = MPMoviePlayerViewController(contentURL: URL(fileURLWithPath: path)) else { return }
        player.moviePlayer.shouldAutoplay = true
        player.moviePlayer.scalingMode = .aspectFit
        observeMovieFinish(player.moviePlayer, label: "normal")
        player.moviePlayer.prepareToPlay()
        moviePlayerVC = player
        present(player, animated: true) {
            player.moviePlayer.play()
        }
    }

    func playAnimatedVideo(path: String) {

        logVideoProbe(path: path, label: "animated")
        stopAudioPlayback()
        startVideoPlaybackSession()
        guard let player = MPMoviePlayerViewController(contentURL: URL(fileURLWithPath: path)) else { return }

        player.moviePlayer.controlStyle = .fullscreen
        player.moviePlayer.repeatMode = .one
        player.moviePlayer.shouldAutoplay = true
        player.moviePlayer.scalingMode = .aspectFit
        observeMovieFinish(player.moviePlayer, label: "animated")
        player.moviePlayer.prepareToPlay()
        moviePlayerVC = player
        present(player, animated: true) {
            player.moviePlayer.play()
        }
    }

    func isLikelyAnimatedVideo(path: String) -> Bool {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard !asset.tracks(withMediaType: .video).isEmpty else { return false }
        guard asset.tracks(withMediaType: .audio).isEmpty else { return false }
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 && seconds <= 60
    }

    func isWebMVideo(filename: String, mimeType: String) -> Bool {
        if mimeType.lowercased() == "video/webm" { return true }
        return RoomTimelineVC.fileExtension(of: filename) == "webm"
    }

    func isVideo(filename: String, mimeType: String) -> Bool {
        if mimeType.hasPrefix("video/") { return true }
        guard mimeType.isEmpty else { return false }
        let ext = RoomTimelineVC.fileExtension(of: filename)
        return ext == "mp4" || ext == "mov" || ext == "m4v" || ext == "3gp"
            || ext == "avi" || ext == "webm"
    }

    func isText(filename: String, mimeType: String) -> Bool {

        if mimeType.hasPrefix("text/") && mimeType != "text/html" { return true }
        if mimeType == "application/json" || mimeType == "application/xml" { return true }
        guard mimeType.isEmpty else { return false }
        let ext = RoomTimelineVC.fileExtension(of: filename)
        return ext == "txt" || ext == "log" || ext == "md" || ext == "csv"
            || ext == "json" || ext == "xml"
    }

    static func fileExtension(of filename: String) -> String {
        guard let dot = filename.lastIndex(of: "."),
              dot < filename.index(before: filename.endIndex) else { return "" }
        return String(filename[filename.index(after: dot)...]).lowercased()
    }

    func visibleAttachmentCell(for mxc: String) -> AttachmentProgressCell? {
        for cell in tableView.visibleCells {
            if let attachment = cell as? AttachmentProgressCell, attachment.mxc == mxc { return attachment }
        }
        return nil
    }

    func showAlert(title: String, message: String) {
#if LEGACY_TARGET
        let alert = UIAlertView()
        alert.title = title
        alert.message = message
        alert.addButton(withTitle: "OK")
        alert.show()
#else
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
#endif
    }

    func openImageViewer(mxc: String, placeholder: UIImage?) {
        let viewer = ImageViewerVC(mxc: mxc, placeholder: placeholder)
        navigationController?.pushViewController(viewer, animated: true)
    }

    func openStickerViewer(
        mxc: String,
        placeholder: UIImage?,
        saveWidth: Int? = nil,
        saveHeight: Int? = nil,
        saveSemanticGIF: Bool = false
    ) {
        let fallback = placeholder?.images?.first ?? placeholder

        let viewer = MagnistraStickerFullscreenVC()
        if let saveWidth = saveWidth,
           let saveHeight = saveHeight {
            if saveSemanticGIF {
                viewer.saveTitle = "Save as…"
                viewer.onSave = { [weak self] in
                    self?.presentSemanticGIFSaveOptions(
                        mxc: mxc,
                        width: saveWidth,
                        height: saveHeight
                    )
                }
            } else if MediaCache.shared.stickerInfo(for: mxc) != nil {
                viewer.saveTitle = "Save Sticker"
                viewer.onSave = { [weak self] in
                    guard let self = self else { return }
                    MagnistraStickerLibrary.shared.save(
                        mxc: mxc,
                        bridgeNetwork: self.room.bridgeNetwork,
                        width: saveWidth,
                        height: saveHeight
                    )
                }
            }
        }
        viewer.view.backgroundColor = .black

        let fullView = UIImageView(frame: viewer.view.bounds)
        fullView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fullView.contentMode = .scaleAspectFit
        fullView.clipsToBounds = true
        fullView.backgroundColor = .clear
        fullView.image = fallback
        viewer.view.addSubview(fullView)

        magnistraMediaTrace(
            "STICKER_FULLSCREEN_OPEN fallback=\(fallback == nil ? "NO" : "YES")"
        )
        navigationController?.pushViewController(viewer, animated: true)

        MediaCache.shared.loadFullAnimatedImage(
            mxc: mxc,
            trueSticker: saveWidth != nil && saveHeight != nil && !saveSemanticGIF
        ) { [weak viewer, weak fullView] image in
            guard let viewer = viewer, let fullView = fullView else { return }
            guard viewer.navigationController != nil else { return }

            guard let image = image else {
                magnistraMediaTrace(
                    "STICKER_FULLSCREEN_RESULT animated=NO reason=DECODE_NIL fallback=\(fallback == nil ? "NO" : "YES")"
                )
                return
            }

            let frames = image.images ?? []
            let frameCount = frames.count
            if frameCount > 1 {
                fullView.stopAnimating()
                fullView.animationImages = nil
                fullView.image = frames[0]
                fullView.animationImages = frames
                fullView.animationDuration = max(0.05, image.duration)
                fullView.animationRepeatCount = 0
                fullView.startAnimating()
                fullView.setNeedsDisplay()
                magnistraMediaTrace(
                    "STICKER_FULLSCREEN_RESULT animated=YES frames=\(frameCount) duration=\(image.duration)"
                )
                return
            }

            if fallback == nil {
                fullView.image = image
                fullView.setNeedsDisplay()
            }
            magnistraMediaTrace(
                "STICKER_FULLSCREEN_RESULT animated=NO frames=\(frameCount) fallback=\(fallback == nil ? "NO" : "YES")"
            )
        }
    }

    func showSendError(_ error: Error) {
#if LEGACY_TARGET
        let alert = UIAlertView()
        alert.title = "Send failed"
        alert.message = "\(error)"
        alert.addButton(withTitle: "OK")
        alert.show()
#else
        let alert = UIAlertController(title: "Send failed", message: "\(error)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
#endif
    }
}
