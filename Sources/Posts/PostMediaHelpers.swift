// Overview: Post cell helpers: relative time, avatars and photo-music long press.
import UIKit
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import Security
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration

extension MagnistraPostCell {


    static func relativeTime(
        timestamp: Double
    ) -> String {
        if timestamp <= 0 {
            return ""
        }

        let age =
            max(
                0.0,
                Date().timeIntervalSince1970 -
                timestamp
            )

        if age < 60.0 {
            return "just now"
        }

        if age < 3600.0 {
            return "\(Int(age / 60.0)) min ago"
        }

        if age < 86400.0 {
            return "\(Int(age / 3600.0)) hr ago"
        }

        return "\(Int(age / 86400.0)) d ago"
    }

    static func makeAvatarImage(
        size: CGSize,
        variant: Int
    ) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(
            size,
            false,
            0.0
        )

        let colors: [UIColor] = [
            UIColor(
                red: 0.34,
                green: 0.52,
                blue: 0.67,
                alpha: 1.0
            ),
            UIColor(
                red: 0.50,
                green: 0.42,
                blue: 0.60,
                alpha: 1.0
            ),
            UIColor(
                red: 0.36,
                green: 0.57,
                blue: 0.44,
                alpha: 1.0
            )
        ]

        colors[
            variant %
            colors.count
        ].setFill()

        UIBezierPath(
            roundedRect:
                CGRect(
                    x: 0.0,
                    y: 0.0,
                    width: size.width,
                    height: size.height
                ),
            cornerRadius: 4.0
        ).fill()

        UIColor(
            white: 1.0,
            alpha: 0.82
        ).setFill()

        UIBezierPath(
            ovalIn:
                CGRect(
                    x: 9.0,
                    y: 5.0,
                    width: 12.0,
                    height: 12.0
                )
        ).fill()

        UIBezierPath(
            roundedRect:
                CGRect(
                    x: 5.0,
                    y: 18.0,
                    width: 20.0,
                    height: 10.0
                ),
            cornerRadius: 5.0
        ).fill()

        let image =
            UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return image ?? UIImage()
    }

    func installHomePhotoMusicLongPressIfNeeded() {
        let longPressTargets:
            [UIView] = [
                photoView,
                photoMusicFullscreenButton
            ]

        for target in longPressTargets {
            target.isUserInteractionEnabled =
                true

            let alreadyInstalled =
                target
                    .gestureRecognizers?
                    .contains(
                        where: {
                            $0 is
                                UILongPressGestureRecognizer &&
                            $0.view === target
                        }
                    ) ?? false

            if alreadyInstalled {
                continue
            }

            let recognizer =
                UILongPressGestureRecognizer(
                    target:
                        self,
                    action:
                        #selector(
                            homePhotoMusicOverlayLongPressed(
                                _:
                            )
                        )
                )

            recognizer.minimumPressDuration =
                0.45

            recognizer.cancelsTouchesInView =
                true

            target.addGestureRecognizer(
                recognizer
            )
        }
    }

    @objc func homePhotoMusicOverlayLongPressed(
        _ recognizer:
            UILongPressGestureRecognizer
    ) {
        guard
            recognizer.state ==
                .began
        else {
            return
        }

        normalPhotoLongPressed(
            recognizer
        )
    }
}
