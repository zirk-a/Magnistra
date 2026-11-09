// Overview: Explore: search bar delegate callbacks.
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


    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if usesIOS7SearchControls {
            ios7QueryText = searchText
            layoutIOS7SearchControls()
        }
        layoutIOS8PlusSearchControls()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {

        searchBar.resignFirstResponder()
    }

    func searchBarTextDidBeginEditing(
        _ searchBar: UISearchBar
    ) {
        if usesIOS7SearchControls {
            ios7SearchEditing = true
            layoutIOS7SearchControls()
        } else {
            if usesIOS8PlusFixedSearch { ios8PlusSearchEditing = true }
            searchBar.showsCancelButton = true
        }
        layoutIOS8PlusSearchControls()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        if usesIOS7SearchControls {
            ios7SearchEditing = false
            layoutIOS7SearchControls()
        }
        if usesIOS8PlusFixedSearch { ios8PlusSearchEditing = false }
        layoutIOS8PlusSearchControls()
    }

    func searchBarCancelButtonClicked(
        _ searchBar: UISearchBar
    ) {
        if usesIOS7SearchControls { ios7QueryText = "" }
        searchBar.text = ""
        searchTextField(in: searchBar)?.text = ""
        searchBar.resignFirstResponder()
        searchTextField(in: searchBar)?.resignFirstResponder()
        if usesIOS7SearchControls {
            ios7SearchEditing = false
            layoutIOS7SearchControls()
        } else {
            if usesIOS8PlusFixedSearch { ios8PlusSearchEditing = false }
            searchBar.showsCancelButton = false
        }
        layoutIOS8PlusSearchControls()
    }

    @objc func ios7CancelTapped(_ sender: UIButton) {
        searchBarCancelButtonClicked(searchBar)
    }

    @objc func ios7ClearTapped(_ sender: UIButton) {
        guard usesIOS7SearchControls else { return }
        ios7QueryText = ""
        searchBar.text = ""
        searchTextField(in: searchBar)?.text = ""

        updateIOS7SearchTextControls()
    }

    func searchBarSearchButtonClicked(
        _ searchBar: UISearchBar
    ) {
        let raw =
            (
                searchBar.text ??
                ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard
            !raw.isEmpty
        else {
            return
        }

        let routedQuery:
            String

        if
            raw.hasPrefix("#") ||
            raw.hasPrefix("@")
        {
            routedQuery =
                raw
        } else if searchModeIsTag {
            routedQuery =
                "#" +
                raw
        } else {
            routedQuery =
                "@" +
                raw
        }

        searchBar.resignFirstResponder()
        if usesIOS7SearchControls {
            ios7SearchEditing = false
            layoutIOS7SearchControls()
        } else {
            searchBar.showsCancelButton = false
        }

        if routedQuery.hasPrefix("#") {
            var tag =
                routedQuery

            while tag.hasPrefix("#") {
                tag.removeFirst()
            }

            tag =
                tag.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

            guard !tag.isEmpty else {
                return
            }

            navigationController?
                .pushViewController(
                    MagnistraExploreTagGridViewController(
                        tag:
                            tag,
                        searchSessionID:
                            MagnistraHomeService
                                .makeExploreSearchSessionID()
                    ),
                    animated:
                        true
                )

            return
        }

        navigationController?
            .pushViewController(
                MagnistraExploreSearchResultsViewController(
                    query:
                        routedQuery
                ),
                animated:
                    true
            )
    }

    @objc func searchModeTapped(
        _ sender: UIButton
    ) {
        searchModeIsTag.toggle()

        sender.setTitle(
            searchModeIsTag
                ? "#"
                : "@",
            for:
                .normal
        )

        if usesIOS7SearchControls {
            searchBar.placeholder = ""
            ios7SearchPlaceholder.text = searchModeIsTag
                ? "Search tags" : "Search users"
        } else if usesIOS8PlusFixedSearch {
            ios8PlusIdlePlaceholder.text = searchModeIsTag
                ? "Search tags" : "Search users"
        } else {
            searchBar.placeholder = searchModeIsTag
                ? "Search tags" : "Search users"
        }
        layoutIOS8PlusSearchControls()

        if !(searchTextField(in: searchBar)?.isFirstResponder ?? searchBar.isFirstResponder) {
            searchBar.becomeFirstResponder()
        }
        if usesIOS7SearchControls {
            ios7SearchEditing = true
            layoutIOS7SearchControls()
        }
    }

    func searchTextField(
        in view: UIView
    ) -> UITextField? {
        if let field =
            view as? UITextField
        {
            return field
        }

        for child in view.subviews {
            if
                let found =
                    searchTextField(
                        in:
                            child
                    )
            {
                return found
            }
        }

        return nil
    }

    func makeIOS7ClearGlyph() -> UIImage? {

        UIGraphicsBeginImageContextWithOptions(CGSize(width: 18.0, height: 18.0),
                                               false, 0.0)
        defer { UIGraphicsEndImageContext() }
        let disc = UIBezierPath(ovalIn: CGRect(x: 1.0, y: 1.0,
                                              width: 16.0, height: 16.0))
        UIColor(white: 0.62, alpha: 0.90).setFill()
        disc.fill()
        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: 6.3, y: 6.3))
        cross.addLine(to: CGPoint(x: 11.7, y: 11.7))
        cross.move(to: CGPoint(x: 11.7, y: 6.3))
        cross.addLine(to: CGPoint(x: 6.3, y: 11.7))
        cross.lineCapStyle = .round
        cross.lineWidth = 1.55
        UIColor.white.setStroke()
        cross.stroke()
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    func updateIOS7SearchTextControls() {
        guard usesIOS7SearchControls else { return }
        let hasText = !ios7QueryText.isEmpty
        ios7SearchPlaceholder.isHidden = hasText
        ios7ClearButton.isHidden = !hasText
    }

    func layoutIOS7SearchControls() {
        guard usesIOS7SearchControls else { return }

        let width = max(1.0, searchBarHost.bounds.width)
        let cancelWidth: CGFloat = ios7SearchEditing ? 65.0 : 0.0
        searchBar.frame = CGRect(x: 0.0, y: 0.0,
                                 width: max(1.0, width - cancelWidth),
                                 height: 44.0)
        ios7CancelButton.frame = CGRect(x: width - 65.0, y: 0.0,
                                       width: 65.0, height: 44.0)
        ios7CancelButton.isHidden = !ios7SearchEditing
        searchBar.layoutIfNeeded()
        if let field = searchTextField(in: searchBar) {
            field.placeholder = ""
            field.textAlignment = .left
            field.contentVerticalAlignment = .center
            field.clearButtonMode = .never
            if field.leftView !== ios7SearchSpacer {
                field.leftView = ios7SearchSpacer
                field.leftViewMode = .always
            }

            let centerInHost = field.convert(
                CGPoint(x: field.bounds.midX, y: field.bounds.midY),
                to: searchBarHost).y
            let offset = 22.0 - centerInHost
            if abs(offset) > 0.5 && abs(offset) < 20.0 {
                var nativeFrame = field.frame
                nativeFrame.origin.y += offset
                field.frame = nativeFrame
            }
            ios7SearchPlaceholder.font = field.font ?? UIFont.systemFont(ofSize: 14.0)
            if ios7SearchEditing {

                if ios7SearchPlaceholder.superview !== field {
                    ios7SearchPlaceholder.removeFromSuperview()
                    field.addSubview(ios7SearchPlaceholder)
                }
                let nativeTextRect = field.editingRect(forBounds: field.bounds)
                ios7SearchPlaceholder.frame = CGRect(
                    x: nativeTextRect.minX + 3.0,
                    y: nativeTextRect.minY,
                    width: max(1.0, nativeTextRect.width - 3.0),
                    height: nativeTextRect.height)
                field.bringSubviewToFront(ios7SearchPlaceholder)
            } else {

                if ios7SearchPlaceholder.superview !== searchBarHost {
                    ios7SearchPlaceholder.removeFromSuperview()
                    searchBarHost.addSubview(ios7SearchPlaceholder)
                }
                ios7SearchPlaceholder.frame = CGRect(
                    x: 46.0, y: 11.0,
                    width: max(1.0, searchBar.frame.width - 80.0),
                    height: 22.0)
                searchBarHost.bringSubviewToFront(ios7SearchPlaceholder)
            }
        }

        searchModeButton.frame = CGRect(x: 12.0, y: 8.0,
                                        width: 28.0, height: 28.0)
        ios7ClearButton.frame = CGRect(x: max(0.0, searchBar.frame.width - 40.0),
            y: 8.0, width: 28.0, height: 28.0)
        ios7SearchPlaceholder.text = searchModeIsTag ? "Search tags" : "Search users"
        updateIOS7SearchTextControls()
        searchBarHost.bringSubviewToFront(searchModeButton)
        searchBarHost.bringSubviewToFront(ios7ClearButton)
        searchBarHost.bringSubviewToFront(ios7CancelButton)
    }

    func layoutIOS8PlusSearchControls() {
        guard usesIOS8PlusFixedSearch else { return }

        searchModeButton.frame = CGRect(x: 12.0, y: 8.0,
                                        width: 28.0, height: 28.0)
        let activeCancel = searchBar.showsCancelButton
        let field = searchTextField(in: searchBar)
        if let nativeField = field {
            nativeField.placeholder = ""
            nativeField.textAlignment = .left
            ios8PlusIdlePlaceholder.font = nativeField.font ?? UIFont.systemFont(ofSize: 14.0)
        }
        if ios8PlusSearchEditing, let nativeField = field {

            if ios8PlusIdlePlaceholder.superview !== nativeField {
                ios8PlusIdlePlaceholder.removeFromSuperview()
                nativeField.addSubview(ios8PlusIdlePlaceholder)
            }
            let textRect = nativeField.editingRect(forBounds: nativeField.bounds)
            ios8PlusIdlePlaceholder.frame = CGRect(
                x: textRect.minX + 3.0, y: textRect.minY,
                width: max(1.0, textRect.width - 3.0), height: textRect.height)
            nativeField.bringSubviewToFront(ios8PlusIdlePlaceholder)
        } else {

            if ios8PlusIdlePlaceholder.superview !== searchBarHost {
                ios8PlusIdlePlaceholder.removeFromSuperview()
                searchBarHost.addSubview(ios8PlusIdlePlaceholder)
            }
            ios8PlusIdlePlaceholder.frame = CGRect(
                x: 46.0, y: 11.0,
                width: max(1.0, searchBarHost.bounds.width - (activeCancel ? 130.0 : 66.0)),
                height: 22.0)
            searchBarHost.bringSubviewToFront(ios8PlusIdlePlaceholder)
        }
        ios8PlusIdlePlaceholder.text = searchModeIsTag ? "Search tags" : "Search users"
        ios8PlusIdlePlaceholder.isHidden = !(searchBar.text ?? "").isEmpty
        searchBarHost.bringSubviewToFront(searchModeButton)
    }
}
