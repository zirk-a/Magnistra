// Overview: Photo music: info, images and playback URLs for photo-music posts.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func photoMusicInfo(
        from media: [String: Any]
    ) -> (
        title: String,
        artist: String,
        audioURL: String,
        startTimeMs: Int
    )? {

        guard
            intValue(
                media["media_type"]
            ) == 1,
            let imageVersions =
                media["image_versions2"]
                    as? [String: Any],
            let imageCandidates =
                imageVersions["candidates"]
                    as? [[String: Any]],
            !imageCandidates.isEmpty
        else {
            return nil
        }

        var hasStaticImageCandidate = false

        for candidate in imageCandidates {
            if
                let url =
                    candidate["url"]
                        as? String,
                !url.isEmpty
            {
                hasStaticImageCandidate = true
                break
            }
        }

        guard hasStaticImageCandidate else {
            return nil
        }

        if
            let videos =
                media["video_versions"]
                    as? [[String: Any]],
            !videos.isEmpty
        {
            return nil
        }

        var containers:
            [[String: Any]] = []

        if let music =
            media["music_metadata"]
                as? [String: Any]
        {
            containers.append(
                music
            )
        }

        if let clips =
            media["clips_metadata"]
                as? [String: Any]
        {
            containers.append(
                clips
            )
        }

        for container in containers {
            if let musicInfo =
                container["music_info"]
                    as? [String: Any]
            {
                let asset =
                    (
                        musicInfo[
                            "music_asset_info"
                        ] as? [String: Any]
                    ) ??
                    musicInfo

                let audioURL =
                    (
                        asset[
                            "fast_start_progressive_download_url"
                        ] as? String
                    ) ??
                    (
                        asset[
                            "progressive_download_url"
                        ] as? String
                    ) ??
                    ""

                if !audioURL.isEmpty {
                    let title =
                        (
                            asset["title"]
                                as? String
                        ) ??
                        (
                            asset[
                                "sanitized_title"
                            ] as? String
                        ) ??
                        "Music"

                    let artist =
                        (
                            asset[
                                "display_artist"
                            ] as? String
                        ) ??
                        (
                            asset["subtitle"]
                                as? String
                        ) ??
                        ""

                    var startTimeMs =
                        intValue(
                            asset[
                                "audio_asset_start_time_in_ms"
                            ]
                        ) ?? 0

                    if
                        startTimeMs <= 0,
                        let highlights =
                            asset[
                                "highlight_start_times_in_ms"
                            ] as? [Any],
                        let first =
                            highlights.first
                    {
                        startTimeMs =
                            intValue(
                                first
                            ) ?? 0
                    }

                    return (
                        title:
                            title,
                        artist:
                            artist,
                        audioURL:
                            audioURL,
                        startTimeMs:
                            max(
                                0,
                                startTimeMs
                            )
                    )
                }
            }

            if let sound =
                container["original_sound_info"]
                    as? [String: Any]
            {
                let audioURL =
                    (
                        sound[
                            "fast_start_progressive_download_url"
                        ] as? String
                    ) ??
                    (
                        sound[
                            "progressive_download_url"
                        ] as? String
                    ) ??
                    ""

                if !audioURL.isEmpty {
                    let title =
                        (
                            sound[
                                "original_audio_title"
                            ] as? String
                        ) ??
                        "Original audio"

                    var artist = ""

                    if let igArtist =
                        sound["ig_artist"]
                            as? [String: Any]
                    {
                        artist =
                            (
                                igArtist["full_name"]
                                    as? String
                            ) ??
                            (
                                igArtist["username"]
                                    as? String
                            ) ??
                            ""
                    }

                    let startTimeMs =
                        intValue(
                            sound[
                                "audio_asset_start_time_in_ms"
                            ]
                        ) ?? 0

                    return (
                        title:
                            title,
                        artist:
                            artist,
                        audioURL:
                            audioURL,
                        startTimeMs:
                            max(
                                0,
                                startTimeMs
                            )
                    )
                }
            }
        }

        return nil
    }

    static func carouselMediaItems(
        from media: [String: Any],
        quality: MagnistraPhotoQuality
    ) -> [MagnistraCarouselMedia] {
        guard let children = media["carousel_media"] as? [[String: Any]],
              children.count > 1 else { return [] }
        var result: [MagnistraCarouselMedia] = []
        for (index, wrapper) in children.prefix(20).enumerated() {
            let child = timelineDisplayMedia(from: wrapper)
            guard let imageURL = preferredFeedImageURL(from: child, quality: quality),
                  !imageURL.isEmpty else { continue }
            let mediaID = stringValue(child["pk"]) ??
                stringValue(child["id"]) ??
                ((stringValue(media["pk"]) ?? "carousel") + ":" + String(index))
            let versions = child["video_versions"] as? [[String: Any]] ?? []
            var videoURL: String? = nil
            var videoWidth = 0
            var videoHeight = 0
            for version in versions {
                guard let candidate = version["url"] as? String,
                      !candidate.isEmpty else { continue }
                if videoURL == nil {
                    videoURL = candidate
                    videoWidth = intValue(version["width"]) ?? 0
                    videoHeight = intValue(version["height"]) ?? 0
                }
            }
            result.append(MagnistraCarouselMedia(
                mediaID: mediaID,
                imageURL: imageURL,
                videoURL: videoURL,
                videoWidth: videoWidth,
                videoHeight: videoHeight
            ))
        }
        return result.count > 1 ? result : []
    }

    static func preferredFeedImageURL(
        from media: [String: Any],
        quality: MagnistraPhotoQuality
    ) -> String? {
        let isMetricTrackingEnabled = MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("IMAGE_SELECT", metricStartedAt) } }

        guard
            photoMusicInfo(
                from:
                    media
            ) != nil
        else {

            return preferredImageURL(
                from:
                    media,
                quality:
                    quality
            )
        }

        guard
            let versions =
                media["image_versions2"]
                    as? [String: Any],
            let candidates =
                versions["candidates"]
                    as? [[String: Any]],
            !candidates.isEmpty
        else {
            return preferredImageURL(
                from:
                    media,
                quality:
                    quality
            )
        }

        let targetWidth =
            640

        var smallestAbove:
            String? = nil

        var smallestAboveWidth =
            Int.max

        var largestBelow:
            String? = nil

        var largestBelowWidth =
            0

        for candidate in candidates {
            guard
                let url =
                    candidate["url"]
                        as? String,
                !url.isEmpty
            else {
                continue
            }

            let width =
                intValue(
                    candidate["width"]
                ) ?? 0

            if
                width >= targetWidth,
                width < smallestAboveWidth
            {
                smallestAbove =
                    url

                smallestAboveWidth =
                    width
            } else if
                width > largestBelowWidth
            {
                largestBelow =
                    url

                largestBelowWidth =
                    width
            }
        }

        return
            smallestAbove ??
            largestBelow ??
            preferredImageURL(
                from:
                    media,
                quality:
                    quality
            )
    }

    static func photoMusicFallbackImageURL(
        from media: [String: Any],
        excluding primary: String
    ) -> String? {
        guard
            photoMusicInfo(from: media) != nil,
            let versions = media["image_versions2"] as? [String: Any],
            let candidates = versions["candidates"] as? [[String: Any]],
            !candidates.isEmpty
        else {
            return nil
        }

        let targetWidth = 640
        var bestURL: String? = nil
        var bestDistance = Int.max
        var unknownWidthURL: String? = nil

        for candidate in candidates {
            guard
                let url = candidate["url"] as? String,
                !url.isEmpty,
                url != primary
            else {
                continue
            }

            let width = intValue(candidate["width"]) ?? 0

            if width <= 0 {
                if unknownWidthURL == nil {
                    unknownWidthURL = url
                }
                continue
            }

            let distance = width >= targetWidth ? width - targetWidth : targetWidth - width
            if distance < bestDistance {
                bestDistance = distance
                bestURL = url
            }
        }

        return bestURL ?? unknownWidthURL
    }

    static func photoMusicImageData(
        url: String
    ) -> Data? {
        guard
            !url.isEmpty,
            let session =
                try? loadSession(),
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                )
        else {
            return nil
        }

        return MagnistraLazyImageTransport
            .fetch(
                url:
                    url,
                caPath:
                    caPath,
                userAgent:
                    session.userAgent
            )
    }

    static func localPhotoMusicPlaybackURL(
        for post: MagnistraRealPost
    ) throws -> URL? {
        guard
            post.videoURL == nil,
            let remote =
                post.musicAudioURL,
            !remote.isEmpty
        else {
            return nil
        }

        let session =
            try loadSession()

        guard
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                )
        else {
            throw NSError(
                domain:
                    "MagnistraPhotoMusic",
                code:
                    5501,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        return StreamProxy
            .shared
            .localURL(
                for:
                    remote,
                caPath:
                    caPath,
                userAgent:
                    session.userAgent
            )
    }
}
