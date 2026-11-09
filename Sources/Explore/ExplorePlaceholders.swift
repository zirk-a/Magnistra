// Overview: Explore: placeholder tiles shown while the grid loads.
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

extension ExploreViewController {


    func placeholderColor(
        for index: Int
    ) -> UIColor {
        guard
            !placeholderColors.isEmpty
        else {
            return UIColor.lightGray
        }

        if
            placeholderColorOrder.count ==
                placeholderColors.count
        {
            let slot =
                index %
                placeholderColorOrder.count

            return placeholderColors[
                placeholderColorOrder[
                    slot
                ]
            ]
        }

        return placeholderColors[
            index %
            placeholderColors.count
        ]
    }

    func installInitialPlaceholders() {
        removeAllPlaceholders()

        placeholderColorOrder =
            Array(
                0..<placeholderColors.count
            )

        if placeholderColorOrder.count > 1 {
            var position =
                placeholderColorOrder.count -
                1

            while position > 0 {
                let swapIndex =
                    Int(
                        arc4random_uniform(
                            UInt32(
                                position +
                                1
                            )
                        )
                    )

                if swapIndex != position {
                    let temporary =
                        placeholderColorOrder[
                            position
                        ]

                    placeholderColorOrder[
                        position
                    ] =
                        placeholderColorOrder[
                            swapIndex
                        ]

                    placeholderColorOrder[
                        swapIndex
                    ] =
                        temporary
                }

                position -= 1
            }
        }

        for index in 0..<(magnistraSavedGrid ? 15 : 12) {
            addPlaceholder(
                for: index
            )
        }

        layoutGrid()
    }

    func addPlaceholder(
        for index: Int
    ) {
        let tag =
            placeholderTagBase +
            index

        if
            scrollView.viewWithTag(
                tag
            ) != nil
        {
            return
        }

        let placeholder =
            UIView(
                frame: CGRect.zero
            )

        placeholder.tag =
            tag

        placeholder.backgroundColor =
            placeholderColor(
                for: index
            )

        placeholder.isUserInteractionEnabled =
            false

        placeholderViews.append(
            placeholder
        )

        scrollView.addSubview(
            placeholder
        )
    }

    func removePlaceholder(
        for index: Int
    ) {
        let tag =
            placeholderTagBase +
            index

        if let view =
            scrollView.viewWithTag(
                tag
            )
        {
            view.removeFromSuperview()
        }

        placeholderViews =
            placeholderViews.filter {
                $0.tag != tag
            }
    }

    func removeAllPlaceholders() {
        for view in placeholderViews {
            view.removeFromSuperview()
        }

        placeholderViews.removeAll(
            keepingCapacity: true
        )
    }
}
