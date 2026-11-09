// Overview: Fullscreen video overlay.
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



final class MagnistraFullscreenVideoOverlay:
    UIView,
    UIGestureRecognizerDelegate
{
    var videoLayer:
        AVPlayerLayer? = nil

    var onClose:
        (() -> Void)? = nil

    var onMute:
        (() -> Bool)? = nil

    let closeButton =
        MagnistraVideoGlyphButton(
            frame: CGRect.zero
        )

    private let muteButton =
        MagnistraVideoGlyphButton(
            frame: CGRect.zero
        )

    private let rotateButton =
        MagnistraVideoGlyphButton(frame: CGRect.zero)

    private var isVideoQuarterTurn = false

    private var controlsVisible =
        true

    private var videoZoomScale:
        CGFloat = 1.0

    private var pinchStartScale:
        CGFloat = 1.0

    private var videoPanStartTranslation:
        CGPoint = .zero

    private var videoPanCurrentTranslation:
        CGPoint = .zero

    private let autoHideDelay:
        TimeInterval = 2.5

    override init(
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        backgroundColor =
            UIColor.black

        closeButton.glyphKind =
            .close

        closeButton.addTarget(
            self,
            action:
                #selector(
                    closeTapped
                ),
            for:
                .touchUpInside
        )

        addSubview(
            closeButton
        )

        muteButton.glyphKind =
            .volume

        muteButton.addTarget(
            self,
            action:
                #selector(
                    muteTapped
                ),
            for:
                .touchUpInside
        )

        addSubview(
            muteButton
        )

        rotateButton.glyphKind = .rotate
        rotateButton.accessibilityLabel = "Rotate video"
        rotateButton.addTarget(self, action: #selector(rotateTapped),
                               for: .touchUpInside)
        addSubview(rotateButton)

        let tap =
            UITapGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        overlayTapped(
                            _:
                        )
                    )
            )

        tap.cancelsTouchesInView =
            false

        tap.delegate =
            self

        addGestureRecognizer(
            tap
        )

        let hold = UILongPressGestureRecognizer(
            target: self, action: #selector(fullscreenHeld(_:)))
        hold.minimumPressDuration = 0.45
        hold.cancelsTouchesInView = true
        hold.delegate = self
        addGestureRecognizer(hold)

        let pinch =
            UIPinchGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        videoPinched(
                            _:
                        )
                    )
            )

        pinch.cancelsTouchesInView =
            false

        addGestureRecognizer(
            pinch
        )

        let pan =
            UIPanGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        videoPanned(
                            _:
                        )
                    )
            )

        pan.maximumNumberOfTouches =
            1

        pan.cancelsTouchesInView =
            false

        addGestureRecognizer(
            pan
        )
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil {
            showControls(
                animated:
                    false
            )
        } else {
            cancelAutoHide()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let layer =
            videoLayer
        {
            CATransaction.begin()
            CATransaction.setDisableActions(
                true
            )

            let rotated = isVideoQuarterTurn
            layer.bounds = CGRect(x: 0, y: 0,
                width: rotated ? bounds.height : bounds.width,
                height: rotated ? bounds.width : bounds.height)
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)

            let extraX =
                max(
                    0.0,
                    ((bounds.size.width *
                      videoZoomScale) -
                     bounds.size.width) / 2.0
                )

            let extraY =
                max(
                    0.0,
                    ((bounds.size.height *
                      videoZoomScale) -
                     bounds.size.height) / 2.0
                )

            let clampedX =
                min(
                    max(
                        videoPanCurrentTranslation.x,
                        -extraX
                    ),
                    extraX
                )

            let clampedY =
                min(
                    max(
                        videoPanCurrentTranslation.y,
                        -extraY
                    ),
                    extraY
                )

            videoPanCurrentTranslation =
                CGPoint(
                    x: clampedX,
                    y: clampedY
                )

            layer.setAffineTransform(
                CGAffineTransform(rotationAngle: rotated ? CGFloat.pi / 2.0 : 0.0)
                .scaledBy(x: videoZoomScale, y: videoZoomScale)
                .translatedBy(x: clampedX / max(videoZoomScale, 1.0),
                              y: clampedY / max(videoZoomScale, 1.0))
            )

            CATransaction.commit()
        }

        closeButton.frame =
            CGRect(
                x:
                    10.0,
                y:
                    10.0,
                width:
                    32.0,
                height:
                    32.0
            )

        muteButton.frame =
            CGRect(
                x: 10.0,
                y: bounds.size.height - 42.0,
                width: 32.0,
                height: 32.0
            )

        rotateButton.frame = CGRect(
            x: bounds.size.width - 42.0,
            y: bounds.size.height - 42.0,
            width: 32.0, height: 32.0)
        bringSubviewToFront(closeButton)
        bringSubviewToFront(muteButton)
        bringSubviewToFront(rotateButton)
    }

    func setMuted(
        _ muted: Bool
    ) {
        muteButton.glyphKind =
            muted
                ? .muted
                : .volume
    }

    func cancelAutoHide() {
        NSObject.cancelPreviousPerformRequests(
            withTarget:
                self,
            selector:
                #selector(
                    autoHideControls
                ),
            object:
                nil
        )
    }

    private func scheduleAutoHide() {
        cancelAutoHide()

        perform(
            #selector(
                autoHideControls
            ),
            with:
                nil,
            afterDelay:
                autoHideDelay
        )
    }

    private func showControls(
        animated: Bool
    ) {
        cancelAutoHide()

        controlsVisible =
            true

        closeButton.isHidden =
            false

        muteButton.isHidden =
            false
        rotateButton.isHidden = false

        closeButton.isUserInteractionEnabled =
            true

        muteButton.isUserInteractionEnabled =
            true
        rotateButton.isUserInteractionEnabled = true

        if animated {
            closeButton.alpha =
                0.0

            muteButton.alpha =
                0.0
            rotateButton.alpha = 0.0

            UIView.animate(
                withDuration:
                    0.18,
                animations: {
                    [weak self] in

                    self?.closeButton.alpha =
                        1.0

                    self?.muteButton.alpha =
                        1.0
                    self?.rotateButton.alpha = 1.0
                }
            )
        } else {
            closeButton.alpha =
                1.0

            muteButton.alpha =
                1.0
            rotateButton.alpha = 1.0
        }

        scheduleAutoHide()
    }

    private func hideControls(
        animated: Bool
    ) {
        cancelAutoHide()

        controlsVisible =
            false

        closeButton.isUserInteractionEnabled =
            false

        muteButton.isUserInteractionEnabled =
            false
        rotateButton.isUserInteractionEnabled = false

        let finish: () -> Void = {
            [weak self] in

            guard
                let self =
                    self
            else {
                return
            }

            if !self.controlsVisible {
                self.closeButton.isHidden =
                    true

                self.muteButton.isHidden =
                    true
                self.rotateButton.isHidden = true
            }
        }

        if animated {
            UIView.animate(
                withDuration:
                    0.18,
                animations: {
                    [weak self] in

                    self?.closeButton.alpha =
                        0.0

                    self?.muteButton.alpha =
                        0.0
                    self?.rotateButton.alpha = 0.0
                },
                completion: {
                    _ in
                    finish()
                }
            )
        } else {
            closeButton.alpha =
                0.0

            muteButton.alpha =
                0.0
            rotateButton.alpha = 0.0

            finish()
        }
    }

    @objc private func autoHideControls() {
        hideControls(
            animated:
                true
        )
    }

    @objc private func overlayTapped(
        _ recognizer:
            UITapGestureRecognizer
    ) {
        guard
            recognizer.state ==
                .ended
        else {
            return
        }

        if controlsVisible {
            hideControls(
                animated:
                    true
            )
        } else {
            showControls(
                animated:
                    true
            )
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer:
            UIGestureRecognizer,
        shouldReceive touch:
            UITouch
    ) -> Bool {
        return
            !(touch.view is UIControl)
    }

    @objc private func videoPinched(
        _ recognizer:
            UIPinchGestureRecognizer
    ) {
        switch recognizer.state {
        case .began:
            pinchStartScale =
                videoZoomScale

        case .changed:
            let next =
                pinchStartScale *
                recognizer.scale

            videoZoomScale =
                min(
                    4.0,
                    max(
                        1.0,
                        next
                    )
                )

            setNeedsLayout()

        case .ended,
             .cancelled,
             .failed:
            if videoZoomScale < 1.02 {
                videoZoomScale =
                    1.0
            }

            setNeedsLayout()

        default:
            break
        }
    }

    func resetVideoZoom() {
        videoPanStartTranslation =
            .zero

        videoPanCurrentTranslation =
            .zero

        videoZoomScale =
            1.0

        pinchStartScale =
            1.0

        setNeedsLayout()
    }

    @objc private func videoPanned(
        _ recognizer:
            UIPanGestureRecognizer
    ) {
        guard
            videoZoomScale >
                1.01
        else {
            return
        }

        switch recognizer.state {
        case .began:
            videoPanStartTranslation =
                videoPanCurrentTranslation

        case .changed:
            let delta =
                recognizer.translation(
                    in: self
                )

            videoPanCurrentTranslation =
                CGPoint(
                    x:
                        videoPanStartTranslation.x +
                        delta.x,
                    y:
                        videoPanStartTranslation.y +
                        delta.y
                )

            setNeedsLayout()

        case .ended,
             .cancelled,
             .failed:
            setNeedsLayout()

        default:
            break
        }
    }

    @objc private func fullscreenHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            cancelAutoHide()
            onClose?()
        }
    }

    @objc private func closeTapped() {
        cancelAutoHide()
        onClose?()
    }

    @objc private func rotateTapped() {
        isVideoQuarterTurn = !isVideoQuarterTurn
        resetVideoZoom()
        layoutIfNeeded()
        showControls(animated: false)
    }

    @objc private func muteTapped() {
        if let muted =
            onMute?()
        {
            setMuted(
                muted
            )
        }

        showControls(
            animated:
                false
        )
    }
}