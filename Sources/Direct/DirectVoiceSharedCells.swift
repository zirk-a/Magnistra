// Overview: Direct thread: voice message cell and shared post/reel cells.
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



final class MagnistraDirectVoiceCell:
    MagnistraDirectMessageCell
{
    let playGlyph =
        MagnistraDirectPlayGlyphView()

    private let waveform =
        MagnistraDirectWaveformView()

    private let durationLabel =
        UILabel()

    private var totalDurationMilliseconds:
        Double =
            0.0

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

        waveform.backgroundColor =
            UIColor.clear

        durationLabel.backgroundColor =
            UIColor.clear

        durationLabel.font =
            UIFont.systemFont(
                ofSize:
                    10.5
            )

        durationLabel.textAlignment =
            .right

        bubbleView.addSubview(
            playGlyph
        )

        bubbleView.addSubview(
            waveform
        )

        bubbleView.addSubview(
            durationLabel
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        outgoing =
            message.isOutgoing

        applyTextBubbleStyle()

        waveform.samples =
            message.audioWaveform

        totalDurationMilliseconds =
            max(
                0.0,
                message.audioDurationMilliseconds
            )

        let totalSeconds =
            Int(
                max(
                    0.0,
                    message.audioDurationMilliseconds /
                    1000.0
                )
            )

        durationLabel.text =
            String(
                format:
                    "%d:%02d",
                totalSeconds / 60,
                totalSeconds % 60
            )

        if outgoing {
            playGlyph.glyphColor =
                UIColor.white

            waveform.barColor =
                UIColor.white

            durationLabel.textColor =
                UIColor(
                    white:
                        0.92,
                    alpha:
                        1.0
                )
        } else {
            let blue =
                MagnistraPostCell
                    .magnistraBlue

            playGlyph.glyphColor =
                blue

            waveform.barColor =
                blue

            durationLabel.textColor =
                UIColor(
                    white:
                        0.36,
                    alpha:
                        1.0
                )
        }

        waveform.playbackProgress =
            0.0

        waveform.playbackActive =
            false

        playGlyph.showsPause =
            false

        setNeedsLayout()
    }

    func setPlayback(
        progress:
            Double,
        elapsedMilliseconds:
            Double,
        playing:
            Bool
    ) {
        let bounded =
            max(
                0.0,
                min(
                    1.0,
                    progress
                )
            )

        waveform.playbackProgress =
            CGFloat(
                bounded
            )

        waveform.playbackActive =
            playing ||
            bounded >
                0.0

        playGlyph.showsPause =
            playing

        let displayMilliseconds =
            playing
                ? max(
                    0.0,
                    elapsedMilliseconds
                )
                : totalDurationMilliseconds

        let displaySeconds =
            Int(
                displayMilliseconds /
                1000.0
            )

        durationLabel.text =
            String(
                format:
                    "%d:%02d",
                displaySeconds /
                    60,
                displaySeconds %
                    60
            )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width =
            min(
                214.0,
                bounds.size.width *
                0.74
            )

        bubbleView.frame =
            CGRect(
                x:
                    alignedX(
                        width:
                            width
                    ),
                y: 5.0,
                width: width,
                height: 46.0
            )

        playGlyph.frame =
            CGRect(
                x: 9.0,
                y: 11.0,
                width: 24.0,
                height: 24.0
            )

        waveform.frame =
            CGRect(
                x: 42.0,
                y: 10.0,
                width:
                    max(
                        40.0,
                        width -
                        88.0
                    ),
                height: 26.0
            )

        durationLabel.frame =
            CGRect(
                x:
                    max(
                        44.0,
                        width -
                        42.0
                    ),
                y: 14.0,
                width: 34.0,
                height: 18.0
            )
            magnistraDirectKeepBubbleInside()
    }

    static func rowHeight()
        -> CGFloat
    {
        return 56.0
    }
}

class MagnistraDirectSharedCell:
    MagnistraDirectPreviewCell
{
    let kindGlyph =
        MagnistraDirectSharedKindGlyphView()

    private let authorLabel =
        UILabel()

    private let kindLabel =
        UILabel()

    var reel =
        false

    var aspect:
        CGFloat =
            1.0

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

        bubbleView.backgroundColor =
            UIColor(
                white:
                    0.97,
                alpha:
                    1.0
            )

        bubbleView.layer.cornerRadius =
            9.0

        bubbleView.layer.borderWidth =
            0.5

        bubbleView.layer.borderColor =
            UIColor(
                white:
                    0.73,
                alpha:
                    1.0
            )
            .cgColor

        bubbleView.clipsToBounds =
            true

        previewView.layer.cornerRadius =
            0.0

        authorLabel.backgroundColor =
            UIColor.clear

        authorLabel.textColor =
            UIColor(
                white:
                    0.20,
                alpha:
                    1.0
            )

        authorLabel.font =
            UIFont.boldSystemFont(
                ofSize:
                    11.5
            )

        authorLabel.lineBreakMode =
            .byTruncatingTail

        kindLabel.backgroundColor =
            UIColor.clear

        kindLabel.textColor =
            UIColor(
                white:
                    0.48,
                alpha:
                    1.0
            )

        kindLabel.font =
            UIFont.boldSystemFont(
                ofSize:
                    9.0
            )

        kindLabel.textAlignment =
            .right

        bubbleView.addSubview(
            kindGlyph
        )

        bubbleView.addSubview(
            authorLabel
        )

        bubbleView.addSubview(
            kindLabel
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    func configureShared(
        _ message:
            MagnistraDirectMessage,
        reel:
            Bool
    ) {
        self.reel =
            reel

        aspect =
            CGFloat(
                max(
                    0.35,
                    min(
                        2.5,
                        message.mediaAspectRatio
                    )
                )
            )

        kindGlyph.isReel =
            reel

        kindLabel.text =
            reel
                ? "REEL"
                : "POST"

        let detail =
            message.detailText?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ) ??
            ""

        if
            !detail.isEmpty,
            detail.lowercased() !=
                "shared post",
            detail.lowercased() !=
                "shared reel"
        {
            authorLabel.text =
                detail
        } else {
            authorLabel.text =
                reel
                    ? "shared Reel"
                    : "shared Post"
        }

        configurePreview(
            message
        )

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width =
            min(
                218.0,
                bounds.size.width *
                0.74
            )

        let headerHeight:
            CGFloat =
                36.0

        let previewHeight =
            max(
                110.0,
                min(
                    205.0,
                    width /
                    max(
                        0.35,
                        aspect
                    )
                )
            )

        let height =
            headerHeight +
            previewHeight

        bubbleView.frame =
            CGRect(
                x:
                    alignedX(
                        width:
                            width
                    ),
                y: 5.0,
                width: width,
                height: height
            )

        kindGlyph.frame =
            CGRect(
                x: 8.0,
                y: 9.0,
                width: 18.0,
                height: 18.0
            )

        kindLabel.frame =
            CGRect(
                x:
                    max(
                        1.0,
                        width -
                        46.0
                    ),
                y: 9.0,
                width: 38.0,
                height: 18.0
            )

        authorLabel.frame =
            CGRect(
                x: 32.0,
                y: 8.0,
                width:
                    max(
                        1.0,
                        width -
                        82.0
                    ),
                height: 20.0
            )

        previewView.frame =
            CGRect(
                x: 0.0,
                y: headerHeight,
                width: width,
                height: previewHeight
            )
    }

    static func rowHeight(
        for message:
            MagnistraDirectMessage,
        width:
            CGFloat
    ) -> CGFloat {
        let cardWidth =
            min(
                218.0,
                width *
                0.74
            )

        let aspect =
            CGFloat(
                max(
                    0.35,
                    min(
                        2.5,
                        message.mediaAspectRatio
                    )
                )
            )

        let previewHeight =
            max(
                110.0,
                min(
                    205.0,
                    cardWidth /
                    aspect
                )
            )

        return
            36.0 +
            previewHeight +
            10.0
    }
}

final class MagnistraDirectSharedPostCell:
    MagnistraDirectSharedCell
{
    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        configureShared(
            message,
            reel: false
        )
    }
}

final class MagnistraDirectSharedReelCell:
    MagnistraDirectSharedCell
{
    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        configureShared(
            message,
            reel: true
        )
    }
}