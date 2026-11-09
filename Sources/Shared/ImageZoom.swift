// Overview: Image zoom overlay.
import UIKit

final class MagnistraImageZoomOverlay:
    UIView,
    UIScrollViewDelegate
{
    private let scrollView =
        UIScrollView()

    private let imageView =
        UIImageView()

    private let closeButton =
        MagnistraVideoGlyphButton(
            frame: CGRect.zero
        )

    private var statusBarWasHidden =
        false

    init(
        image: UIImage,
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        backgroundColor =
            UIColor.black

        autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        scrollView.backgroundColor =
            UIColor.black

        scrollView.delegate =
            self

        scrollView.minimumZoomScale =
            1.0

        scrollView.maximumZoomScale =
            4.0

        scrollView.bouncesZoom =
            true

        scrollView.showsHorizontalScrollIndicator =
            false

        scrollView.showsVerticalScrollIndicator =
            false

        addSubview(
            scrollView
        )

        imageView.image =
            image

        imageView.contentMode =
            .scaleAspectFit

        imageView.backgroundColor =
            UIColor.black

        imageView.isUserInteractionEnabled =
            true

        scrollView.addSubview(
            imageView
        )

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

        let doubleTap =
            UITapGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        doubleTapped(
                            _:
                        )
                    )
            )

        doubleTap.numberOfTapsRequired =
            2

        imageView.addGestureRecognizer(
            doubleTap
        )

        let hold = UILongPressGestureRecognizer(
            target: self, action: #selector(fullscreenHeld(_:)))
        hold.minimumPressDuration = 0.45
        hold.cancelsTouchesInView = true
        scrollView.addGestureRecognizer(hold)
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil {
            statusBarWasHidden =
                UIApplication.shared
                    .isStatusBarHidden

            UIApplication.shared
                .setStatusBarHidden(
                    true,
                    with:
                        .fade
                )
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": true])

        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        scrollView.frame =
            bounds

        if
            scrollView.zoomScale <=
                1.001
        {
            imageView.frame =
                scrollView.bounds
        }

        closeButton.frame =
            CGRect(
                x: 10.0,
                y: 10.0,
                width: 34.0,
                height: 34.0
            )

        bringSubviewToFront(
            closeButton
        )
    }

    func viewForZooming(
        in scrollView: UIScrollView
    ) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(
        _ scrollView: UIScrollView
    ) {
        let bounds =
            scrollView.bounds

        var frame =
            imageView.frame

        frame.origin.x =
            frame.size.width <
                bounds.size.width
                ? (
                    bounds.size.width -
                    frame.size.width
                ) * 0.5
                : 0.0

        frame.origin.y =
            frame.size.height <
                bounds.size.height
                ? (
                    bounds.size.height -
                    frame.size.height
                ) * 0.5
                : 0.0

        imageView.frame =
            frame
    }

    @objc private func doubleTapped(
        _ recognizer:
            UITapGestureRecognizer
    ) {
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(
                1.0,
                animated:
                    true
            )
        } else {
            scrollView.setZoomScale(
                2.0,
                animated:
                    true
            )
        }
    }

    @objc private func fullscreenHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { closeTapped() }
    }

    @objc private func closeTapped() {
        UIApplication.shared
            .setStatusBarHidden(
                statusBarWasHidden,
                with:
                    .fade
            )

        removeFromSuperview()
        NotificationCenter.default.post(
            name: Notification.Name("MagnistraFullscreenStatusBarChanged"),
            object: self, userInfo: ["hidden": false])
    }

    static func present(
        image: UIImage
    ) -> Bool {
        let app =
            UIApplication.shared

        guard
            let window =
                app.keyWindow ??
                app.windows.first
        else {
            return false
        }

        let overlay =
            MagnistraImageZoomOverlay(
                image:
                    image,
                frame:
                    window.bounds
            )

        window.addSubview(
            overlay
        )

        overlay.setNeedsLayout()

        return true
    }
}
