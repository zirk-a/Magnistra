// Overview: Comment cell.
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



final class MagnistraCommentCell:
    UITableViewCell
{
    static let mediaQueue:
        OperationQueue = {
            let queue =
                OperationQueue()
            queue.maxConcurrentOperationCount =
                3
            return queue
        }()

    private static let avatarImageCache =
        NSCache<NSString, UIImage>()

    static func clearAvatarMemoryCache() {
        avatarImageCache.removeAllObjects()
    }

    private let avatarView = UIImageView()
    private let usernameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyLabel = UILabel()
    private let replyButton = UIButton(type: .custom)
    private let repliesButton = UIButton(type: .custom)
    private let likeButton = UIButton(type: .custom)
    private let likeCountLabel = UILabel()
    private let richMediaView = UIImageView()
    private let richMediaSpinner = UIActivityIndicatorView(style: .gray)

    private var representedCommentID = ""
    private var layoutComment: MagnistraComment?
    private var threadReplyLayout = false

    var onReply: (() -> Void)?
    var onReplies: (() -> Void)?
    var onLike: (() -> Void)?
    var onProfileTap: ((String) -> Void)?

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(
            style: style,
            reuseIdentifier:
                reuseIdentifier
        )

        selectionStyle = .none
        backgroundColor = UIColor.white
        contentView.backgroundColor = UIColor.white

        avatarView.backgroundColor =
            UIColor(
                white: 0.92,
                alpha: 1.0
            )
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        contentView.addSubview(avatarView)

        avatarView.isUserInteractionEnabled =
            true
        avatarView.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action:
                    #selector(commentProfileTapped)
            )
        )

        usernameLabel.font =
            UIFont.boldSystemFont(
                ofSize: 12.5
            )
        usernameLabel.textColor =
            UIColor(
                white: 0.10,
                alpha: 1.0
            )
        contentView.addSubview(usernameLabel)

        usernameLabel.isUserInteractionEnabled =
            true
        usernameLabel.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action:
                    #selector(commentProfileTapped)
            )
        )

        timeLabel.font =
            UIFont.systemFont(
                ofSize: 10.5
            )
        timeLabel.textColor =
            UIColor(
                white: 0.52,
                alpha: 1.0
            )
        contentView.addSubview(timeLabel)

        bodyLabel.font =
            UIFont.systemFont(
                ofSize: 13.0
            )
        bodyLabel.textColor =
            UIColor(
                white: 0.10,
                alpha: 1.0
            )
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.isUserInteractionEnabled =
            true
        bodyLabel.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action:
                    #selector(commentBodyTapped(_:))
            )
        )
        contentView.addSubview(bodyLabel)

        replyButton.setTitle(
            "Reply",
            for: .normal
        )
        replyButton.setTitleColor(
            UIColor(
                white: 0.46,
                alpha: 1.0
            ),
            for: .normal
        )
        replyButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize: 10.5
            )
        replyButton.contentHorizontalAlignment =
            .left
        replyButton.addTarget(
            self,
            action: #selector(replyTapped),
            for: .touchUpInside
        )
        contentView.addSubview(replyButton)

        repliesButton.setTitleColor(
            UIColor(
                white: 0.46,
                alpha: 1.0
            ),
            for: .normal
        )
        repliesButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize: 10.5
            )
        repliesButton.contentHorizontalAlignment =
            .left
        repliesButton.addTarget(
            self,
            action: #selector(repliesTapped),
            for: .touchUpInside
        )
        contentView.addSubview(repliesButton)

        likeButton.imageView?.contentMode =
            .scaleAspectFit
        likeButton.addTarget(
            self,
            action: #selector(likeTapped),
            for: .touchUpInside
        )
        contentView.addSubview(likeButton)

        likeCountLabel.font =
            UIFont.systemFont(
                ofSize: 9.5
            )
        likeCountLabel.textAlignment = .center
        likeCountLabel.textColor =
            UIColor(
                white: 0.45,
                alpha: 1.0
            )
        contentView.addSubview(likeCountLabel)

        richMediaView.contentMode = .scaleAspectFill
        richMediaView.clipsToBounds = true
        richMediaView.layer.cornerRadius = 6.0
        richMediaView.backgroundColor =
            UIColor(
                white: 0.94,
                alpha: 1.0
            )
        contentView.addSubview(richMediaView)

        richMediaSpinner.hidesWhenStopped =
            true
        contentView.addSubview(
            richMediaSpinner
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        representedCommentID = ""
        layoutComment = nil
        threadReplyLayout = false
        avatarView.image = nil
        usernameLabel.text = nil
        timeLabel.text = nil
        bodyLabel.text = nil
        if #available(iOS 6.0, *) {
            bodyLabel.attributedText =
                nil
        }
        repliesButton.setTitle(
            nil,
            for: .normal
        )
        likeCountLabel.text = nil
        onReply = nil
        onReplies = nil
        onLike = nil
        onProfileTap = nil
        richMediaView.image = nil
        richMediaSpinner.stopAnimating()
        richMediaView.isHidden = true
    }

    static func rowHeight(
        comment: MagnistraComment,
        width: CGFloat,
        isThreadReply: Bool,
        showRepliesControl: Bool
    ) -> CGFloat {
        let leftInset: CGFloat =
            isThreadReply
                ? 92.0
                : 58.0

        let textWidth =
            max(
                80.0,
                width -
                leftInset -
                48.0 -
                8.0
            )

        var y: CGFloat =
            isThreadReply
                ? 29.0
                : 31.0

        if !comment.text.isEmpty {
            let measure =
                UILabel(
                    frame: CGRect.zero
                )
            measure.font =
                UIFont.systemFont(
                    ofSize: 13.0
                )
            measure.numberOfLines = 0
            measure.lineBreakMode = .byWordWrapping
            measure.text = comment.text

            y +=
                ceil(
                    measure.sizeThatFits(
                        CGSize(
                            width: textWidth,
                            height: 10000.0
                        )
                    ).height
                ) +
                6.0
        }

        if comment.giphyURL != nil {
            y +=
                mediaHeight(
                    comment: comment,
                    width: width,
                    isThreadReply:
                        isThreadReply
                ) +
                7.0
        }

        y += 16.0

        if showRepliesControl {
            y += 17.0
        }

        return max(
            isThreadReply
                ? 56.0
                : 62.0,
            y + 9.0
        )
    }

    private static func mediaHeight(
        comment: MagnistraComment,
        width: CGFloat,
        isThreadReply: Bool
    ) -> CGFloat {
        let leftInset: CGFloat =
            isThreadReply
                ? 92.0
                : 58.0

        let available =
            min(
                220.0,
                max(
                    110.0,
                    width -
                    leftInset -
                    54.0
                )
            )

        if
            comment.giphyWidth > 0,
            comment.giphyHeight > 0
        {
            let ratio =
                CGFloat(
                    comment.giphyHeight
                ) /
                CGFloat(
                    comment.giphyWidth
                )

            return min(
                230.0,
                max(
                    100.0,
                    available * ratio
                )
            )
        }

        return min(
            190.0,
            available
        )
    }

    func configure(
        _ comment: MagnistraComment,
        repliesExpanded: Bool,
        repliesLoading: Bool,
        isThreadReply: Bool,
        showHideReplies: Bool
    ) {
        representedCommentID =
            comment.commentID
        layoutComment =
            comment
        threadReplyLayout =
            isThreadReply

        usernameLabel.text =
            comment.username

        timeLabel.text =
            MagnistraCommentCell
                .relativeTime(
                    comment.createdAt
                )

        bodyLabel.text =
            comment.text

        if #available(iOS 6.0, *) {
            let attributed =
                NSMutableAttributedString(
                    string:
                        comment.text
                )

            let fullRange =
                NSRange(
                    location: 0,
                    length:
                        (comment.text as NSString)
                            .length
                )

            if fullRange.length > 0 {
                attributed.addAttribute(
                    NSAttributedString.Key(
                        rawValue: "NSFont"
                    ),
                    value:
                        bodyLabel.font ??
                        UIFont.systemFont(
                            ofSize: 13.0
                        ),
                    range:
                        fullRange
                )

                attributed.addAttribute(
                    NSAttributedString.Key(rawValue: "NSColor"),
                    value:
                        UIColor(
                            white: 0.10,
                            alpha: 1.0
                        ),
                    range:
                        fullRange
                )

                if
                    let expression =
                        try? NSRegularExpression(
                            pattern:
                                "@[A-Za-z0-9._]+",
                            options:
                                []
                        )
                {
                    let source =
                        comment.text as NSString

                    for match in
                        expression.matches(
                            in:
                                comment.text,
                            options:
                                [],
                            range:
                                NSRange(
                                    location: 0,
                                    length:
                                        source.length
                                )
                        )
                    {
                        attributed.addAttribute(
                            NSAttributedString.Key(rawValue: "NSColor"),
                            value:
                                MagnistraPostCell
                                    .magnistraBlue,
                            range:
                                match.range
                        )
                    }
                }
            }

            bodyLabel.attributedText =
                attributed
        }

        bodyLabel.isHidden =
            comment.text.isEmpty

        repliesButton.isEnabled =
            !repliesLoading

        if
            repliesLoading &&
            !isThreadReply
        {
            repliesButton.setTitle(
                "Loading...",
                for: .normal
            )
            repliesButton.isHidden =
                false
        } else if isThreadReply {
            if showHideReplies {
                repliesButton.setTitle(
                    "Hide replies",
                    for: .normal
                )
                repliesButton.isHidden =
                    false
            } else {
                repliesButton.setTitle(
                    nil,
                    for: .normal
                )
                repliesButton.isHidden =
                    true
            }
        } else if
            comment.childCommentCount > 0 &&
            !repliesExpanded
        {
            repliesButton.setTitle(
                comment.childCommentCount == 1
                    ? "View 1 reply"
                    : "View \(comment.childCommentCount) replies",
                for: .normal
            )
            repliesButton.isHidden =
                false
        } else {
            repliesButton.setTitle(
                nil,
                for: .normal
            )
            repliesButton.isHidden =
                true
        }

        likeButton.setImage(
            UIImage(
                named:
                    comment.hasLiked
                        ? "MagnistraPostLikeActive"
                        : "MagnistraPostLike"
            ),
            for: .normal
        )

        likeCountLabel.text =
            comment.likeCount > 0
                ? "\(comment.likeCount)"
                : nil

        richMediaView.image = nil

        let hasRichMedia =
            !(
                comment.giphyURL ?? ""
            ).isEmpty

        richMediaView.isHidden =
            !hasRichMedia

        if hasRichMedia {
            richMediaSpinner.startAnimating()
        } else {
            richMediaSpinner.stopAnimating()
        }

        setNeedsLayout()

        loadAvatar(comment)
        loadRichMedia(comment)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width =
            max(
                1.0,
                contentView.bounds
                    .size.width
            )

        let avatarSide: CGFloat =
            threadReplyLayout
                ? 30.0
                : 36.0

        let avatarX: CGFloat =
            threadReplyLayout
                ? 52.0
                : 12.0

        let contentX: CGFloat =
            threadReplyLayout
                ? 92.0
                : 58.0

        let topY: CGFloat =
            threadReplyLayout
                ? 10.0
                : 12.0

        avatarView.frame =
            CGRect(
                x: avatarX,
                y: topY,
                width: avatarSide,
                height: avatarSide
            )
        avatarView.layer.cornerRadius =
            avatarSide * 0.5

        let rightX =
            width -
            38.0

        let textWidth =
            max(
                80.0,
                rightX -
                contentX -
                8.0
            )

        usernameLabel.frame =
            CGRect(
                x: contentX,
                y:
                    threadReplyLayout
                        ? 9.0
                        : 11.0,
                width: min(
                    textWidth * 0.72,
                    180.0
                ),
                height: 17.0
            )

        let usernameWidth =
            min(
                usernameLabel
                    .sizeThatFits(
                        CGSize(
                            width: textWidth,
                            height: 20.0
                        )
                    ).width +
                4.0,
                textWidth * 0.72
            )

        timeLabel.frame =
            CGRect(
                x:
                    contentX +
                    usernameWidth,
                y:
                    threadReplyLayout
                        ? 10.0
                        : 12.0,
                width:
                    max(
                        34.0,
                        textWidth -
                        usernameWidth
                    ),
                height: 15.0
            )

        var y: CGFloat =
            threadReplyLayout
                ? 29.0
                : 31.0

        if !bodyLabel.isHidden {
            let bodyHeight =
                ceil(
                    bodyLabel
                        .sizeThatFits(
                            CGSize(
                                width: textWidth,
                                height: 10000.0
                            )
                        ).height
                )

            bodyLabel.frame =
                CGRect(
                    x: contentX,
                    y: y,
                    width: textWidth,
                    height: bodyHeight
                )

            y +=
                bodyHeight +
                6.0
        } else {
            bodyLabel.frame =
                CGRect.zero
        }

        if
            !richMediaView.isHidden,
            let comment =
                layoutComment
        {
            let mediaHeight =
                MagnistraCommentCell
                    .mediaHeight(
                        comment: comment,
                        width: width,
                        isThreadReply:
                            threadReplyLayout
                    )

            richMediaView.frame =
                CGRect(
                    x: contentX,
                    y: y,
                    width:
                        min(
                            220.0,
                            textWidth
                        ),
                    height:
                        mediaHeight
                )

            y +=
                mediaHeight +
                7.0
        } else {
            richMediaView.frame =
                CGRect.zero
        }

        if
            richMediaView.frame.width > 0.0 &&
            richMediaView.frame.height > 0.0
        {
            richMediaSpinner.frame =
                CGRect(
                    x:
                        richMediaView.frame.midX -
                        10.0,
                    y:
                        richMediaView.frame.midY -
                        10.0,
                    width: 20.0,
                    height: 20.0
                )
        } else {
            richMediaSpinner.frame =
                CGRect.zero
        }

        replyButton.frame =
            CGRect(
                x: contentX,
                y: y,
                width: 52.0,
                height: 16.0
            )

        if !repliesButton.isHidden {
            repliesButton.frame =
                CGRect(
                    x:
                        contentX +
                        60.0,
                    y: y,
                    width:
                        max(
                            80.0,
                            textWidth -
                            60.0
                        ),
                    height: 16.0
                )
        } else {
            repliesButton.frame =
                CGRect.zero
        }

        likeButton.frame =
            CGRect(
                x: rightX,
                y:
                    threadReplyLayout
                        ? 21.0
                        : 25.0,
                width: 17.0,
                height: 17.0
            )

        likeCountLabel.frame =
            CGRect(
                x:
                    rightX -
                    4.0,
                y:
                    threadReplyLayout
                        ? 40.0
                        : 44.0,
                width: 25.0,
                height: 13.0
            )
    }

    @objc private func commentProfileTapped() {
        guard
            let username =
                layoutComment?
                    .username,
            !username.isEmpty
        else {
            return
        }

        onProfileTap?(
            username
        )
    }

    @objc private func commentBodyTapped(
        _ recognizer:
            UITapGestureRecognizer
    ) {
        guard
            let comment = layoutComment,
            !comment.text.isEmpty,
            bodyLabel.bounds.size.width > 0.0,
            bodyLabel.bounds.size.height > 0.0
        else {
            return
        }

        let source = comment.text as NSString
        guard
            let expression =
                try? NSRegularExpression(
                    pattern: "@[A-Za-z0-9._]+",
                    options: []
                )
        else {
            return
        }
        let mentions = expression.matches(
            in: comment.text,
            options: [],
            range: NSRange(location: 0, length: source.length)
        )
        guard !mentions.isEmpty else {
            return
        }

        let font = bodyLabel.font ??
            UIFont.systemFont(ofSize: 13.0)
        let ctFont = CTFontCreateWithName(
            font.fontName as CFString,
            font.pointSize,
            nil
        )
        let attributed = NSMutableAttributedString(
            string: comment.text
        )
        attributed.addAttribute(
            NSAttributedString.Key(rawValue: "NSFont"),
            value: ctFont,
            range: NSRange(location: 0, length: source.length)
        )
        let framesetter =
            CTFramesetterCreateWithAttributedString(
                attributed as CFAttributedString
            )
        let path = CGMutablePath()
        path.addRect(
            CGRect(
                origin: .zero,
                size: bodyLabel.bounds.size
            )
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        let lines = CTFrameGetLines(frame)
        let count = CFArrayGetCount(lines)
        guard count > 0 else {
            return
        }
        var origins = [CGPoint](
            repeating: CGPoint.zero,
            count: count
        )
        CTFrameGetLineOrigins(
            frame,
            CFRange(location: 0, length: 0),
            &origins
        )
        let touch = recognizer.location(in: bodyLabel)

        let pointY = bodyLabel.bounds.size.height - touch.y
        for i in 0..<count {
            let line: CTLine = unsafeBitCast(
                CFArrayGetValueAtIndex(lines, i),
                to: CTLine.self
            )
            var ascent: CGFloat = 0.0
            var descent: CGFloat = 0.0
            var leading: CGFloat = 0.0
            let width = CGFloat(
                CTLineGetTypographicBounds(
                    line, &ascent, &descent, &leading
                )
            )
            let baseline = origins[i]
            let horizontal = touch.x - baseline.x
            guard
                horizontal >= 0.0,
                horizontal <= width,
                pointY >= baseline.y - descent - 3.0,
                pointY <= baseline.y + ascent + 3.0
            else {
                continue
            }
            let charIndex = CTLineGetStringIndexForPosition(
                line,
                CGPoint(x: horizontal, y: 0.0)
            )
            guard charIndex != kCFNotFound else {
                return
            }
            let index = Int(charIndex)
            for match in mentions {
                guard
                    index >= match.range.location,
                    index < NSMaxRange(match.range)
                else {
                    continue
                }
                let raw = source.substring(with: match.range)
                let username = String(raw.dropFirst())
                if !username.isEmpty {
                    onProfileTap?(username)
                }
                return
            }
            return
        }
    }

    @objc private func replyTapped() {
        onReply?()
    }

    @objc private func repliesTapped() {
        onReplies?()
    }

    @objc private func likeTapped() {
        onLike?()
    }

    private func loadAvatar(
        _ comment: MagnistraComment
    ) {
        guard
            let url = comment.avatarURL,
            !url.isEmpty
        else {
            avatarView.image =
                nil
            return
        }

        let cacheKey =
            url as NSString

        if
            let cached =
                MagnistraCommentCell
                    .avatarImageCache
                    .object(
                        forKey:
                            cacheKey
                    )
        {
            avatarView.image =
                cached
            return
        }

        let commentID =
            comment.commentID

        MagnistraCommentCell
            .mediaQueue
            .addOperation {
                [weak self] in

                let path =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url: url,
                            stableKey:
                                "comment-avatar-" +
                                commentID,
                            isAvatar: true
                        )

                let image =
                    path.flatMap {
                        UIImage(
                            contentsOfFile: $0
                        )
                    }

                if let image = image {
                    MagnistraCommentCell
                        .avatarImageCache
                        .setObject(
                            image,
                            forKey:
                                cacheKey
                        )
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self = self,
                            self.representedCommentID ==
                                commentID
                        else {
                            return
                        }

                        self.avatarView.image =
                            image
                    }
            }
    }

    private func loadRichMedia(
        _ comment: MagnistraComment
    ) {
        guard
            let url = comment.giphyURL,
            !url.isEmpty
        else {
            richMediaSpinner.stopAnimating()
            return
        }

        let commentID =
            comment.commentID

        MagnistraCommentCell
            .mediaQueue
            .addOperation {
                [weak self] in

                let image: UIImage?

                if
                    let path =
                        MagnistraHomeService
                            .materializeFeedImage(
                                url: url,
                                stableKey:
                                    "comment-giphy-" +
                                    commentID,
                                isAvatar: false
                            ),
                    let data =
                        FileManager.default
                            .contents(
                                atPath: path
                            )
                {
                    image =
                        MagnistraCommentCell
                            .animatedGIF(data) ??
                        UIImage(data: data)
                } else {
                    image = nil
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self = self,
                            self.representedCommentID ==
                                commentID
                        else {
                            return
                        }

                        self.richMediaSpinner
                            .stopAnimating()

                        self.richMediaView.image =
                            image

                        self.richMediaView.isHidden =
                            image == nil
                    }
            }
    }

    private static func relativeTime(
        _ timestamp: Double
    ) -> String {
        guard timestamp > 0.0 else {
            return ""
        }

        let delta =
            max(
                0.0,
                Date()
                    .timeIntervalSince1970 -
                timestamp
            )

        if delta < 60.0 {
            return "\(Int(delta))s"
        }

        if delta < 3600.0 {
            return "\(Int(delta / 60.0))m"
        }

        if delta < 86400.0 {
            return "\(Int(delta / 3600.0))h"
        }

        if delta < 604800.0 {
            return "\(Int(delta / 86400.0))d"
        }

        return "\(Int(delta / 604800.0))w"
    }

    private static func animatedGIF(
        _ data: Data
    ) -> UIImage? {
        guard
            data.count >= 6,
            let source =
                CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                )
        else {
            return nil
        }

        let count =
            CGImageSourceGetCount(source)

        guard count > 1 else {
            return nil
        }

        let maxFrames =
            min(
                count,
                60
            )

        var frames: [UIImage] = []
        var duration: Double = 0.0

        for index in 0..<maxFrames {
            guard
                let cg =
                    CGImageSourceCreateImageAtIndex(
                        source,
                        index,
                        nil
                    )
            else {
                continue
            }

            frames.append(
                UIImage(
                    cgImage: cg
                )
            )

            duration +=
                frameDelay(
                    source: source,
                    index: index
                )
        }

        guard frames.count > 1 else {
            return nil
        }

        if duration <= 0.0 {
            duration =
                Double(
                    frames.count
                ) *
                0.1
        }

        return UIImage.animatedImage(
            with: frames,
            duration: duration
        )
    }

    private static func frameDelay(
        source: CGImageSource,
        index: Int
    ) -> Double {
        guard
            let props =
                CGImageSourceCopyPropertiesAtIndex(
                    source,
                    index,
                    nil
                ) as? [String: Any],
            let gif =
                props[
                    kCGImagePropertyGIFDictionary
                        as String
                ] as? [String: Any]
        else {
            return 0.1
        }

        var delay =
            (
                gif[
                    kCGImagePropertyGIFUnclampedDelayTime
                        as String
                ] as? NSNumber
            )?.doubleValue ??
            0.0

        if delay <= 0.0 {
            delay =
                (
                    gif[
                        kCGImagePropertyGIFDelayTime
                            as String
                    ] as? NSNumber
                )?.doubleValue ??
                0.0
        }

        if delay < 0.02 {
            delay = 0.1
        }

        return delay
    }
}