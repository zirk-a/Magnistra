// Overview: Explore: search mode button inside the search field.
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


    func installSearchModeButtonInField() {
        searchModeButton.removeFromSuperview()

        if usesIOS8PlusFixedSearch {

            if let field = searchTextField(in: searchBar) {
                field.leftView = ios7SearchSpacer
                field.leftViewMode = .always
                field.placeholder = ""
            }
            searchBarHost.addSubview(searchModeButton)
            layoutIOS8PlusSearchControls()
            return
        }
        if usesIOS7SearchControls {

            if let field = searchTextField(in: searchBar) {
                field.leftView = ios7SearchSpacer
                field.leftViewMode = .always
            }
            searchBarHost.addSubview(searchModeButton)
            layoutIOS7SearchControls()
            return
        }

        guard
            let field =
                searchTextField(
                    in:
                        searchBar
                )
        else {
            searchModeButton.frame =
                CGRect(
                    x: 8.0,
                    y: 8.0,
                    width: 28.0,
                    height: 28.0
                )

            searchBar.addSubview(
                searchModeButton
            )
            return
        }

        searchModeButton.frame =
            CGRect(
                x: 0.0,
                y: 0.0,
                width: 28.0,
                height: 28.0
            )

        field.leftView =
            searchModeButton

        field.leftViewMode =
            .always
    }
}
