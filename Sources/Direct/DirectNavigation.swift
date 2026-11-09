// Overview: Direct thread: opening photos, videos and shared Instagram links or posts from messages.
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

extension MagnistraDirectThreadViewController {


    func openDirectPhoto(
        _ message:
            MagnistraDirectMessage
    ) {
        let remoteURL =
            message.mediaURL ??
            message.previewURL

        guard
            let remoteURL =
                remoteURL,
            !remoteURL.isEmpty
        else {
            return
        }

        let controller =
            MagnistraDirectPhotoViewController(
                remoteURL:
                    remoteURL,
                stableKey:
                    "direct-photo-open-" +
                    message.messageID
            )

        navigationController?
            .pushViewController(
                controller,
                animated:
                    true
            )
    }

    func openDirectVideo(
        _ message:
            MagnistraDirectMessage
    ) {
        guard
            let raw =
                message.mediaURL,
            let url =
                URL(
                    string:
                        raw
                )
        else {
            return
        }

        let controller =
            MPMoviePlayerViewController(
                contentURL:
                    url
            )

        presentMoviePlayerViewControllerAnimated(
            controller
        )
    }

    func matrixInstagramLink(in text: String) -> String? {
        guard magnistraDirectIsMatrix else { return nil }
        let expression = "https?://(?:www\\.)?instagram\\.com/(?:p|reel|tv)/[A-Za-z0-9_-]+/?"
        guard let regex = try? NSRegularExpression(pattern: expression,
                                                    options: [.caseInsensitive]) else { return nil }
        let source = text as NSString
        let full = NSRange(location: 0, length: source.length)
        guard let match = regex.firstMatch(in: text, options: [], range: full) else { return nil }
        return source.substring(with: match.range)
    }

    func directSharedShortcode(
        _ raw:
            String
    ) -> String? {
        let path =
            raw
                .components(
                    separatedBy:
                        "?"
                )
                .first ??
            raw

        let parts =
            path.split(
                separator:
                    "/",
                omittingEmptySubsequences:
                    true
            )

        guard
            parts.count >= 2
        else {
            return nil
        }

        for index in 0..<(parts.count - 1) {
            let kind =
                String(
                    parts[index]
                )
                .lowercased()

            if
                kind == "p" ||
                kind == "reel" ||
                kind == "tv"
            {
                let shortcode =
                    String(
                        parts[
                            index + 1
                        ]
                    )

                return
                    shortcode.isEmpty
                        ? nil
                        : shortcode
            }
        }

        return nil
    }

    func openDirectSharedTarget(
        _ message:
            MagnistraDirectMessage
    ) {
        guard let raw = message.targetURL else {
            if message.previewURL != nil { openDirectPhoto(message) }
            return
        }
        openDirectSharedLink(raw)
    }

    func openDirectSharedLink(_ raw: String) {
        guard let shortcode = directSharedShortcode(raw) else { return }
        guard !magnistraDirectOpeningShared.contains(shortcode) else { return }
        magnistraDirectOpeningShared.insert(shortcode)
        loadQueue.addOperation {
            [weak self] in

            do {
                let post =
                    try MagnistraHomeService
                        .loadActivityReferencedPost(
                            shortcode:
                                shortcode
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        guard self.navigationController?.topViewController === self else {
                            self.magnistraDirectOpeningShared.remove(shortcode)
                            return
                        }
                        let controller = MagnistraExploreFeedViewController(
                                selectedPost:
                                    post,
                                deferredPostsProvider: {
                                    []
                                },
                                nextMaxID:
                                    nil,
                                reachedEnd:
                                    true
                            )

                        self.navigationController?
                            .pushViewController(
                                controller,
                                animated:
                                    true
                            )
                    }
            } catch {
                let failure =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation { [weak self] in
                        self?.magnistraDirectOpeningShared.remove(shortcode)
                        let alert =
                            UIAlertView(
                                title:
                                    "Post",
                                message:
                                    failure,
                                delegate:
                                    nil,
                                cancelButtonTitle:
                                    "OK"
                            )

                        alert.show()
                    }
            }
        }
    }
}
