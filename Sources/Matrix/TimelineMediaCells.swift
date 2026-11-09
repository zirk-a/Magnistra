// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: audio, file and video cells.
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



class AudioEventCell: UITableViewCell {
    static let bubbleHeight: CGFloat = 46
    static let bubbleMaxWidth: CGFloat = 210

    private let bubble = UIView()
    private let metaLabel = UILabel()
    private let avatarView = AvatarView()
    private let revealTimeLabel = UILabel()
    private let playButton = UIButton(type: .custom)
    private let durationLabel = UILabel()
    private var isOwnMessage = false
    private var hasMeta = false
    private var revealOffset: CGFloat = 0

    var mxc: String?
    var declaredDuration: TimeInterval = 0
    var onPlayTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        metaLabel.backgroundColor = .clear
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.textColor = .gray
        contentView.addSubview(metaLabel)

        avatarView.isHidden = true
        contentView.addSubview(avatarView)

        bubble.layer.cornerRadius = 12
        bubble.layer.masksToBounds = true
        contentView.addSubview(bubble)

        playButton.imageView?.contentMode = .scaleAspectFit
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        bubble.addSubview(playButton)

        durationLabel.backgroundColor = .clear
        durationLabel.font = UIFont.systemFont(ofSize: 13)
        bubble.addSubview(durationLabel)

        revealTimeLabel.backgroundColor = .clear
        revealTimeLabel.font = UIFont.systemFont(ofSize: 11)
        revealTimeLabel.textColor = .gray
        revealTimeLabel.textAlignment = .right
        revealTimeLabel.isHidden = true
        contentView.addSubview(revealTimeLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func playTapped() { onPlayTap?() }

    func configure(meta: String?, mxc: String, durationMs: Int, time: String, isOwn: Bool,
                   avatarMxc: String?, senderName: String) {
        isOwnMessage = isOwn
        hasMeta = meta != nil
        metaLabel.isHidden = !hasMeta
        metaLabel.text = meta
        metaLabel.textAlignment = isOwn ? .right : .left
        revealTimeLabel.text = time
        self.mxc = mxc
        declaredDuration = Double(durationMs) / 1000.0

        bubble.backgroundColor = isOwn ? UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
                                        : UIColor(white: 0.85, alpha: 1.0)
        let fg: UIColor = isOwn ? .white : .black
        durationLabel.textColor = fg

        let showAvatar = !isOwn && hasMeta
        avatarView.isHidden = !showAvatar
        if showAvatar { avatarView.setAvatar(mxc: avatarMxc, name: senderName) }

        setPlaybackState(playing: false, currentTime: 0, duration: declaredDuration)
        setNeedsLayout()
    }

    func setPlaybackState(playing: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        let iconName: String
        if playing { iconName = isOwnMessage ? "PauseWhite" : "PauseDark" }
        else { iconName = isOwnMessage ? "PlayWhite" : "PlayDark" }
        playButton.setImage(UIImage(named: iconName), for: .normal)
        let total = duration > 0 ? duration : declaredDuration
        if playing {
            durationLabel.text = "\(AudioEventCell.fmt(currentTime)) / \(AudioEventCell.fmt(total))"
        } else {
            durationLabel.text = "Voice \u{00B7} \(AudioEventCell.fmt(total))"
        }
    }

    private static func fmt(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func setRevealOffset(_ offset: CGFloat) {
        guard offset != revealOffset else { return }
        revealOffset = offset
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxBubbleWidth = contentView.bounds.width * EventCell.bubbleWidthFraction
        let bw = min(AudioEventCell.bubbleMaxWidth, maxBubbleWidth)
        let bh = AudioEventCell.bubbleHeight

        let leftEdge = EventCell.outerMargin + (isOwnMessage ? 0 : EventCell.senderGutter)

        var y: CGFloat = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
        if hasMeta {
            let metaX = isOwnMessage ? contentView.bounds.width - EventCell.outerMargin - maxBubbleWidth
                                     : leftEdge
            metaLabel.frame = CGRect(x: metaX - revealOffset, y: y,
                                      width: maxBubbleWidth, height: EventCell.metaHeight)
            y += EventCell.metaHeight + EventCell.metaGap
        }

        let bubbleX = isOwnMessage ? contentView.bounds.width - bw - EventCell.outerMargin
                                    : leftEdge
        bubble.frame = CGRect(x: bubbleX - revealOffset, y: y, width: bw, height: bh)

        let pad: CGFloat = 8
        let btn: CGFloat = 30
        playButton.frame = CGRect(x: pad, y: (bh - btn) / 2, width: btn, height: btn)
        let labelX = pad + btn + 8
        durationLabel.frame = CGRect(x: labelX, y: 0, width: max(0, bw - labelX - pad), height: bh)

        if !avatarView.isHidden {
            let ax = EventCell.outerMargin - revealOffset
            let ay = bubble.frame.maxY - EventCell.avatarSize
            avatarView.frame = CGRect(x: ax, y: ay, width: EventCell.avatarSize, height: EventCell.avatarSize)
        }

        revealTimeLabel.frame = CGRect(x: contentView.bounds.width - EventCell.maxReveal + 2,
                                        y: bubble.frame.minY, width: EventCell.maxReveal - 8,
                                        height: bubble.frame.height)
        revealTimeLabel.isHidden = revealOffset <= 0.5
    }
}

protocol AttachmentProgressCell: AnyObject {
    var mxc: String? { get }
    func setProgress(_ progress: Float?)
    func markDownloaded()
}

class FileEventCell: UITableViewCell, AttachmentProgressCell {
    static let bubbleHeight: CGFloat = 58
    static let bubbleMaxWidth: CGFloat = 250

    private let bubble = UIView()
    private let metaLabel = UILabel()
    private let avatarView = AvatarView()
    private let revealTimeLabel = UILabel()
    private let chip = UIView()
    private let chipLabel = UILabel()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var isOwnMessage = false
    private var hasMeta = false
    private var revealOffset: CGFloat = 0

    private var isDownloaded = false
    private var sizeText = ""

    var mxc: String?
    var onTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        metaLabel.backgroundColor = .clear
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.textColor = .gray
        contentView.addSubview(metaLabel)

        avatarView.isHidden = true
        contentView.addSubview(avatarView)

        bubble.layer.cornerRadius = 12
        bubble.layer.masksToBounds = true
        contentView.addSubview(bubble)

        chip.layer.cornerRadius = 6
        chip.layer.masksToBounds = true
        bubble.addSubview(chip)

        chipLabel.backgroundColor = .clear
        chipLabel.font = UIFont.boldSystemFont(ofSize: 11)
        chipLabel.textAlignment = .center
        chipLabel.adjustsFontSizeToFitWidth = true
        chip.addSubview(chipLabel)

        nameLabel.backgroundColor = .clear
        nameLabel.font = UIFont.boldSystemFont(ofSize: 14)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        bubble.addSubview(nameLabel)

        detailLabel.backgroundColor = .clear
        detailLabel.font = UIFont.systemFont(ofSize: 11)
        bubble.addSubview(detailLabel)

        progressView.isHidden = true
        bubble.addSubview(progressView)

        revealTimeLabel.backgroundColor = .clear
        revealTimeLabel.font = UIFont.systemFont(ofSize: 11)
        revealTimeLabel.textColor = .gray
        revealTimeLabel.textAlignment = .right
        revealTimeLabel.isHidden = true
        contentView.addSubview(revealTimeLabel)

        bubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bubbleTapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func bubbleTapped() { onTap?() }

    func configure(meta: String?, mxc: String, filename: String, mimeType: String, sizeBytes: Int,
                   downloaded: Bool, time: String, isOwn: Bool, avatarMxc: String?, senderName: String) {
        isOwnMessage = isOwn
        hasMeta = meta != nil
        metaLabel.isHidden = !hasMeta
        metaLabel.text = meta
        metaLabel.textAlignment = isOwn ? .right : .left
        revealTimeLabel.text = time

        self.mxc = mxc
        isDownloaded = downloaded
        sizeText = sizeBytes > 0 ? FileEventCell.humanSize(sizeBytes) : ""
        nameLabel.text = filename
        chipLabel.text = FileEventCell.typeTag(filename: filename, mimeType: mimeType)
        setProgress(nil)

        bubble.backgroundColor = isOwn ? UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
                                        : UIColor(white: 0.85, alpha: 1.0)
        nameLabel.textColor = isOwn ? .white : .black
        detailLabel.textColor = isOwn ? UIColor(white: 1.0, alpha: 0.75) : .darkGray
        chip.backgroundColor = isOwn ? UIColor(white: 1.0, alpha: 0.22) : .white
        chipLabel.textColor = isOwn ? .white : UIColor(white: 0.3, alpha: 1.0)
        progressView.progressTintColor = isOwn ? .white : UIColor(white: 0.35, alpha: 1.0)

        let showAvatar = !isOwn && hasMeta
        avatarView.isHidden = !showAvatar
        if showAvatar { avatarView.setAvatar(mxc: avatarMxc, name: senderName) }

        setNeedsLayout()
    }

    func setProgress(_ progress: Float?) {
        if let progress = progress {
            progressView.isHidden = false
            progressView.progress = progress
            detailLabel.text = "Downloading\u{2026} \(Int(progress * 100))%"
            return
        }
        progressView.isHidden = true
        let lead = isDownloaded ? "Saved" : "Tap to download"
        detailLabel.text = sizeText.isEmpty ? lead : "\(lead) \u{00B7} \(sizeText)"
    }

    func markDownloaded() {
        isDownloaded = true
        setProgress(nil)
    }

    private static func typeTag(filename: String, mimeType: String) -> String {
        var candidate = ""
        if let dot = filename.lastIndex(of: "."), dot < filename.index(before: filename.endIndex) {
            candidate = String(filename[filename.index(after: dot)...])
        }
        if candidate.isEmpty, let slash = mimeType.lastIndex(of: "/"),
           slash < mimeType.index(before: mimeType.endIndex) {
            candidate = String(mimeType[mimeType.index(after: slash)...])
        }
        if candidate.isEmpty { return "FILE" }
        return asciiUppercased(String(candidate.prefix(4)))
    }

    private static func asciiUppercased(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if scalar.value >= 97, scalar.value <= 122, let up = UnicodeScalar(scalar.value - 32) {
                out.append(up)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    private static func humanSize(_ bytes: Int) -> String {
        let b = Double(bytes)
        if b >= 1024 * 1024 * 1024 { return String(format: "%.1f GB", b / (1024 * 1024 * 1024)) }
        if b >= 1024 * 1024 { return String(format: "%.1f MB", b / (1024 * 1024)) }
        if b >= 1024 { return String(format: "%.0f KB", b / 1024) }
        return "\(bytes) B"
    }

    func setRevealOffset(_ offset: CGFloat) {
        guard offset != revealOffset else { return }
        revealOffset = offset
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxBubbleWidth = contentView.bounds.width * EventCell.bubbleWidthFraction
        let bw = min(FileEventCell.bubbleMaxWidth, maxBubbleWidth)
        let bh = FileEventCell.bubbleHeight

        let leftEdge = EventCell.outerMargin + (isOwnMessage ? 0 : EventCell.senderGutter)

        var y: CGFloat = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
        if hasMeta {
            let metaX = isOwnMessage ? contentView.bounds.width - EventCell.outerMargin - maxBubbleWidth
                                     : leftEdge
            metaLabel.frame = CGRect(x: metaX - revealOffset, y: y,
                                      width: maxBubbleWidth, height: EventCell.metaHeight)
            y += EventCell.metaHeight + EventCell.metaGap
        }

        let bubbleX = isOwnMessage ? contentView.bounds.width - bw - EventCell.outerMargin
                                    : leftEdge
        bubble.frame = CGRect(x: bubbleX - revealOffset, y: y, width: bw, height: bh)

        let pad: CGFloat = 8
        let chipSize: CGFloat = 38
        chip.frame = CGRect(x: pad, y: (bh - chipSize) / 2, width: chipSize, height: chipSize)
        chipLabel.frame = chip.bounds.insetBy(dx: 2, dy: 0)

        let textX = pad + chipSize + 8
        let textW = max(0, bw - textX - pad)
        nameLabel.frame = CGRect(x: textX, y: 9, width: textW, height: 18)
        detailLabel.frame = CGRect(x: textX, y: 28, width: textW, height: 14)
        progressView.frame = CGRect(x: textX, y: 46, width: textW, height: 2)

        if !avatarView.isHidden {
            let ax = EventCell.outerMargin - revealOffset
            let ay = bubble.frame.maxY - EventCell.avatarSize
            avatarView.frame = CGRect(x: ax, y: ay, width: EventCell.avatarSize, height: EventCell.avatarSize)
        }

        revealTimeLabel.frame = CGRect(x: contentView.bounds.width - EventCell.maxReveal + 2,
                                        y: bubble.frame.minY, width: EventCell.maxReveal - 8,
                                        height: bubble.frame.height)
        revealTimeLabel.isHidden = revealOffset <= 0.5
    }
}

class VideoEventCell: UITableViewCell, AttachmentProgressCell {
    private let bubble = UIView()
    private let posterView = UIImageView()
    private let playBadge = UIView()
    private let playIcon = UIImageView()
    private let durationLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let metaLabel = UILabel()
    private let avatarView = AvatarView()
    private let revealTimeLabel = UILabel()
    private var isOwnMessage = false
    private var hasMeta = false
    private var revealOffset: CGFloat = 0
    private var posterWidth = 0
    private var posterHeight = 0

    private var isDownloaded = false
    private var idleText = ""

    private var currentThumbnailMxc: String?
    private var inlinePlayer: MPMoviePlayerController?
    private var inlineAnimatedMxc: String?

    private var byteAnimatedMxc: String?
    private var byteProbeMxc: String?
    var mxc: String?
    var onTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        metaLabel.backgroundColor = .clear
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.textColor = .gray
        contentView.addSubview(metaLabel)

        avatarView.isHidden = true
        contentView.addSubview(avatarView)

        bubble.layer.cornerRadius = 12
        bubble.layer.masksToBounds = true
        bubble.backgroundColor = UIColor(white: 0.85, alpha: 1.0)
        contentView.addSubview(bubble)

        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        bubble.addSubview(posterView)

        playBadge.backgroundColor = UIColor(white: 0, alpha: 0.45)
        playBadge.layer.cornerRadius = VideoEventCell.badgeSize / 2
        playBadge.layer.masksToBounds = true
        bubble.addSubview(playBadge)

        playIcon.image = UIImage(named: "PlayWhite")
        playIcon.contentMode = .scaleAspectFit
        playBadge.addSubview(playIcon)

        durationLabel.backgroundColor = UIColor(white: 0, alpha: 0.45)
        durationLabel.font = UIFont.boldSystemFont(ofSize: 11)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.layer.cornerRadius = 4
        durationLabel.layer.masksToBounds = true
        bubble.addSubview(durationLabel)

        progressView.isHidden = true
        progressView.progressTintColor = .white
        bubble.addSubview(progressView)

        revealTimeLabel.backgroundColor = .clear
        revealTimeLabel.font = UIFont.systemFont(ofSize: 11)
        revealTimeLabel.textColor = .gray
        revealTimeLabel.textAlignment = .right
        revealTimeLabel.isHidden = true
        contentView.addSubview(revealTimeLabel)

        bubble.isUserInteractionEnabled = true
        bubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bubbleTapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopInlineAnimation()
        inlineAnimatedMxc = nil
        byteAnimatedMxc = nil
        byteProbeMxc = nil
    }

    @objc private func bubbleTapped() {

        guard byteAnimatedMxc != mxc else { return }
        onTap?()
    }

    private func beginByteAnimatedProbe(video: VideoAttachment) {
        guard !video.isAnimated else { return }
        let lowerMime = video.mimeType.lowercased()
        let lowerName = video.filename.lowercased()
        let ext = (lowerName as NSString).pathExtension.lowercased()

        let candidate = video.durationMs <= 0
            || lowerMime == "image/gif"
            || ext == "gif"
            || lowerName.hasSuffix(".gif.mp4")
            || lowerName.hasSuffix(".gif.mov")
            || lowerName.contains(".gif.")
        magnistraMediaTrace(
            "GIF_PROBE mime=\(lowerMime) ext=\(ext) durationMs=\(video.durationMs) candidate=\(candidate ? "YES" : "NO")"
        )
        guard candidate else { return }

        byteProbeMxc = video.mxc

        playBadge.isHidden = true
        durationLabel.isHidden = true

        if let path = MediaCache.shared.downloadedFilePath(
            mxc: video.mxc, filename: video.filename, mimeType: video.mimeType
        ) {
            DispatchQueue.main.async { [weak self] in
                self?.finishByteAnimatedProbe(path: path, video: video)
            }
            return
        }

        MediaCache.shared.downloadFile(
            mxc: video.mxc,
            filename: video.filename,
            mimeType: video.mimeType,
            progress: nil
        ) { [weak self] path in
            guard let self = self,
                  self.byteProbeMxc == video.mxc,
                  self.mxc == video.mxc,
                  let path = path else { return }
            self.finishByteAnimatedProbe(path: path, video: video)
        }
    }

    private func finishByteAnimatedProbe(path: String, video: VideoAttachment) {
        guard byteProbeMxc == video.mxc, mxc == video.mxc else { return }
        let kind = MediaCache.mediaKindAtPath(path: path)
        magnistraMediaTrace(
            "GIF_RESULT kind=\(kind) durationMs=\(video.durationMs)"
        )

        if kind == "gif", let image = MediaCache.animatedImageAtPath(path: path) {

            byteAnimatedMxc = video.mxc
            byteProbeMxc = nil
            inlineAnimatedMxc = nil
            stopInlineAnimation()
            currentThumbnailMxc = "__g4r13_gif__" + video.mxc
            posterView.isHidden = false
            posterView.image = nil
            posterView.image = image
            posterView.setNeedsDisplay()
            playBadge.isHidden = true
            durationLabel.isHidden = true
            setNeedsLayout()
            return
        }

        if kind == "iso-bmff", isShortSilentLoop(path: path) {
            byteAnimatedMxc = video.mxc
            byteProbeMxc = nil
            inlineAnimatedMxc = video.mxc
            posterView.image = nil
            posterView.isHidden = false
            posterView.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
            playBadge.isHidden = true
            durationLabel.isHidden = true
            MediaCache.shared.loadVideoBackedAnimatedWebP(
                mxc: video.mxc,
                filename: video.filename,
                mimeType: video.mimeType
            ) { [weak self] image, _ in
                guard let self = self,
                      self.mxc == video.mxc,
                      self.inlineAnimatedMxc == video.mxc,
                      let image = image else { return }
                self.applyVideoBackedAnimatedWebP(image, expectedMxc: video.mxc)
            }
            return
        }

        byteProbeMxc = nil
        byteAnimatedMxc = nil
        posterView.isHidden = false
        playBadge.isHidden = false
        durationLabel.isHidden = video.durationMs <= 0
    }

    private func isShortSilentLoop(path: String) -> Bool {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard !asset.tracks(withMediaType: .video).isEmpty else { return false }
        guard asset.tracks(withMediaType: .audio).isEmpty else { return false }
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 && seconds <= 60
    }

    private func beginInlineAnimation(video: VideoAttachment) {
        let lowerMime = video.mimeType.lowercased()
        let lowerName = video.filename.lowercased()
        if lowerMime == "video/webm" || lowerName.hasSuffix(".webm") {
            stopInlineAnimation()
            return
        }

        stopInlineAnimation()
        inlineAnimatedMxc = video.mxc
        posterView.isHidden = false
        posterView.image = nil
        posterView.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        playBadge.isHidden = true
        durationLabel.isHidden = true

        MediaCache.shared.loadVideoBackedAnimatedWebP(
            mxc: video.mxc,
            filename: video.filename,
            mimeType: video.mimeType
        ) { [weak self] image, _ in
            guard let self = self,
                  self.inlineAnimatedMxc == video.mxc,
                  self.mxc == video.mxc,
                  let image = image else { return }
            self.applyVideoBackedAnimatedWebP(image, expectedMxc: video.mxc)
        }
    }

    private func applyVideoBackedAnimatedWebP(_ image: UIImage, expectedMxc: String) {
        guard inlineAnimatedMxc == expectedMxc, mxc == expectedMxc else { return }

        posterView.stopAnimating()
        posterView.animationImages = nil
        posterView.animationDuration = 0
        posterView.animationRepeatCount = 0

        let frames = image.images ?? []
        guard frames.count > 1 else {
            posterView.image = image
            posterView.backgroundColor = .clear
            return
        }

        posterView.image = frames[0]
        posterView.animationImages = frames
        posterView.animationDuration = max(0.05, image.duration)
        posterView.animationRepeatCount = 0
        posterView.backgroundColor = .clear
        posterView.startAnimating()

        playBadge.isHidden = true
        durationLabel.isHidden = true
        posterView.isHidden = false
        magnistraMediaTrace(
            "VIDEO_WEBP_PRESENT frames=\(frames.count) duration=\(image.duration)"
        )
        setNeedsLayout()
    }

    private func startInlineAnimation(path: String, expectedMxc: String) {
        guard inlineAnimatedMxc == expectedMxc, mxc == expectedMxc else { return }
        stopInlineAnimation()
        inlineAnimatedMxc = expectedMxc

        guard let player = MPMoviePlayerController(contentURL: URL(fileURLWithPath: path)) else { return }
        player.controlStyle = .none
        player.repeatMode = .one
        player.shouldAutoplay = true
        player.scalingMode = .aspectFit
        player.view.backgroundColor = .clear
        player.view.isUserInteractionEnabled = false
        inlinePlayer = player
        bubble.addSubview(player.view)
        player.view.frame = bubble.bounds
        player.prepareToPlay()
        player.play()
        setNeedsLayout()
    }

    private func stopInlineAnimation() {
        inlinePlayer?.stop()
        inlinePlayer?.view.removeFromSuperview()
        inlinePlayer = nil
        posterView.stopAnimating()
        posterView.animationImages = nil
        posterView.animationDuration = 0
        posterView.animationRepeatCount = 0
    }

    func configure(meta: String?, video: VideoAttachment, downloaded: Bool, time: String, isOwn: Bool,
                   avatarMxc: String?, senderName: String) {
        isOwnMessage = isOwn
        hasMeta = meta != nil
        metaLabel.isHidden = !hasMeta
        metaLabel.text = meta
        metaLabel.textAlignment = isOwn ? .right : .left
        revealTimeLabel.text = time
        let showAvatar = !isOwn && hasMeta
        avatarView.isHidden = !showAvatar
        if showAvatar { avatarView.setAvatar(mxc: avatarMxc, name: senderName) }

        mxc = video.mxc
        isDownloaded = downloaded
        posterWidth = video.width
        posterHeight = video.height
        idleText = VideoEventCell.idleText(video: video)
        setProgress(nil)

        byteAnimatedMxc = nil
        byteProbeMxc = nil
        playBadge.isHidden = video.isAnimated
        durationLabel.isHidden = video.isAnimated
        posterView.isHidden = false
        if video.isAnimated {

            beginInlineAnimation(video: video)
        } else {
            posterView.backgroundColor = .clear
            inlineAnimatedMxc = nil
            stopInlineAnimation()
            beginByteAnimatedProbe(video: video)
        }

        if video.isAnimated {
            currentThumbnailMxc = nil
        } else {

            posterView.image = nil
            let posterKeyMxc = video.thumbnailMxc ?? video.mxc
            currentThumbnailMxc = posterKeyMxc
            let (reqW, reqH) = ImageEventCell.thumbnailRequestSize(
                imageWidth: video.width,
                imageHeight: video.height
            )
            if let thumb = video.thumbnailMxc {
                MediaCache.shared.loadThumbnail(mxc: thumb, width: reqW, height: reqH) { [weak self] image in
                    guard let self = self,
                          self.currentThumbnailMxc == thumb,
                          let image = image else { return }
                    self.posterView.image = image
                }
            } else {
                MediaCache.shared.loadCachedThumbnail(
                    mxc: video.mxc,
                    width: reqW,
                    height: reqH
                ) { [weak self] image in
                    guard let self = self,
                          self.currentThumbnailMxc == video.mxc else { return }
                    if let image = image {
                        self.posterView.image = image
                        return
                    }
                    guard MatrixE2EEManager.encryptedMediaRecord(for: video.mxc) == nil else { return }
                    MediaCache.shared.loadThumbnail(
                        mxc: video.mxc,
                        width: reqW,
                        height: reqH
                    ) { [weak self] generated in
                        guard let self = self,
                              self.currentThumbnailMxc == video.mxc,
                              let generated = generated else { return }
                        self.posterView.image = generated
                    }
                }
            }
        }

        setNeedsLayout()
    }

    func setProgress(_ progress: Float?) {
        if let progress = progress {
            progressView.isHidden = false
            progressView.progress = progress
            playBadge.isHidden = true
            durationLabel.text = " \(Int(progress * 100))% "
            return
        }
        progressView.isHidden = true
        playBadge.isHidden = false
        durationLabel.text = " \(idleText) "
        setNeedsLayout()
    }

    func markDownloaded() {
        isDownloaded = true
        setProgress(nil)
    }

    func setRevealOffset(_ offset: CGFloat) {
        guard offset != revealOffset else { return }
        revealOffset = offset
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxBubbleWidth = contentView.bounds.width * EventCell.bubbleWidthFraction
        let box = ImageEventCell.displaySize(imageWidth: posterWidth, imageHeight: posterHeight,
                                             maxWidth: maxBubbleWidth)

        let leftEdge = EventCell.outerMargin + (isOwnMessage ? 0 : EventCell.senderGutter)

        var y: CGFloat = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
        if hasMeta {
            let metaX = isOwnMessage ? contentView.bounds.width - EventCell.outerMargin - maxBubbleWidth
                                     : leftEdge
            metaLabel.frame = CGRect(x: metaX - revealOffset, y: y,
                                      width: maxBubbleWidth, height: EventCell.metaHeight)
            y += EventCell.metaHeight + EventCell.metaGap
        }

        let bubbleX = isOwnMessage ? contentView.bounds.width - box.width - EventCell.outerMargin
                                    : leftEdge
        bubble.frame = CGRect(x: bubbleX - revealOffset, y: y, width: box.width, height: box.height)
        posterView.frame = bubble.bounds
        inlinePlayer?.view.frame = bubble.bounds

        if inlineAnimatedMxc == mxc {
            playBadge.isHidden = true
            durationLabel.isHidden = true
        }

        let badge = VideoEventCell.badgeSize
        playBadge.frame = CGRect(x: (box.width - badge) / 2, y: (box.height - badge) / 2,
                                  width: badge, height: badge)

        playIcon.frame = playBadge.bounds.insetBy(dx: 10, dy: 10).offsetBy(dx: 1, dy: 0)

        let pillWidth = min(box.width - 12, durationLabel.sizeThatFits(CGSize(width: box.width,
                                                                             height: 16)).width + 8)
        durationLabel.frame = CGRect(x: 6, y: box.height - 22, width: max(28, pillWidth), height: 16)
        progressView.frame = CGRect(x: 6, y: box.height - 4, width: box.width - 12, height: 2)

        if !avatarView.isHidden {
            let ax = EventCell.outerMargin - revealOffset
            let ay = bubble.frame.maxY - EventCell.avatarSize
            avatarView.frame = CGRect(x: ax, y: ay, width: EventCell.avatarSize, height: EventCell.avatarSize)
        }

        revealTimeLabel.frame = CGRect(x: contentView.bounds.width - EventCell.maxReveal + 2,
                                        y: bubble.frame.minY, width: EventCell.maxReveal - 8,
                                        height: bubble.frame.height)
        revealTimeLabel.isHidden = revealOffset <= 0.5
    }

    private static let badgeSize: CGFloat = 44

    private static func idleText(video: VideoAttachment) -> String {
        if video.isAnimated { return "GIF" }
        if video.durationMs > 0 {
            let total = video.durationMs / 1000
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        if video.sizeBytes > 0 { return humanSize(video.sizeBytes) }
        return "Video"
    }

    private static func humanSize(_ bytes: Int) -> String {
        let b = Double(bytes)
        if b >= 1024 * 1024 { return String(format: "%.1f MB", b / (1024 * 1024)) }
        if b >= 1024 { return String(format: "%.0f KB", b / 1024) }
        return "\(bytes) B"
    }
}