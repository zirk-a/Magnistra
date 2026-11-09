// Overview: Video control buttons and glyphs.
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



// Shared view tags for photo-music overlays across Home and Explore feeds.
// Keep these values stable: playback code finds the buttons by tag.
enum MagnistraPhotoMusicUITags {
    static let cover = 73420
    static let status = 73421
}

enum MagnistraVideoUITags {
    static let surface = 73170
    static let status = 73171
    static let mute = 73172
    static let fullscreen = 73173
}

enum MagnistraVideoGlyphKind {
    case play
    case stop
    case volume
    case muted
    case fullscreen
    case rotate
    case music
    case close
}

final class MagnistraVideoSurfaceButton:
    UIButton
{
    var mediaID = ""
    var onFullscreenHold: (() -> Void)? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        installFullscreenHold()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installFullscreenHold()
    }

    func installFullscreenHold() {
        let gesture = UILongPressGestureRecognizer(
            target: self, action: #selector(fullscreenHeld(_:)))
        gesture.minimumPressDuration = 0.45
        gesture.cancelsTouchesInView = true
        addGestureRecognizer(gesture)
    }

    @objc private func fullscreenHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onFullscreenHold?() }
    }
}

final class MagnistraVideoGlyphButton:
    UIButton
{
    var mediaID = ""

    var glyphKind:
        MagnistraVideoGlyphKind = .play
    {
        didSet {
            if glyphKind == .music {
                setTitle(
                    "♫",
                    for:
                        .normal
                )

                setTitleColor(
                    UIColor(
                        white: 1.0,
                        alpha: 0.96
                    ),
                    for:
                        .normal
                )

                titleLabel?
                    .font =
                    UIFont.systemFont(
                        ofSize:
                            13.0
                    )
            } else {
                setTitle(
                    nil,
                    for:
                        .normal
                )
            }

            setNeedsDisplay()
        }
    }

    override init(
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        backgroundColor =
            UIColor.clear

        isOpaque = false
    }

    required init?(
        coder: NSCoder
    ) {
        super.init(
            coder: coder
        )

        backgroundColor =
            UIColor.clear

        isOpaque = false
    }

    override func draw(
        _ rect: CGRect
    ) {
        let bounds =
            rect.insetBy(
                dx: 1.0,
                dy: 1.0
            )

        UIColor(
            white: 0.0,
            alpha: 0.62
        ).setFill()

        UIBezierPath(
            roundedRect: bounds,
            cornerRadius: 6.0
        ).fill()

        UIColor(
            white: 1.0,
            alpha: 0.96
        ).setStroke()

        UIColor(
            white: 1.0,
            alpha: 0.96
        ).setFill()

        switch glyphKind {
        case .play:
            let path = UIBezierPath()

            path.move(
                to:
                    CGPoint(
                        x: rect.midX - 4.0,
                        y: rect.midY - 7.0
                    )
            )

            path.addLine(
                to:
                    CGPoint(
                        x: rect.midX + 7.0,
                        y: rect.midY
                    )
            )

            path.addLine(
                to:
                    CGPoint(
                        x: rect.midX - 4.0,
                        y: rect.midY + 7.0
                    )
            )

            path.close()
            path.fill()

        case .stop:
            UIBezierPath(
                rect:
                    CGRect(
                        x: rect.midX - 5.0,
                        y: rect.midY - 5.0,
                        width: 10.0,
                        height: 10.0
                    )
            ).fill()

        case .volume,
             .muted:
            let speaker = UIBezierPath()

            speaker.move(
                to:
                    CGPoint(
                        x: rect.midX - 8.0,
                        y: rect.midY - 3.0
                    )
            )

            speaker.addLine(
                to:
                    CGPoint(
                        x: rect.midX - 4.0,
                        y: rect.midY - 3.0
                    )
            )

            speaker.addLine(
                to:
                    CGPoint(
                        x: rect.midX + 1.0,
                        y: rect.midY - 8.0
                    )
            )

            speaker.addLine(
                to:
                    CGPoint(
                        x: rect.midX + 1.0,
                        y: rect.midY + 8.0
                    )
            )

            speaker.addLine(
                to:
                    CGPoint(
                        x: rect.midX - 4.0,
                        y: rect.midY + 3.0
                    )
            )

            speaker.addLine(
                to:
                    CGPoint(
                        x: rect.midX - 8.0,
                        y: rect.midY + 3.0
                    )
            )

            speaker.close()
            speaker.fill()

            let mutedGlyph: Bool

            switch glyphKind {
            case .muted:
                mutedGlyph = true
            default:
                mutedGlyph = false
            }

            if mutedGlyph {
                let slash = UIBezierPath()
                slash.lineWidth = 2.0

                slash.move(
                    to:
                        CGPoint(
                            x: rect.midX + 3.0,
                            y: rect.midY - 7.0
                        )
                )

                slash.addLine(
                    to:
                        CGPoint(
                            x: rect.midX + 10.0,
                            y: rect.midY + 7.0
                        )
                )

                slash.stroke()
            } else {
                let wave = UIBezierPath()
                wave.lineWidth = 2.0

                wave.move(
                    to:
                        CGPoint(
                            x: rect.midX + 4.0,
                            y: rect.midY - 5.0
                        )
                )

                wave.addQuadCurve(
                    to:
                        CGPoint(
                            x: rect.midX + 4.0,
                            y: rect.midY + 5.0
                        ),
                    controlPoint:
                        CGPoint(
                            x: rect.midX + 10.0,
                            y: rect.midY
                        )
                )

                wave.stroke()
            }

        case .fullscreen:
            let path = UIBezierPath()
            path.lineWidth = 2.0

            let left = rect.midX - 8.0
            let right = rect.midX + 8.0
            let top = rect.midY - 8.0
            let bottom = rect.midY + 8.0

            path.move(to: CGPoint(x: left, y: top + 6.0))
            path.addLine(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left + 6.0, y: top))

            path.move(to: CGPoint(x: right - 6.0, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: top + 6.0))

            path.move(to: CGPoint(x: right, y: bottom - 6.0))
            path.addLine(to: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: right - 6.0, y: bottom))

            path.move(to: CGPoint(x: left + 6.0, y: bottom))
            path.addLine(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: bottom - 6.0))

            path.stroke()

        case .rotate:

            let rotateContext = UIGraphicsGetCurrentContext()
            rotateContext?.saveGState()
            rotateContext?.translateBy(x: rect.midX, y: rect.midY)
            rotateContext?.scaleBy(x: 0.80, y: 0.80)
            rotateContext?.translateBy(x: -rect.midX, y: -rect.midY)

            let cx = rect.midX
            let cy = rect.midY
            let screen = UIBezierPath()
            screen.lineWidth = 2.2
            screen.lineCapStyle = .round
            screen.lineJoinStyle = .round
            screen.move(to: CGPoint(x: cx - 3.9, y: cy - 7.4))
            screen.addQuadCurve(to: CGPoint(x: cx - 1.2, y: cy - 7.4),
                controlPoint: CGPoint(x: cx - 2.6, y: cy - 8.8))
            screen.addLine(to: CGPoint(x: cx + 7.2, y: cy + 1.0))
            screen.addQuadCurve(to: CGPoint(x: cx + 7.2, y: cy + 3.7),
                controlPoint: CGPoint(x: cx + 8.6, y: cy + 2.3))
            screen.addLine(to: CGPoint(x: cx + 3.7, y: cy + 7.2))
            screen.addQuadCurve(to: CGPoint(x: cx + 1.0, y: cy + 7.2),
                controlPoint: CGPoint(x: cx + 2.3, y: cy + 8.6))
            screen.addLine(to: CGPoint(x: cx - 7.4, y: cy - 1.2))
            screen.addQuadCurve(to: CGPoint(x: cx - 7.4, y: cy - 3.9),
                controlPoint: CGPoint(x: cx - 8.8, y: cy - 2.6))
            screen.close()
            screen.stroke()

            let upperArc = UIBezierPath()
            upperArc.lineWidth = 2.5
            upperArc.lineCapStyle = .round
            upperArc.move(to: CGPoint(x: cx + 10.1, y: cy - 0.7))
            upperArc.addCurve(to: CGPoint(x: cx + 3.4, y: cy - 8.7),
                controlPoint1: CGPoint(x: cx + 10.4, y: cy - 5.7),
                controlPoint2: CGPoint(x: cx + 7.6, y: cy - 8.8))
            upperArc.stroke()
            let upperHead = UIBezierPath()
            upperHead.move(to: CGPoint(x: cx + 1.5, y: cy - 8.8))
            upperHead.addLine(to: CGPoint(x: cx + 5.9, y: cy - 11.0))
            upperHead.addLine(to: CGPoint(x: cx + 5.4, y: cy - 6.0))
            upperHead.close()
            upperHead.fill()

            let lowerArc = UIBezierPath()
            lowerArc.lineWidth = 2.5
            lowerArc.lineCapStyle = .round
            lowerArc.move(to: CGPoint(x: cx - 10.2, y: cy + 0.8))
            lowerArc.addCurve(to: CGPoint(x: cx - 3.3, y: cy + 8.5),
                controlPoint1: CGPoint(x: cx - 10.1, y: cy + 5.9),
                controlPoint2: CGPoint(x: cx - 7.4, y: cy + 8.6))
            lowerArc.stroke()
            let lowerHead = UIBezierPath()
            lowerHead.move(to: CGPoint(x: cx - 1.4, y: cy + 8.5))
            lowerHead.addLine(to: CGPoint(x: cx - 5.7, y: cy + 5.7))
            lowerHead.addLine(to: CGPoint(x: cx - 5.8, y: cy + 11.0))
            lowerHead.close()
            lowerHead.fill()
            rotateContext?.restoreGState()

        case .music:
            break

        case .close:
            let path = UIBezierPath()
            path.lineWidth = 2.0

            path.move(
                to:
                    CGPoint(
                        x: rect.midX - 6.0,
                        y: rect.midY - 6.0
                    )
            )

            path.addLine(
                to:
                    CGPoint(
                        x: rect.midX + 6.0,
                        y: rect.midY + 6.0
                    )
            )

            path.move(
                to:
                    CGPoint(
                        x: rect.midX + 6.0,
                        y: rect.midY - 6.0
                    )
            )

            path.addLine(
                to:
                    CGPoint(
                        x: rect.midX - 6.0,
                        y: rect.midY + 6.0
                    )
            )

            path.stroke()
        }
    }
}