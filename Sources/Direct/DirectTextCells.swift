// Overview: Direct thread: base message cell, text cell and unsupported-message cell.
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



class MagnistraDirectMessageCell:
    UITableViewCell
{
    static let previewQueue:
        OperationQueue =
            {
                let queue =
                    OperationQueue()

                queue.maxConcurrentOperationCount =
                    1

                return queue
            }()

    private static let previewCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    private static var previewApplicationSuspended =
        false

    let bubbleView =
        UIView()

    var outgoing =
        false

    private var senderHeaderName: String? = nil
    private var senderHeaderLabel: UILabel? = nil

    func setSenderHeader(_ name: String?) {
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        senderHeaderName = clean.isEmpty ? nil : clean
        if senderHeaderName != nil && senderHeaderLabel == nil {
            let label = UILabel(frame: .zero)
            label.font = UIFont.boldSystemFont(ofSize: 11.5)
            label.textColor = UIColor(white: 0.42, alpha: 1.0)
            label.backgroundColor = UIColor.clear
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.isUserInteractionEnabled = false
            addSubview(label)
            senderHeaderLabel = label
        }
        senderHeaderLabel?.text = senderHeaderName
        senderHeaderLabel?.isHidden = senderHeaderName == nil
        setNeedsLayout()
    }

    override init(
        style:
            UITableViewCell.CellStyle,
        reuseIdentifier:
            String?
    ) {
        super.init(
            style: style,
            reuseIdentifier:
                reuseIdentifier
        )

        backgroundColor =
            UIColor.clear

        contentView.backgroundColor =
            UIColor.clear

        selectionStyle =
            .none

        bubbleView.layer.masksToBounds =
            true

        contentView.addSubview(
            bubbleView
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    static func setPreviewApplicationSuspended(
        _ suspended:
            Bool
    ) {
        previewApplicationSuspended =
            suspended
    }

    static func isPreviewApplicationSuspended()
        -> Bool
    {
        return
            previewApplicationSuspended
    }

    static func decodedPreviewImage(
        atPath path:
            String
    ) -> UIImage? {
        if let webp = magnistraDirectDecodedWebP(at: path) {
            MagnistraDirectMediaTrace.record(webp.images != nil ?
                "DECODE_ANIMATED_WEBP" : "DECODE_STATIC_WEBP")
            return webp
        }

        MagnistraDirectMediaTrace.record("DECODE_ATTEMPT")

        if let animated = MagnistraDirectMessageCell.magnistraDirectAnimatedGIF(at: path) {
            MagnistraDirectMediaTrace.record("DECODE_ANIMATED_GIF")
            return animated
        }

        let source: UIImage
        if let normal = UIImage(contentsOfFile: path) {
            source = normal
        } else {
            let fileURL = URL(fileURLWithPath: path)
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let firstFrame = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else { return nil }
            source = UIImage(cgImage: firstFrame)
        }

        let size =
            source.size

        let longest =
            max(
                size.width,
                size.height
            )

        guard longest > 0.0
        else {
            return source
        }

        let maximum:
            CGFloat =
                440.0

        let ratio =
            min(
                1.0,
                maximum /
                longest
            )

        let target =
            CGSize(
                width:
                    max(
                        1.0,
                        floor(
                            size.width *
                            ratio
                        )
                    ),
                height:
                    max(
                        1.0,
                        floor(
                            size.height *
                            ratio
                        )
                    )
            )

        UIGraphicsBeginImageContextWithOptions(
            target,
            false,
            1.0
        )

        source.draw(
            in:
                CGRect(
                    origin:
                        CGPoint.zero,
                    size:
                        target
                )
        )

        let decoded =
            UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        MagnistraDirectMediaTrace.record("DECODE_STATIC_IMAGE")
        return decoded ?? source
    }

    static func prewarmPreview(
        _ message:
            MagnistraDirectMessage
    ) {
        if message.previewURL != nil {
            MagnistraDirectMediaTrace.record("PREWARM", id: message.messageID,
                info: "preview=" + MagnistraDirectMediaTrace.urlTag(message.previewURL))
        }

        guard
            magnistraDirectRenderKind(
                message
            ) !=
                .unsupported,
            let remoteURL =
                message.previewURL,
            !remoteURL.isEmpty
        else {
            return
        }

        let stableKey =
            "direct-preview:" +
            message.messageID

        let key =
            stableKey as NSString

        if
            previewCache.object(
                forKey:
                    key
            ) != nil
        {
            return
        }

        previewQueue.addOperation {
            autoreleasepool {
                if
                    previewCache.object(
                        forKey:
                            key
                    ) != nil
                {
                    return
                }

                guard
                    let path =
                        MagnistraDirectMediaDiskCache.imagePath(remote: remoteURL, key: stableKey),
                    let image =
                        decodedPreviewImage(
                            atPath:
                                path
                        )
                else {
                    return
                }

                let cost =
                    max(
                        1,
                        Int(image.size.width * image.size.height * 4.0) * max(1, image.images?.count ?? 1)
                    )

                previewCache.setObject(
                    image,
                    forKey:
                        key,
                    cost:
                        cost
                )
            }
        }
    }

    static func seedPreview(
        _ image: UIImage,
        messageID: String
    ) {
        let key =
            ("direct-preview:" + messageID)
                as NSString

        let cost =
            max(
                1,
                Int(image.size.width * image.size.height * 4.0) * max(1, image.images?.count ?? 1)
            )

        previewCache.setObject(
            image,
            forKey:
                key,
            cost:
                cost
        )
    }

    static func requestPreview(
        _ message:
            MagnistraDirectMessage,
        completion:
            @escaping (UIImage?) -> Void
    ) {
        MagnistraDirectMediaTrace.record("REQUEST_PREVIEW", id: message.messageID,
            info: "preview=" + MagnistraDirectMediaTrace.urlTag(message.previewURL))

        guard
            magnistraDirectRenderKind(
                message
            ) !=
                .unsupported,
            let remoteURL =
                message.previewURL,
            !remoteURL.isEmpty
        else {
            completion(nil)
            return
        }

        let stableKey =
            "direct-preview:" +
            message.messageID

        let key =
            stableKey as NSString

        if
            let ready =
                previewCache.object(
                    forKey:
                        key
                )
        {
            completion(ready)
            return
        }

        previewQueue.addOperation {
            autoreleasepool {
                guard
                    let path =
                        MagnistraDirectMediaDiskCache.imagePath(remote: remoteURL, key: stableKey),
                    let image =
                        decodedPreviewImage(
                            atPath:
                                path
                        )
                else {
                    OperationQueue.main
                        .addOperation {
                            completion(nil)
                        }
                    return
                }

                let cost =
                    max(
                        1,
                        Int(image.size.width * image.size.height * 4.0) * max(1, image.images?.count ?? 1)
                    )

                previewCache.setObject(
                    image,
                    forKey:
                        key,
                    cost:
                        cost
                )

                OperationQueue.main
                    .addOperation {
                        completion(image)
                    }
            }
        }
    }

    func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        outgoing =
            message.isOutgoing
    }

    func applyPendingPreviewIfNeeded() {
    }

    func alignedX(
        width:
            CGFloat
    ) -> CGFloat {
        return
            outgoing
                ? max(
                    8.0,
                    bounds.size.width -
                    width -
                    10.0
                )
                : 10.0
    }

    func applyTextBubbleStyle() {
        bubbleView.layer.cornerRadius =
            9.0

        bubbleView.layer.borderWidth =
            0.5

        if outgoing {

            bubbleView.backgroundColor =
                UIColor(red: 80.0/255.0, green: 91.0/255.0,
                        blue: 241.0/255.0, alpha: 1.0)

            bubbleView.layer.borderColor =
                UIColor(
                    red:
                        0.16,
                    green:
                        0.34,
                    blue:
                        0.52,
                    alpha:
                        1.0
                )
                .cgColor
        } else {
            bubbleView.backgroundColor =
                UIColor(
                    white:
                        0.90,
                    alpha:
                        1.0
                )

            bubbleView.layer.borderColor =
                UIColor(
                    white:
                        0.76,
                    alpha:
                        1.0
                )
                .cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        contentView.transform = CGAffineTransform.identity
        senderHeaderLabel?.frame = CGRect(x: 12.0, y: 1.0,
            width: max(1.0, bounds.width - 24.0), height: 16.0)
        if let label = senderHeaderLabel { bringSubviewToFront(label) }
        magnistraDirectKeepBubbleInside()
    }

    func magnistraDirectKeepBubbleInside() {
        let availableWidth = contentView.bounds.width
        if availableWidth < 120 { return }
        let leftEdge: CGFloat = 10.0
        let rightEdge = availableWidth - 10.0
        let maximumWidth = rightEdge - leftEdge
        var rect = bubbleView.frame
        if rect.width <= 0 || rect.height <= 0 { return }
        var changed = false
        if rect.width > maximumWidth {
            rect.size.width = maximumWidth
            changed = true
        }
        if rect.origin.x < leftEdge || rect.maxX > rightEdge {
            rect.origin.x = outgoing ? (rightEdge - rect.width) : leftEdge
            changed = true
        }
        if changed { bubbleView.frame = rect }

        if senderHeaderName != nil && bubbleView.frame.origin.y < 17.0 {
            var shifted = bubbleView.frame
            shifted.origin.y += 18.0
            bubbleView.frame = shifted
        }

        bubbleView.clipsToBounds = true
        contentView.clipsToBounds = false
        clipsToBounds = false
    }

    private static func magnistraDirectDecodedWebP(at path: String) -> UIImage? {

        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        let magic = handle.readData(ofLength: 12)
        handle.closeFile()
        let header = [UInt8](magic)
        guard header.count == 12 &&
            Array(header[0..<4]) == [82, 73, 70, 70] &&
            Array(header[8..<12]) == [87, 69, 66, 80],
            let bytes = NSData(contentsOfFile: path),
            bytes.length >= 16 && bytes.length <= 4 * 1024 * 1024 else { return nil }
        var width: Int32 = 0
        var height: Int32 = 0
        var count: Int32 = 0
        guard let decoder = MagnistraDirectWebPAnimOpen(
            bytes.bytes.assumingMemoryBound(to: UInt8.self),
            bytes.length, &width, &height, &count) else {
            MagnistraDirectMediaTrace.record("WEBP_DECODER_OPEN_FAILED")
            return nil
        }
        defer { MagnistraDirectWebPAnimClose(decoder) }
        guard width > 0 && height > 0 && count > 0 && count <= 400 else { return nil }
        let w = Int(width)
        let h = Int(height)
        let pixelsPerFrame = w * h * 4
        guard pixelsPerFrame <= 512 * 512 * 4 else { return nil }
        let maxFrames = 24
        let sampleStep = max(1, (Int(count) + maxFrames - 1) / maxFrames)
        var frames: [UIImage] = []
        frames.reserveCapacity(min(Int(count), maxFrames))
        var lastTimestamp: Int32 = 0
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(CGBitmapInfo.byteOrder32Big)
        for index in 0..<Int(count) {
            var pixels: UnsafePointer<UInt8>? = nil
            var ms: Int32 = 0
            guard MagnistraDirectWebPAnimNext(decoder, &pixels, &ms) != 0,
                  let decoded = pixels else { return nil }
            lastTimestamp = ms
            if index % sampleStep != 0 || frames.count >= maxFrames { continue }
            let frameBytes = Data(bytes: decoded, count: pixelsPerFrame)
            guard let provider = CGDataProvider(data: frameBytes as CFData),
                  let cg = CGImage(width: w, height: h,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: colorSpace, bitmapInfo: bitmap, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { return nil }
            var image = UIImage(cgImage: cg)
            let longest = max(image.size.width, image.size.height)
            if longest > 160.0 {
                let ratio = 160.0 / longest
                let target = CGSize(width: max(1.0, floor(image.size.width * ratio)),
                                    height: max(1.0, floor(image.size.height * ratio)))
                UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
                image.draw(in: CGRect(origin: CGPoint.zero, size: target))
                if let downsampled = UIGraphicsGetImageFromCurrentImageContext() {
                    image = downsampled
                }
                UIGraphicsEndImageContext()
            }
            frames.append(image)
        }
        guard let first = frames.first else { return nil }
        if frames.count < 2 { return first }
        let duration = max(0.12, min(25.0, Double(lastTimestamp) / 1000.0))
        return UIImage.animatedImage(with: frames, duration: duration) ?? first
    }

    private static func magnistraDirectAnimatedGIF(at path: String) -> UIImage? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        if count < 2 { return nil }
        let maxFrames = 16
        let step = max(1, (count + maxFrames - 1) / maxFrames)
        let thumbnailOptions: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: 320,
            kCGImageSourceCreateThumbnailWithTransform as String: true
        ]
        var frames: [UIImage] = []
        var total: TimeInterval = 0.0
        for index in stride(from: 0, to: count, by: step) {
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                src, index, thumbnailOptions as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: thumbnail))
            var seconds: TimeInterval = 0.10
            if let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [String: Any],
               let info = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                if let delay = (info[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)
                    ?? (info[kCGImagePropertyGIFDelayTime as String] as? NSNumber) {
                    seconds = delay.doubleValue
                }
            }
            total += Double(step) * min(1.0, max(0.06, seconds))
        }
        guard frames.count >= 2 else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(0.12, total))
    }
}

class MagnistraDirectTextCell:
    MagnistraDirectMessageCell
{
    let messageLabel =
        UILabel()

    override init(
        style:
            UITableViewCell.CellStyle,
        reuseIdentifier:
            String?
    ) {
        super.init(
            style: style,
            reuseIdentifier:
                reuseIdentifier
        )

        messageLabel.backgroundColor =
            UIColor.clear

        messageLabel.font =
            UIFont.systemFont(
                ofSize:
                    16.0
            )

        messageLabel.numberOfLines =
            0

        bubbleView.addSubview(
            messageLabel
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    func configureText(
        _ text:
            String,
        outgoing:
            Bool
    ) {
        self.outgoing =
            outgoing

        applyTextBubbleStyle()

        messageLabel.text =
            text

        messageLabel.textColor =
            outgoing
                ? UIColor.white
                : UIColor(
                    white:
                        0.13,
                    alpha:
                        1.0
                )

        setNeedsLayout()
    }

    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        configureText(
            message.text,
            outgoing:
                message.isOutgoing
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let maxBubbleWidth =
            max(
                90.0,
                bounds.size.width *
                0.74
            )

        let fit =
            messageLabel.sizeThatFits(
                CGSize(
                    width:
                        maxBubbleWidth -
                        20.0,
                    height:
                        10000.0
                )
            )

        let width =
            min(
                maxBubbleWidth,
                max(
                    42.0,
                    fit.width +
                    20.0
                )
            )

        let height =
            max(
                34.0,
                fit.height +
                16.0
            )

        bubbleView.frame =
            CGRect(
                x:
                    alignedX(
                        width:
                            width
                    ),
                y:
                    5.0,
                width:
                    width,
                height:
                    height
            )

        messageLabel.frame =
            CGRect(
                x: 10.0,
                y: 8.0,
                width:
                    max(
                        1.0,
                        width -
                        20.0
                    ),
                height:
                    max(
                        1.0,
                        fit.height
                    )
            )
            magnistraDirectKeepBubbleInside()

        bubbleView.layer.cornerRadius = min(20.0, bubbleView.bounds.height / 2.0)
    }

    static func rowHeight(
        for message:
            MagnistraDirectMessage,
        width:
            CGFloat
    ) -> CGFloat {
        let label =
            UILabel()

        label.font =
            UIFont.systemFont(
                ofSize:
                    16.0
            )

        label.numberOfLines =
            0

        label.text =
            message.text

        let maxBubbleWidth =
            max(
                90.0,
                width *
                0.74
            )

        let fit =
            label.sizeThatFits(
                CGSize(
                    width:
                        maxBubbleWidth -
                        20.0,
                    height:
                        10000.0
                )
            )

        return
            max(
                44.0,
                fit.height +
                26.0
            )
    }
}

final class MagnistraDirectUnsupportedCell:
    MagnistraDirectTextCell
{
    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        configureText(
            "Unsupported message",
            outgoing:
                message.isOutgoing
        )
    }
}