// Overview: Image URL selection and fetching/caching of public images.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func preferredImageURL(
        from media: [String: Any],
        quality: MagnistraPhotoQuality
    ) -> String? {
        guard
            let versions =
                media["image_versions2"]
                    as? [String: Any],
            let candidates =
                versions["candidates"]
                    as? [[String: Any]],
            !candidates.isEmpty
        else {
            return nil
        }

        let targetWidth =
            quality.targetWidth

        var firstURL:
            String? = nil

        var largestAreaURL:
            String? = nil

        var largestArea =
            0

        var largestAreaAspect:
            Double? = nil

        for candidate in candidates {
            guard
                let url =
                    candidate["url"]
                        as? String,
                !url.isEmpty
            else {
                continue
            }

            if firstURL == nil {
                firstURL = url
            }

            let width =
                intValue(
                    candidate["width"]
                ) ?? 0

            let height =
                intValue(
                    candidate["height"]
                ) ?? 0

            guard
                width > 0,
                height > 0
            else {
                continue
            }

            let area =
                width * height

            if area > largestArea {
                largestArea = area
                largestAreaURL = url
                largestAreaAspect =
                    Double(width) /
                    Double(height)
            }
        }

        var referenceAspect =
            largestAreaAspect

        let originalWidth =
            intValue(
                media["original_width"]
            ) ?? 0

        let originalHeight =
            intValue(
                media["original_height"]
            ) ?? 0

        if
            originalWidth > 0,
            originalHeight > 0
        {
            let originalAspect =
                Double(originalWidth) /
                Double(originalHeight)

            var nearestOriginalDelta =
                Double.greatestFiniteMagnitude

            for candidate in candidates {
                let width =
                    intValue(
                        candidate["width"]
                    ) ?? 0

                let height =
                    intValue(
                        candidate["height"]
                    ) ?? 0

                if
                    width > 0,
                    height > 0
                {
                    let delta =
                        abs(
                            Double(width) /
                            Double(height) -
                            originalAspect
                        )

                    if delta < nearestOriginalDelta {
                        nearestOriginalDelta = delta
                    }
                }
            }

            if nearestOriginalDelta <= 0.025 {
                referenceAspect =
                    originalAspect
            }
        }

        guard
            let wantedAspect =
                referenceAspect
        else {
            return
                largestAreaURL ??
                firstURL
        }

        let aspectTolerance =
            max(
                0.020,
                wantedAspect * 0.015
            )

        var aboveURL:
            String? = nil

        var aboveWidth =
            Int.max

        var belowURL:
            String? = nil

        var belowWidth =
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

            let height =
                intValue(
                    candidate["height"]
                ) ?? 0

            guard
                width > 0,
                height > 0
            else {
                continue
            }

            let candidateAspect =
                Double(width) /
                Double(height)

            if
                abs(
                    candidateAspect -
                    wantedAspect
                ) > aspectTolerance
            {
                continue
            }

            if width >= targetWidth {
                if width < aboveWidth {
                    aboveWidth = width
                    aboveURL = url
                }
            } else if width > belowWidth {
                belowWidth = width
                belowURL = url
            }
        }

        return
            aboveURL ??
            belowURL ??
            largestAreaURL ??
            firstURL
    }

    static func fetchPublicImageBytes(
        url: String,
        caPath: String,
        userAgent: String
    ) -> Data? {
        let curlCode: Int32 =
            caPath.withCString { ca in
                userAgent
                    .withCString { ua in
                    url.withCString {
                        imageURL in
                        Int32(
                            magnistra_transport_fetch_public_image(
                                ca,
                                ua,
                                imageURL
                            )
                        )
                    }
                }
            }

        guard
            curlCode == 0,
            magnistra_transport_http_status()
                >= 200,
            magnistra_transport_http_status()
                < 300,
            magnistra_transport_tls_verify_result()
                == 0
        else {
            return nil
        }

        let length =
            Int(
                magnistra_transport_body_length()
            )

        guard
            length > 0,
            let pointer =
                magnistra_transport_body()
        else {
            return nil
        }

        return Data(
            bytes: pointer,
            count: length
        )
    }

    static func cachedPublicImagePath(
        kind: MagnistraMediaCacheKind,
        stableKey: String,
        url: String,
        caPath: String,
        userAgent: String
    ) -> String? {
        let limits =
            cacheLimits(
                kind: kind
            )

        guard let path =
            cachePath(
                kind: kind,
                stableKey: stableKey
            )
        else {
            return nil
        }

        if let fresh =
            freshCachePath(
                path: path,
                ttl: limits.ttl
            )
        {
            return fresh
        }

        let stale =
            staleCachePath(
                path: path
            )

        guard let data = fetchPublicImageBytes(
            url: url, caPath: caPath, userAgent: userAgent
        ), !data.isEmpty else { return stale }

        let cacheBytes: Data
        if let nativeImage = UIImage(data: data),
           nativeImage.size.width > 0.0 && nativeImage.size.height > 0.0 {
            cacheBytes = data
        } else if visitedGridWebPHeader(data) {
            guard let png = visitedGridWebPAsPNG(
                data, maxEdge: kind == .avatar ? 384 : 1024) else {
                return stale
            }
            cacheBytes = png
        } else { return stale }

        do {
            try cacheBytes.write(
                to: URL(
                    fileURLWithPath: path
                ),
                options: .atomic
            )

            let now = Date()

            try? FileManager.default
                .setAttributes(
                    [
                        .creationDate: now,
                        .modificationDate: now
                    ],
                    ofItemAtPath: path
                )

            enforceCacheBudget(
                kind: kind
            )

            return path
        } catch {
            return stale
        }
    }

    static func timelineDisplayMedia(
        from row:
            [String: Any]
    ) -> [String: Any] {
        let isMetricTrackingEnabled = MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("DISPLAY_NORMALIZE", metricStartedAt) } }

        if
            let exploreStory =
                row["explore_story"]
                    as? [String: Any],
            let media =
                exploreStory["media_or_ad"]
                    as? [String: Any]
        {
            return media
        }

        return mediaObject(
            from:
                row
        )
    }

    static func cachedPublicImagePathIfPresent(
        kind: MagnistraMediaCacheKind,
        stableKey: String
    ) -> String? {
        let isMetricTrackingEnabled = MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("CACHE_LOOKUP", metricStartedAt) } }

        guard
            let path =
                cachePath(
                    kind:
                        kind,
                    stableKey:
                        stableKey
                ),
            FileManager.default
                .fileExists(
                    atPath:
                        path
                )
        else {
            return nil
        }

        touchCacheFile(
            path
        )

        return path
    }

    static func materializeFeedImage(
        url: String,
        stableKey: String,
        isAvatar: Bool
    ) -> String? {
        let isMetricTrackingEnabled = MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("IMAGE_MATERIALIZE", metricStartedAt) } }

        guard
            !url.isEmpty,
            !stableKey.isEmpty
        else {
            return nil
        }

        let kind:
            MagnistraMediaCacheKind =
                isAvatar
                    ? .avatar
                    : .post

        let limits =
            cacheLimits(
                kind:
                    kind
            )

        guard
            let path =
                cachePath(
                    kind:
                        kind,
                    stableKey:
                        stableKey
                )
        else {
            return nil
        }

        if let fresh =
            freshCachePath(
                path:
                    path,
                ttl:
                    limits.ttl
            )
        {
            return fresh
        }

        let stale =
            staleCachePath(
                path:
                    path
            )

        guard
            let session =
                try? loadSession(),
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                ),
            let data =
                MagnistraLazyImageTransport
                    .fetch(
                        url:
                            url,
                        caPath:
                            caPath,
                        userAgent:
                            session.userAgent
                    ),
            !data.isEmpty
        else {
            return stale
        }

        let cacheBytes: Data
        if let ordinary = UIImage(data: data),
           ordinary.size.width > 0.0 && ordinary.size.height > 0.0 {
            cacheBytes = data
        } else if visitedGridWebPHeader(data) {

            guard let png = visitedGridWebPAsPNG(
                data, maxEdge: isAvatar ? 384 : 1024) else {
                return stale
            }
            cacheBytes = png
        } else {
            return stale
        }

        do {
            try cacheBytes.write(
                to:
                    URL(
                        fileURLWithPath:
                            path
                    ),
                options:
                    .atomic
            )

            let now =
                Date()

            try? FileManager.default
                .setAttributes(
                    [
                        .creationDate:
                            now,
                        .modificationDate:
                            now
                    ],
                    ofItemAtPath:
                        path
                )

            enforceCacheBudget(
                kind:
                    kind
            )

            return path
        } catch {
            return stale
        }
    }

    static func visitedGridUnsupportedImageReason(_ data: Data) -> String {
        let h = [UInt8](data.prefix(20))
        if h.count >= 12 && h[0] == 0x52 && h[1] == 0x49 &&
           h[2] == 0x46 && h[3] == 0x46 && h[8] == 0x57 &&
           h[9] == 0x45 && h[10] == 0x42 && h[11] == 0x50 {
            return "WebP image\nunsupported"
        }
        if h.count >= 12 && h[4] == 0x66 && h[5] == 0x74 &&
           h[6] == 0x79 && h[7] == 0x70 {
            let brand = String(bytes: h[8..<12], encoding: .ascii) ?? ""
            if brand.hasPrefix("avif") || brand == "avis" {
                return "AVIF image\nunsupported"
            }
            if brand.hasPrefix("hei") || brand.hasPrefix("mif") {
                return "HEIC image\nunsupported"
            }
        }
        if h.count >= 5 && h[0] == 0x3c &&
           (h[1] == 0x21 || h[1] == 0x68 || h[1] == 0x48) {
            return "HTML, not\nan image"
        }
        return "Image format\nnot decoded"
    }

    static func visitedGridWebPHeader(_ data: Data) -> Bool {
        let h = [UInt8](data.prefix(12))
        return h.count == 12 && h[0] == 0x52 && h[1] == 0x49 &&
               h[2] == 0x46 && h[3] == 0x46 && h[8] == 0x57 &&
               h[9] == 0x45 && h[10] == 0x42 && h[11] == 0x50
    }

    static func visitedGridWebPAsPNG(
        _ bytes: Data, maxEdge: Int32 = 384
    ) -> Data? {
        var ownedRGBA: UnsafeMutablePointer<UInt8>? = nil
        var width: Int32 = 0
        var height: Int32 = 0
        let status: Int32 = bytes.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress
            return magnistraWebPDecodeThumbnailRGBA(
                ptr, bytes.count, maxEdge, &ownedRGBA, &width, &height)
        }
        guard status == 1, let buffer = ownedRGBA else { return nil }
        defer { magnistraWebPFreeThumbnail(buffer) }
        guard width > 0, height > 0, width <= maxEdge, height <= maxEdge else {
            return nil
        }
        let stride = Int(width) * 4
        let rgba = Data(bytes: buffer, count: stride * Int(height))
        guard let provider = CGDataProvider(data: rgba as CFData) else {
            return nil
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let cg = CGImage(
            width: Int(width), height: Int(height), bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: stride, space: cs,
            bitmapInfo: info, provider: provider,
            decode: nil, shouldInterpolate: true,
            intent: .defaultIntent) else { return nil }
        let image = UIImage(cgImage: cg)
        return image.pngData()
    }

    static func materializeVisitedProfileGridImage(
        url: String, stableKey: String
    ) -> (path: String?, failure: String, retryable: Bool) {
        guard !url.isEmpty else { return (nil, "Image URL\nmissing", false) }
        guard !stableKey.isEmpty,
              let path = cachePath(kind: .post, stableKey: stableKey) else {
            return (nil, "Image cache\nunavailable", false)
        }
        let ttl = cacheLimits(kind: .post).ttl
        if let fresh = freshCachePath(path: path, ttl: ttl),
           let valid = UIImage(contentsOfFile: fresh),
           valid.size.width > 0.0, valid.size.height > 0.0 {
            return (fresh, "", false)
        }

        let stale = staleCachePath(path: path)
        func validStale() -> String? {
            guard let previous = stale,
                  let img = UIImage(contentsOfFile: previous),
                  img.size.width > 0.0, img.size.height > 0.0 else { return nil }
            return previous
        }
        guard let session = try? loadSession() else {
            return (validStale(), "Session not\navailable", false)
        }
        guard let caPath = Bundle.main.path(
            forResource: "CACert", ofType: "pem") else {
            return (validStale(), "CA bundle\nmissing", false)
        }
        guard let data = MagnistraLazyImageTransport.fetch(
            url: url, caPath: caPath, userAgent: session.userAgent) else {

            return (validStale(), "Transport\nreturned nil", true)
        }
        guard !data.isEmpty else {
            return (validStale(), "Image body\nempty", true)
        }

        let cacheBytes: Data
        if let ordinary = UIImage(data: data),
           ordinary.size.width > 0.0 && ordinary.size.height > 0.0 {
            cacheBytes = data
        } else if visitedGridWebPHeader(data) {
            guard let png = visitedGridWebPAsPNG(data) else {
                return (validStale(), "WebP decode\nfailed", false)
            }
            cacheBytes = png
        } else {
            return (validStale(), visitedGridUnsupportedImageReason(data), false)
        }
        do {
            try cacheBytes.write(to: URL(fileURLWithPath: path), options: .atomic)
            let now = Date()
            try? FileManager.default.setAttributes(
                [.creationDate: now, .modificationDate: now], ofItemAtPath: path)
            enforceCacheBudget(kind: .post)
            return (path, "", false)
        } catch {
            return (validStale(), "Image cache\nwrite failed", false)
        }
    }
}
