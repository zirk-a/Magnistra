// Overview: Matrix Direct: message presentation models and the web-style bubble cell.
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

struct MagnistraMatrixMessagePresentation {
    let text: String
    let detail: String?

    private static func clean(
        _ value: Any?
    ) -> String? {
        guard
            let raw =
                value as? String
        else {
            return nil
        }

        let trimmed =
            raw.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        return
            trimmed.isEmpty
                ? nil
                : trimmed
    }

    private static func readableHTML(
        _ raw: String
    ) -> String {
        var value =
            raw

        let lineBreakTags = [
            "<br>",
            "<br/>",
            "<br />",
            "</p>",
            "</div>",
            "</li>"
        ]

        for tag in lineBreakTags {
            value =
                value.replacingOccurrences(
                    of:
                        tag,
                    with:
                        "\n",
                    options:
                        .caseInsensitive,
                    range:
                        nil
                )
        }

        value =
            value.replacingOccurrences(
                of:
                    "<li>",
                with:
                    "• ",
                options:
                    .caseInsensitive,
                range:
                    nil
            )

        var result = ""
        var insideTag = false

        for scalar in value.unicodeScalars {
            if scalar.value == 60 {
                insideTag = true
                continue
            }

            if scalar.value == 62 {
                insideTag = false
                continue
            }

            if !insideTag {
                result.unicodeScalars.append(
                    scalar
                )
            }
        }

        let entities:
            [(String, String)] = [
                ("&amp;", "&"),
                ("&lt;", "<"),
                ("&gt;", ">"),
                ("&quot;", "\""),
                ("&#39;", "'"),
                ("&apos;", "'"),
                ("&nbsp;", " ")
            ]

        for pair in entities {
            result =
                result.replacingOccurrences(
                    of:
                        pair.0,
                    with:
                        pair.1
                )
        }

        while result.contains("\n\n\n") {
            result =
                result.replacingOccurrences(
                    of:
                        "\n\n\n",
                    with:
                        "\n\n"
                )
        }

        return
            result.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }

    private static func messageBody(
        _ content: [String: Any]
    ) -> String? {
        if
            content["format"] as? String ==
                "org.matrix.custom.html",
            let formatted =
                clean(
                    content[
                        "formatted_body"
                    ]
                )
        {
            let readable =
                readableHTML(
                    formatted
                )

            if !readable.isEmpty {
                return readable
            }
        }

        return
            clean(
                content["body"]
            )
    }

    static func make(
        eventType: String,
        content: [String: Any]
    ) -> MagnistraMatrixMessagePresentation {
        if eventType == "m.sticker" {
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        messageBody(content) ??
                        "Sticker",
                    detail:
                        "Sticker"
                )
        }

        if eventType == "m.reaction" {
            let relation =
                content["m.relates_to"]
                    as? [String: Any]

            let key =
                clean(
                    relation?["key"]
                )

            return
                MagnistraMatrixMessagePresentation(
                    text:
                        key.map {
                            "Reaction: " + $0
                        } ??
                        "Reaction",
                    detail:
                        "Reaction"
                )
        }

        guard
            eventType ==
                "m.room.message"
        else {
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        messageBody(content) ??
                        "Message",
                    detail:
                        nil
                )
        }

        let msgtype =
            (
                clean(
                    content["msgtype"]
                ) ??
                "m.text"
            )
            .lowercased()

        let body =
            messageBody(
                content
            )

        switch msgtype {
        case "m.text":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "Message",
                    detail:
                        nil
                )

        case "m.notice":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "Notice",
                    detail:
                        "Notice"
                )

        case "m.emote":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body.map {
                            "• " + $0
                        } ??
                        "•",
                    detail:
                        "Emote"
                )

        case "m.image":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "Photo",
                    detail:
                        "Photo"
                )

        case "m.video":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "Video",
                    detail:
                        "Video"
                )

        case "m.audio":
            let isVoice =
                content[
                    "org.matrix.msc3245.voice"
                ] != nil

            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        (
                            isVoice
                                ? "Voice message"
                                : "Audio"
                        ),
                    detail:
                        isVoice
                            ? "Voice message"
                            : "Audio"
                )

        case "m.file":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "File",
                    detail:
                        "File"
                )

        case "m.location":
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "Location",
                    detail:
                        "Location"
                )

        default:
            return
                MagnistraMatrixMessagePresentation(
                    text:
                        body ??
                        "Message",
                    detail:
                        nil
                )
        }
    }
}

struct MagnistraMatrixTimelineMessage {
    let eventId: String
    let text: String
    let timestampMilliseconds: Double
    let isOutgoing: Bool
    let isEncrypted: Bool
    let detailText: String?
    let eventType: String
    let content: [String: Any]
    var senderUserId: String = ""
}

final class MagnistraMatrixWebStyleBubbleCell:
    UITableViewCell
{
    private let bubbleView =
        UIView()

    private let messageLabel =
        UILabel()

    private let detailLabel =
        UILabel()

    private var outgoing =
        false

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

        selectionStyle =
            .none

        backgroundColor =
            UIColor.clear

        contentView.backgroundColor =
            UIColor.clear

        bubbleView.layer.cornerRadius =
            8.0

        bubbleView.layer.masksToBounds =
            true

        contentView.addSubview(
            bubbleView
        )

        messageLabel.backgroundColor =
            UIColor.clear

        messageLabel.font =
            UIFont.systemFont(
                ofSize:
                    13.0
            )

        messageLabel.numberOfLines =
            0

        messageLabel.lineBreakMode =
            .byWordWrapping

        bubbleView.addSubview(
            messageLabel
        )

        detailLabel.backgroundColor =
            UIColor.clear

        detailLabel.font =
            UIFont.systemFont(
                ofSize:
                    10.5
            )

        detailLabel.numberOfLines =
            1

        detailLabel.lineBreakMode =
            .byTruncatingTail

        bubbleView.addSubview(
            detailLabel
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

        outgoing =
            false

        messageLabel.text =
            nil

        detailLabel.text =
            nil
    }

    fileprivate func configure(
        _ message:
            MagnistraMatrixTimelineMessage
    ) {
        outgoing =
            message.isOutgoing

        messageLabel.text =
            message.text

        detailLabel.text =
            message.isEncrypted
                ? "Encrypted"
                : message.detailText

        if outgoing {
            bubbleView.backgroundColor =
                MagnistraPostCell
                    .magnistraBlue

            messageLabel.textColor =
                UIColor.white

            detailLabel.textColor =
                UIColor(
                    white:
                        0.92,
                    alpha:
                        1.0
                )
        } else {
            bubbleView.backgroundColor =
                UIColor(
                    white:
                        0.88,
                    alpha:
                        1.0
                )

            messageLabel.textColor =
                UIColor(
                    white:
                        0.12,
                    alpha:
                        1.0
                )

            detailLabel.textColor =
                UIColor(
                    white:
                        0.38,
                    alpha:
                        1.0
                )
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let maxBubbleWidth =
            max(
                90.0,
                bounds.size.width *
                0.74
            )

        let messageFit =
            messageLabel.sizeThatFits(
                CGSize(
                    width:
                        maxBubbleWidth -
                        20.0,
                    height:
                        10000.0
                )
            )

        let detailText =
            detailLabel.text ?? ""

        let detailFit =
            detailText.isEmpty
                ? CGSize.zero
                : detailLabel.sizeThatFits(
                    CGSize(
                        width:
                            maxBubbleWidth -
                            20.0,
                        height:
                            10000.0
                    )
                )

        let contentWidth =
            max(
                messageFit.width,
                detailFit.width
            )

        let bubbleWidth =
            min(
                maxBubbleWidth,
                max(
                    42.0,
                    contentWidth +
                    20.0
                )
            )

        let detailGap:
            CGFloat =
                detailText.isEmpty
                    ? 0.0
                    : 3.0

        let detailHeight:
            CGFloat =
                detailText.isEmpty
                    ? 0.0
                    : max(
                        11.0,
                        detailFit.height
                    )

        let bubbleHeight =
            max(
                34.0,
                messageFit.height +
                detailGap +
                detailHeight +
                16.0
            )

        let x =
            outgoing
                ? max(
                    8.0,
                    bounds.size.width -
                    bubbleWidth -
                    10.0
                )
                : 10.0

        bubbleView.frame =
            CGRect(
                x:
                    x,
                y:
                    5.0,
                width:
                    bubbleWidth,
                height:
                    bubbleHeight
            )

        messageLabel.frame =
            CGRect(
                x:
                    10.0,
                y:
                    8.0,
                width:
                    max(
                        1.0,
                        bubbleWidth -
                        20.0
                    ),
                height:
                    max(
                        1.0,
                        messageFit.height
                    )
            )

        detailLabel.frame =
            CGRect(
                x:
                    10.0,
                y:
                    8.0 +
                    messageFit.height +
                    detailGap,
                width:
                    max(
                        1.0,
                        bubbleWidth -
                        20.0
                    ),
                height:
                    detailHeight
            )
    }

    fileprivate static func rowHeight(
        for message:
            MagnistraMatrixTimelineMessage,
        width:
            CGFloat
    ) -> CGFloat {
        let messageLabel =
            UILabel()

        messageLabel.font =
            UIFont.systemFont(
                ofSize:
                    13.0
            )

        messageLabel.numberOfLines =
            0

        messageLabel.text =
            message.text

        let detailLabel =
            UILabel()

        detailLabel.font =
            UIFont.systemFont(
                ofSize:
                    10.5
            )

        let detailText =
            message.isEncrypted
                ? "Encrypted"
                : (
                    message.detailText ??
                    ""
                )

        detailLabel.text =
            detailText

        let maxBubbleWidth =
            max(
                90.0,
                width *
                0.74
            )

        let messageFit =
            messageLabel.sizeThatFits(
                CGSize(
                    width:
                        maxBubbleWidth -
                        20.0,
                    height:
                        10000.0
                )
            )

        let detailFit =
            detailText.isEmpty
                ? CGSize.zero
                : detailLabel.sizeThatFits(
                    CGSize(
                        width:
                            maxBubbleWidth -
                            20.0,
                        height:
                            10000.0
                    )
                )

        let detailGap:
            CGFloat =
                detailText.isEmpty
                    ? 0.0
                    : 3.0

        let detailHeight:
            CGFloat =
                detailText.isEmpty
                    ? 0.0
                    : max(
                        11.0,
                        detailFit.height
                    )

        let bubbleHeight =
            max(
                34.0,
                messageFit.height +
                detailGap +
                detailHeight +
                16.0
            )

        return
            bubbleHeight +
            10.0
    }
}

