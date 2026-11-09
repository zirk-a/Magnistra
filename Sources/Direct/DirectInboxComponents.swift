// Overview: Direct inbox UI pieces: inbox cell, waveform view, play glyph and message render kinds.
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

final class MagnistraDirectInboxCell:
    UITableViewCell
{
    private static let avatarQueue:
        OperationQueue =
            {
                let queue =
                    OperationQueue()

                queue.maxConcurrentOperationCount =
                    2

                return queue
            }()

    private let avatarView =
        UIImageView()

    let titleLabel =
        UILabel()

    let subtitleLabel =
        UILabel()

    private let unreadDot =
        UIView()

    var representedThreadFBID =
        ""

    override init(
        style:
            UITableViewCell.CellStyle,
        reuseIdentifier:
            String?
    ) {
        super.init(
            style:
                style,
            reuseIdentifier:
                reuseIdentifier
        )

        backgroundColor =
            UIColor.white

        accessoryType =
            .disclosureIndicator

        avatarView.backgroundColor =
            UIColor(
                white:
                    0.88,
                alpha:
                    1.0
            )

        avatarView.contentMode =
            .scaleAspectFill

        avatarView.clipsToBounds =
            true

        avatarView.layer.cornerRadius =
            22.0

        avatarView.layer.borderWidth =
            0.5

        avatarView.layer.borderColor =
            UIColor(
                white:
                    0.78,
                alpha:
                    1.0
            )
            .cgColor

        contentView.addSubview(
            avatarView
        )

        titleLabel.backgroundColor =
            UIColor.clear

        titleLabel.font =
            UIFont.boldSystemFont(
                ofSize:
                    14.0
            )

        titleLabel.textColor =
            UIColor(
                white:
                    0.18,
                alpha:
                    1.0
            )

        contentView.addSubview(
            titleLabel
        )

        subtitleLabel.backgroundColor =
            UIColor.clear

        subtitleLabel.font =
            UIFont.systemFont(
                ofSize:
                    11.5
            )

        subtitleLabel.textColor =
            UIColor(
                white:
                    0.47,
                alpha:
                    1.0
            )

        subtitleLabel.numberOfLines =
            2

        contentView.addSubview(
            subtitleLabel
        )

        unreadDot.backgroundColor =
            MagnistraPostCell
                .magnistraBlue

        unreadDot.layer.cornerRadius =
            4.0

        unreadDot.isHidden =
            true

        contentView.addSubview(
            unreadDot
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        representedThreadFBID =
            ""

        avatarView.image =
            nil

        titleLabel.text =
            nil

        subtitleLabel.text =
            nil

        unreadDot.isHidden =
            true
    }

    func configure(
        _ thread:
            MagnistraDirectThreadSummary
    ) {
        representedThreadFBID =
            thread.threadFBID

        titleLabel.text =
            thread.title

        subtitleLabel.text =
            thread.snippet

        unreadDot.isHidden =
            !thread.isUnread

        avatarView.image =
            nil

        guard
            let remoteURL =
                thread.avatarURL,
            !remoteURL.isEmpty
        else {
            return
        }

        let threadID =
            thread.threadFBID

        let stableKey =
            "direct-avatar:" +
            threadID

        MagnistraDirectInboxCell
            .avatarQueue
            .addOperation {
                [weak self] in

                autoreleasepool {
                    guard
                        let path =
                            MagnistraHomeService
                                .materializeFeedImage(
                                    url:
                                        remoteURL,
                                    stableKey:
                                        stableKey,
                                    isAvatar:
                                        true
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
                            [weak self] in

                            guard
                                let self =
                                    self,
                                self.representedThreadFBID ==
                                    threadID
                            else {
                                return
                            }

                            self.avatarView.image =
                                image
                        }
                }
            }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width =
            max(
                1.0,
                bounds.size.width
            )

        avatarView.frame =
            CGRect(
                x:
                    10.0,
                y:
                    11.0,
                width:
                    44.0,
                height:
                    44.0
            )

        unreadDot.frame =
            CGRect(
                x:
                    max(
                        60.0,
                        width -
                        34.0
                    ),
                y:
                    29.0,
                width:
                    8.0,
                height:
                    8.0
            )

        titleLabel.frame =
            CGRect(
                x:
                    64.0,
                y:
                    7.0,
                width:
                    max(
                        1.0,
                        width -
                        104.0
                    ),
                height:
                    21.0
            )

        subtitleLabel.frame =
            CGRect(
                x:
                    64.0,
                y:
                    29.0,
                width:
                    max(
                        1.0,
                        width -
                        104.0
                    ),
                height:
                    31.0
            )
    }
}

final class MagnistraDirectWaveformView:
    UIView
{
    var samples:
        [Double] =
            []
    {
        didSet {
            setNeedsDisplay()
        }
    }

    var barColor:
        UIColor =
            UIColor.white
    {
        didSet {
            setNeedsDisplay()
        }
    }

    var playbackProgress:
        CGFloat =
            0.0
    {
        didSet {
            playbackProgress =
                max(
                    0.0,
                    min(
                        1.0,
                        playbackProgress
                    )
                )

            setNeedsDisplay()
        }
    }

    var playbackActive =
        false
    {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(
        frame:
            CGRect
    ) {
        super.init(
            frame:
                frame
        )

        backgroundColor =
            UIColor.clear

        isOpaque =
            false
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    override func draw(
        _ rect:
            CGRect
    ) {
        super.draw(
            rect
        )

        let count =
            24

        guard
            rect.width > 1.0,
            rect.height > 1.0
        else {
            return
        }

        let barWidth:
            CGFloat =
                2.0

        let gap =
            max(
                1.0,
                (
                    rect.width -
                    CGFloat(count) *
                    barWidth
                ) /
                CGFloat(
                    max(
                        1,
                        count - 1
                    )
                )
            )

        var peak =
            1.0

        for value in samples {
            if value > peak {
                peak =
                    value
            }
        }

        for index in 0..<count {
            let value:
                Double

            if samples.isEmpty {
                let pattern = [
                    0.28,
                    0.46,
                    0.72,
                    0.42,
                    0.88,
                    0.58,
                    0.34,
                    0.76
                ]

                value =
                    pattern[
                        index %
                        pattern.count
                    ]
            } else {
                let sourceIndex =
                    min(
                        samples.count -
                        1,
                        Int(
                            Double(index) /
                            Double(
                                max(
                                    1,
                                    count - 1
                                )
                            ) *
                            Double(
                                samples.count -
                                1
                            )
                        )
                    )

                value =
                    max(
                        0.12,
                        min(
                            1.0,
                            samples[
                                sourceIndex
                            ] /
                            peak
                        )
                    )
            }

            let height =
                max(
                    3.0,
                    rect.height *
                    CGFloat(
                        value
                    )
                )

            let x =
                CGFloat(index) *
                (
                    barWidth +
                    gap
                )

            let y =
                floor(
                    (
                        rect.height -
                        height
                    ) /
                    2.0
                )

            if playbackActive {
                let position =
                    CGFloat(
                        index + 1
                    ) /
                    CGFloat(count)

                let alpha:
                    CGFloat =
                        position <=
                            playbackProgress
                            ? 1.0
                            : 0.28

                barColor
                    .withAlphaComponent(
                        alpha
                    )
                    .setFill()
            } else {
                barColor.setFill()
            }

            UIRectFill(
                CGRect(
                    x:
                        x,
                    y:
                        y,
                    width:
                        barWidth,
                    height:
                        height
                )
            )
        }
    }
}

enum MagnistraDirectRenderKind {
    case text
    case photo
    case video
    case voice
    case sharedPost
    case sharedReel
    case unsupported
}

func magnistraDirectRenderKind(
    _ message:
        MagnistraDirectMessage
) -> MagnistraDirectRenderKind {
    let upperType =
        message
            .contentType
            .uppercased()

    if
        upperType.contains(
            "RAVEN"
        ) ||
        message.text ==
            "Unsupported message"
    {
        return .unsupported
    }

    if
        message.audioURL != nil ||
        message.mediaKind ==
            "voice"
    {
        return .voice
    }

    if
        message.targetURL != nil ||
        message.mediaKind ==
            "shared"
    {
        let route =
            message.targetURL?
                .lowercased() ??
            ""

        if
            route.contains(
                "/reel/"
            ) ||
            route.contains(
                "/tv/"
            )
        {
            return .sharedReel
        }

        return .sharedPost
    }

    if message.mediaKind == "video" {
        return .video
    }

    if message.mediaKind == "photo" {
        return .photo
    }

    return .text
}

final class MagnistraDirectPlayGlyphView:
    UIView
{
    var glyphColor =
        UIColor.white
    {
        didSet {
            setNeedsDisplay()
        }
    }

    var showsPause =
        false
    {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(
        frame:
            CGRect
    ) {
        super.init(
            frame:
                frame
        )

        backgroundColor =
            UIColor.clear

        isOpaque =
            false
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    override func draw(
        _ rect:
            CGRect
    ) {
        super.draw(
            rect
        )

        glyphColor.setFill()

        if showsPause {
            let barWidth =
                max(
                    2.0,
                    floor(
                        rect.width *
                        0.18
                    )
                )

            let gap =
                max(
                    3.0,
                    floor(
                        rect.width *
                        0.14
                    )
                )

            let total =
                barWidth *
                2.0 +
                gap

            let x =
                floor(
                    (
                        rect.width -
                        total
                    ) /
                    2.0
                )

            let top =
                floor(
                    rect.height *
                    0.22
                )

            let height =
                max(
                    4.0,
                    floor(
                        rect.height *
                        0.56
                    )
                )

            UIRectFill(
                CGRect(
                    x:
                        x,
                    y:
                        top,
                    width:
                        barWidth,
                    height:
                        height
                )
            )

            UIRectFill(
                CGRect(
                    x:
                        x +
                        barWidth +
                        gap,
                    y:
                        top,
                    width:
                        barWidth,
                    height:
                        height
                )
            )

            return
        }

        let inset:
            CGFloat =
                max(
                    2.0,
                    rect.width *
                    0.22
                )

        let path =
            UIBezierPath()

        path.move(
            to:
                CGPoint(
                    x:
                        inset,
                    y:
                        inset
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x:
                        rect.width -
                        inset,
                    y:
                        rect.height /
                        2.0
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x:
                        inset,
                    y:
                        rect.height -
                        inset
                )
        )

        path.close()

        path.fill()
    }
}

final class MagnistraDirectSharedKindGlyphView:
    UIView
{
    var isReel =
        false
    {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(
        frame:
            CGRect
    ) {
        super.init(frame: frame)

        backgroundColor =
            UIColor.clear

        isOpaque =
            false
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    override func draw(
        _ rect:
            CGRect
    ) {
        super.draw(rect)

        let stroke =
            UIColor(
                white:
                    0.36,
                alpha:
                    1.0
            )

        stroke.setStroke()

        let outer =
            UIBezierPath(
                roundedRect:
                    rect.insetBy(
                        dx:
                            1.5,
                        dy:
                            1.5
                    ),
                cornerRadius:
                    3.0
            )

        outer.lineWidth =
            1.0

        outer.stroke()

        if isReel {
            let divider =
                UIBezierPath()

            divider.move(
                to:
                    CGPoint(
                        x: 2.0,
                        y: 5.0
                    )
            )

            divider.addLine(
                to:
                    CGPoint(
                        x:
                            rect.width -
                            2.0,
                        y: 5.0
                    )
            )

            divider.lineWidth =
                1.0

            divider.stroke()

            let play =
                UIBezierPath()

            play.move(
                to:
                    CGPoint(
                        x:
                            rect.width *
                            0.42,
                        y:
                            rect.height *
                            0.38
                    )
            )

            play.addLine(
                to:
                    CGPoint(
                        x:
                            rect.width *
                            0.68,
                        y:
                            rect.height *
                            0.52
                    )
            )

            play.addLine(
                to:
                    CGPoint(
                        x:
                            rect.width *
                            0.42,
                        y:
                            rect.height *
                            0.66
                    )
            )

            play.close()

            stroke.setFill()
            play.fill()
        } else {
            let circle =
                UIBezierPath(
                    ovalIn:
                        CGRect(
                            x:
                                rect.width *
                                0.33,
                            y:
                                rect.height *
                                0.33,
                            width:
                                rect.width *
                                0.34,
                            height:
                                rect.height *
                                0.34
                        )
                )

            circle.lineWidth =
                1.0

            circle.stroke()
        }
    }
}

enum MagnistraDirectMediaDiskCache {
    private static let limitBytes: Int64 = 48 * 1024 * 1024
    private static let maxFiles = 160
    private static let queue = OperationQueue()
    private static func directory() -> String {
        let roots = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let base = roots.first ?? NSTemporaryDirectory()
        let path = (base as NSString).appendingPathComponent("MagnistraDirectMedia")
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: path,
                withIntermediateDirectories: true, attributes: nil)
        }
        return path
    }

    private static func filename(_ key: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(format: "%016llx", hash) + ".bin"
    }
    private static func path(for key: String) -> String {
        return (directory() as NSString).appendingPathComponent(filename(key))
    }
    static func existingPath(_ key: String) -> String? {
        let file = path(for: key)
        guard let values = try? FileManager.default.attributesOfItem(atPath: file),
              let length = values[.size] as? NSNumber,
              length.int64Value > 0 else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file)
        return file
    }
    static func imagePath(remote: String, key: String) -> String? {
        let k = "image|" + key + "|" + remote
        MagnistraDirectMediaTrace.record("DISK_LOOKUP", id: key,
            info: "source=" + MagnistraDirectMediaTrace.urlTag(remote))
        if let hit = existingPath(k) {
            MagnistraDirectMediaTrace.record("DISK_HIT", id: key)
            return hit
        }
        if let parsed = URL(string: remote), let host = parsed.host?.lowercased() {
            let lowerPath = parsed.path.lowercased()
            let isAnimatedHost = host == "giphy.com" || host.hasSuffix(".giphy.com")
                || host == "tenor.com" || host.hasSuffix(".tenor.com")
                || host == "giphyusercontent.com" || host.hasSuffix(".giphyusercontent.com")
                || host == "tenor.co" || host.hasSuffix(".tenor.co")
            let probablyAnimated = isAnimatedHost || lowerPath.hasSuffix(".gif")
                || lowerPath.contains("/gif/") || lowerPath.hasSuffix(".webp")
            if probablyAnimated,
               let original = MagnistraHomeService.magnistraDirectGIFBytes(urlString: remote) {
                let destination = path(for: k)
                do {
                    try original.write(to: URL(fileURLWithPath: destination), options: .atomic)
                    MagnistraDirectMediaTrace.record("RAW_ANIMATED_BYTES_OK", id: key)
                    prune()
                    return destination
                } catch { }
            }
        }
        let resolved = MagnistraHomeService.materializeFeedImage(
            url: remote, stableKey: key, isAvatar: false)
        if resolved == nil {
            MagnistraDirectMediaTrace.record("MATERIALIZER_NIL", id: key)
            let destination = path(for: k)
            if let gif = MagnistraHomeService.magnistraDirectGIFBytes(urlString: remote) {
                MagnistraDirectMediaTrace.record("GIF_FALLBACK_BYTES", id: key,
                    info: "size=" + (gif.count > 0 ? "nonzero" : "zero"))
                do {
                    try gif.write(to: URL(fileURLWithPath: destination), options: .atomic)
                    prune()
                    return destination
                } catch { return nil }
            }
            return nil
        }
        guard let source = resolved else { return nil }
        MagnistraDirectMediaTrace.record("MATERIALIZER_OK", id: key)
        let destination = path(for: k)
        if source != destination {
            try? FileManager.default.copyItem(atPath: source, toPath: destination)
        }
        if FileManager.default.fileExists(atPath: destination) {
            prune()
            return destination
        }
        return source
    }
    static func cachedVoice(_ url: URL, key: String) -> Data? {
        let cacheKey = "voice|" + key + "|" + url.absoluteString
        if let hit = existingPath(cacheKey),
           let bytes = NSData(contentsOfFile: hit) as Data? { return bytes }
        guard let bytes = NSData(contentsOf: url) as Data? else { return nil }
        if bytes.count <= Int(limitBytes / 4) {
            (bytes as NSData).write(toFile: path(for: cacheKey), atomically: true)
            prune()
        }
        return bytes
    }
    private static func prune() {
        let dir = directory()
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        var entries: [(String, Int64, Date)] = []
        var total: Int64 = 0
        for name in names where name.hasSuffix(".bin") {
            let full = (dir as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let length = attrs[.size] as? NSNumber else { continue }
            let size = length.int64Value
            total += size
            entries.append((full, size, attrs[.modificationDate] as? Date ?? Date.distantPast))
        }
        if entries.count <= maxFiles && total <= limitBytes { return }
        entries.sort { $0.2 < $1.2 }
        var count = entries.count
        for entry in entries {
            if count <= maxFiles && total <= limitBytes { break }
            do {
                try fm.removeItem(atPath: entry.0)
                total -= entry.1
                count -= 1
            } catch { }
        }
    }
}

@_silgen_name("MagnistraDirectWebPAnimOpen")
func MagnistraDirectWebPAnimOpen(
    _ bytes: UnsafePointer<UInt8>, _ length: Int,
    _ width: UnsafeMutablePointer<Int32>, _ height: UnsafeMutablePointer<Int32>,
    _ count: UnsafeMutablePointer<Int32>) -> UnsafeMutableRawPointer?
@_silgen_name("MagnistraDirectWebPAnimNext")
func MagnistraDirectWebPAnimNext(
    _ decoder: UnsafeMutableRawPointer,
    _ pixels: UnsafeMutablePointer<UnsafePointer<UInt8>?>,
    _ time: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("MagnistraDirectWebPAnimClose")
func MagnistraDirectWebPAnimClose(_ decoder: UnsafeMutableRawPointer)

