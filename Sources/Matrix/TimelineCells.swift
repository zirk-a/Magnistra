// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: event cells (text and image).
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



class EventCell: UITableViewCell {
    static let outerMargin: CGFloat = 12
    static let innerPadding: CGFloat = 10
    static let bubbleWidthFraction: CGFloat = 0.75
    static let metaHeight: CGFloat = 15
    static let metaGap: CGFloat = 2
    static let quoteHeight: CGFloat = 14
    static let quoteGap: CGFloat = 4
    static let statusHeight: CGFloat = 13
    static let statusGap: CGFloat = 3

    static let bodyFont = UIFont.systemFont(ofSize: 15)
    static let topMargin: CGFloat = 8
    static let groupedTopMargin: CGFloat = 2
    static let bottomMargin: CGFloat = 2
    static let dateRowHeight: CGFloat = 28
    static let maxReveal: CGFloat = 62
    static let avatarSize: CGFloat = 28
    static let avatarGap: CGFloat = 6

    static var senderGutter: CGFloat { return avatarSize + avatarGap }

    static let groupingWindowMs: Double = 5 * 60 * 1000

    private static let measuringLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        return label
    }()
    private static var bodySizeCache: [String: CGSize] = [:]

    static func measureBody(_ text: String, font: UIFont, width: CGFloat) -> CGSize {
        let w = max(1, width)

        let key = "\(Int(w))|\(font.pointSize)|\(text)"
        if let cached = bodySizeCache[key] { return cached }
        measuringLabel.font = font
        measuringLabel.text = text
        let size = measuringLabel.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))

        if bodySizeCache.count > 800 { bodySizeCache.removeAll() }
        bodySizeCache[key] = size
        return size
    }

    private let bubble = UIView()
    private let metaLabel = UILabel()
    private let bodyLabel = UILabel()

    private let quoteLabel = UILabel()

    private let statusLabel = UILabel()

    private let avatarView = AvatarView()

    private let revealTimeLabel = UILabel()
    private var isOwnMessage = false
    private var hasMeta = false
    private var revealOffset: CGFloat = 0

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

        quoteLabel.backgroundColor = .clear
        quoteLabel.font = UIFont.systemFont(ofSize: 11)
        quoteLabel.numberOfLines = 1
        quoteLabel.lineBreakMode = .byTruncatingTail
        quoteLabel.isHidden = true
        bubble.addSubview(quoteLabel)

        bodyLabel.backgroundColor = .clear
        bodyLabel.font = EventCell.bodyFont
        bodyLabel.numberOfLines = 0
        bubble.addSubview(bodyLabel)

        statusLabel.backgroundColor = .clear
        statusLabel.font = UIFont.systemFont(ofSize: 10)
        statusLabel.numberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textAlignment = .right
        statusLabel.isHidden = true
        bubble.addSubview(statusLabel)

        revealTimeLabel.backgroundColor = .clear
        revealTimeLabel.font = UIFont.systemFont(ofSize: 11)
        revealTimeLabel.textColor = .gray
        revealTimeLabel.textAlignment = .right
        revealTimeLabel.isHidden = true
        contentView.addSubview(revealTimeLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(meta: String?, quote: String?, body: String, time: String, isOwn: Bool,
                   avatarMxc: String?, senderName: String,
                   status: String? = nil, statusIsError: Bool = false) {
        isOwnMessage = isOwn
        hasMeta = meta != nil
        metaLabel.isHidden = !hasMeta
        metaLabel.text = meta
        metaLabel.textAlignment = isOwn ? .right : .left
        quoteLabel.isHidden = quote == nil
        quoteLabel.text = quote

        quoteLabel.textColor = isOwn ? UIColor(white: 1.0, alpha: 0.75)
                                     : UIColor(white: 0.35, alpha: 1.0)
        bodyLabel.text = body
        bodyLabel.textColor = isOwn ? .white : .black
        bubble.backgroundColor = isOwn ? UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
                                        : UIColor(white: 0.85, alpha: 1.0)
        statusLabel.isHidden = status == nil
        statusLabel.text = status

        statusLabel.textColor = statusIsError ? .white : UIColor(white: 1.0, alpha: 0.75)

        bubble.alpha = status == nil ? 1.0 : 0.7
        revealTimeLabel.text = time

        let showAvatar = !isOwn && hasMeta
        avatarView.isHidden = !showAvatar
        if showAvatar { avatarView.setAvatar(mxc: avatarMxc, name: senderName) }
        setNeedsLayout()
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
        let maxInnerWidth = maxBubbleWidth - EventCell.innerPadding * 2

        let bodySize = EventCell.measureBody(bodyLabel.text ?? "", font: EventCell.bodyFont,
                                             width: maxInnerWidth)

        var contentWidth = ceil(bodySize.width)
        let quoteBlock: CGFloat = quoteLabel.isHidden ? 0 : EventCell.quoteHeight + EventCell.quoteGap
        if !quoteLabel.isHidden {
            let quoteSize = quoteLabel.sizeThatFits(CGSize(width: maxInnerWidth,
                                                           height: EventCell.quoteHeight))
            contentWidth = max(contentWidth, ceil(quoteSize.width))
        }

        let statusBlock: CGFloat = statusLabel.isHidden ? 0 : EventCell.statusHeight + EventCell.statusGap
        if !statusLabel.isHidden {
            let statusSize = statusLabel.sizeThatFits(CGSize(width: maxInnerWidth,
                                                             height: EventCell.statusHeight))
            contentWidth = max(contentWidth, ceil(statusSize.width))
        }
        let innerWidth = min(contentWidth, maxInnerWidth)
        let bubbleWidth = innerWidth + EventCell.innerPadding * 2
        let bubbleHeight = quoteBlock + ceil(bodySize.height) + statusBlock + EventCell.innerPadding * 2

        let leftEdge = EventCell.outerMargin + (isOwnMessage ? 0 : EventCell.senderGutter)

        var y: CGFloat = hasMeta ? EventCell.topMargin : EventCell.groupedTopMargin
        if hasMeta {

            let metaX = isOwnMessage ? contentView.bounds.width - EventCell.outerMargin - maxBubbleWidth
                                     : leftEdge
            metaLabel.frame = CGRect(x: metaX - revealOffset, y: y,
                                      width: maxBubbleWidth, height: EventCell.metaHeight)
            y += EventCell.metaHeight + EventCell.metaGap
        }

        let bubbleX = isOwnMessage ? contentView.bounds.width - bubbleWidth - EventCell.outerMargin
                                    : leftEdge
        bubble.frame = CGRect(x: bubbleX - revealOffset, y: y, width: bubbleWidth, height: bubbleHeight)
        if !quoteLabel.isHidden {
            quoteLabel.frame = CGRect(x: EventCell.innerPadding, y: EventCell.innerPadding,
                                       width: innerWidth, height: EventCell.quoteHeight)
        }
        bodyLabel.frame = CGRect(x: EventCell.innerPadding,
                                  y: EventCell.innerPadding + quoteBlock,
                                  width: innerWidth, height: ceil(bodySize.height))
        if !statusLabel.isHidden {
            statusLabel.frame = CGRect(x: EventCell.innerPadding,
                                       y: bodyLabel.frame.maxY + EventCell.statusGap,
                                       width: innerWidth, height: EventCell.statusHeight)
        }

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

class ImageEventCell: UITableViewCell {

    static let maxHeight: CGFloat = 260
    static func displaySize(imageWidth: Int, imageHeight: Int, maxWidth: CGFloat) -> CGSize {
        var w = CGFloat(imageWidth)
        var h = CGFloat(imageHeight)
        if w <= 0 || h <= 0 {
            w = maxWidth
            h = maxWidth * 2.0 / 3.0
        }
        let scale = min(maxWidth / w, maxHeight / h, 1.0)
        return CGSize(width: max(1, floor(w * scale)), height: max(1, floor(h * scale)))
    }

    static func thumbnailRequestSize(imageWidth: Int, imageHeight: Int) -> (Int, Int) {
        let box = displaySize(imageWidth: imageWidth, imageHeight: imageHeight,
                              maxWidth: UIScreen.main.bounds.width * EventCell.bubbleWidthFraction)
        return (Int(box.width * 2), Int(box.height * 2))
    }

    private let bubble = UIView()
    private let imageView2 = UIImageView()
    private let metaLabel = UILabel()
    private let avatarView = AvatarView()
    private let revealTimeLabel = UILabel()
    private var isOwnMessage = false
    private var hasMeta = false
    private var imageWidth = 0
    private var imageHeight = 0
    private var revealOffset: CGFloat = 0

    private var currentMxc: String?

    private var currentAnimatedFullMxc: String?

    private var stickerPlaceholderActive = false
    var onMediaVisualReady: (() -> Void)?

    var onTap: (() -> Void)?

    var displayedImage: UIImage? { return imageView2.image }

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

        imageView2.contentMode = .scaleAspectFill
        imageView2.clipsToBounds = true
        bubble.addSubview(imageView2)

        bubble.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        bubble.addGestureRecognizer(tap)

        revealTimeLabel.backgroundColor = .clear
        revealTimeLabel.font = UIFont.systemFont(ofSize: 11)
        revealTimeLabel.textColor = .gray
        revealTimeLabel.textAlignment = .right
        revealTimeLabel.isHidden = true
        contentView.addSubview(revealTimeLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentAnimatedFullMxc = nil
        stickerPlaceholderActive = false
        imageView2.stopAnimating()
        imageView2.animationImages = nil
        imageView2.animationDuration = 0
        imageView2.animationRepeatCount = 0

        imageView2.layer.cornerRadius = 0
        imageView2.clipsToBounds = false
        onMediaVisualReady = nil
        onTap = nil
    }

    private func revealStickerContentIfNeeded() {
        guard stickerPlaceholderActive else { return }
        stickerPlaceholderActive = false
        bubble.backgroundColor = .clear
        bubble.layer.cornerRadius = 0
    }

    private func applyStickerVisual(_ image: UIImage) {
        imageView2.stopAnimating()
        imageView2.animationImages = nil
        imageView2.animationDuration = 0
        imageView2.animationRepeatCount = 0

        let frames = image.images ?? []
        if frames.count > 1 {
            imageView2.image = frames[0]
            imageView2.animationImages = frames
            imageView2.animationDuration = max(0.05, image.duration)
            imageView2.animationRepeatCount = 0
            imageView2.startAnimating()
            magnistraMediaTrace(
                "STICKER_REARM animated=YES frames=\(frames.count) duration=\(image.duration)"
            )
        } else {
            imageView2.image = image
            magnistraMediaTrace("STICKER_REARM animated=NO frames=\(frames.count)")
        }
        revealStickerContentIfNeeded()
    }

    @objc private func handleTap() { onTap?() }

    func configure(meta: String?, mxc: String, imageWidth: Int, imageHeight: Int,
                   isSticker: Bool, isTrueSticker: Bool, inlineAnimated: Bool,
                   time: String, isOwn: Bool,
                   avatarMxc: String?, senderName: String) {
        isOwnMessage = isOwn

        stickerPlaceholderActive = isSticker
        bubble.backgroundColor = isSticker
            ? UIColor(white: 0.88, alpha: 1.0)
            : UIColor(white: 0.85, alpha: 1.0)
        bubble.layer.cornerRadius = isSticker ? 10 : 12
        imageView2.contentMode = isSticker ? .scaleAspectFit : .scaleAspectFill
        hasMeta = meta != nil
        metaLabel.isHidden = !hasMeta
        metaLabel.text = meta
        metaLabel.textAlignment = isOwn ? .right : .left
        revealTimeLabel.text = time
        let showAvatar = !isOwn && hasMeta
        avatarView.isHidden = !showAvatar
        if showAvatar { avatarView.setAvatar(mxc: avatarMxc, name: senderName) }
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        currentMxc = mxc
        imageView2.image = nil

        let (reqW, reqH) = ImageEventCell.thumbnailRequestSize(imageWidth: imageWidth, imageHeight: imageHeight)

        if inlineAnimated {
            let isVideoBackedAnimatedTransport =
                MediaCache.shared.videoBackedAnimatedInfo(for: mxc) != nil

            if isVideoBackedAnimatedTransport {
                imageView2.layer.cornerRadius = 10
                imageView2.clipsToBounds = true
            } else if isSticker {
                imageView2.layer.cornerRadius = 0
                imageView2.clipsToBounds = false
            }
            let preserveCurrentVideoBackedAnimation =
                isVideoBackedAnimatedTransport
                && currentAnimatedFullMxc == mxc
                && (imageView2.animationImages?.count ?? 0) > 1

            if preserveCurrentVideoBackedAnimation {

                revealStickerContentIfNeeded()
                if !imageView2.isAnimating {
                    imageView2.startAnimating()
                }
                setNeedsLayout()
                return
            }

            currentAnimatedFullMxc = nil
            if isSticker {
                imageView2.stopAnimating()
                imageView2.animationImages = nil
                imageView2.animationDuration = 0
                imageView2.animationRepeatCount = 0
            }
            imageView2.image = nil

            if isSticker && !isVideoBackedAnimatedTransport {
                MediaCache.shared.loadCachedThumbnail(mxc: mxc, width: reqW, height: reqH) { [weak self] cached in
                    guard let self = self,
                          self.currentMxc == mxc,
                          self.currentAnimatedFullMxc != mxc else { return }
                    if let cached = cached {
                        self.imageView2.image = cached
                        self.revealStickerContentIfNeeded()
                        self.setNeedsLayout()
                        self.layoutIfNeeded()
                    } else {
                        MediaCache.shared.loadThumbnail(mxc: mxc, width: reqW, height: reqH) { [weak self] poster in
                            guard let self = self,
                                  self.currentMxc == mxc,
                                  self.currentAnimatedFullMxc != mxc,
                                  let poster = poster else { return }
                            self.imageView2.image = poster
                            self.revealStickerContentIfNeeded()
                            self.setNeedsLayout()
                            self.layoutIfNeeded()
                        }
                    }
                }
            }

            MediaCache.shared.loadFullAnimatedImage(
                mxc: mxc,
                trueSticker: isTrueSticker
            ) { [weak self] image in
                guard let self = self,
                      self.currentMxc == mxc,
                      let image = image else { return }
                self.currentAnimatedFullMxc = mxc
                if isSticker {
                    let keepRunningVideoBackedAnimation =
                        MediaCache.shared.videoBackedAnimatedInfo(for: mxc) != nil
                        && self.imageView2.isAnimating
                        && (self.imageView2.animationImages?.count ?? 0) > 1
                    if keepRunningVideoBackedAnimation {
                        self.revealStickerContentIfNeeded()
                    } else {
                        self.applyStickerVisual(image)
                    }
                } else {
                    self.imageView2.image = nil
                    self.imageView2.image = image
                    self.revealStickerContentIfNeeded()
                    self.imageView2.setNeedsDisplay()
                }
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.onMediaVisualReady?()
            }
        } else {
            currentAnimatedFullMxc = nil
            MediaCache.shared.loadThumbnail(mxc: mxc, width: reqW, height: reqH) { [weak self] image in
                guard let self = self else { return }
                guard self.currentMxc == mxc, let image = image else { return }
                self.imageView2.image = image
                self.revealStickerContentIfNeeded()
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
        setNeedsLayout()
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
        let box = ImageEventCell.displaySize(imageWidth: imageWidth, imageHeight: imageHeight, maxWidth: maxBubbleWidth)

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
        imageView2.frame = bubble.bounds

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