// Home-only GraphQL response adapter.  No request/transport behavior is changed here.
// 2026-11-21 H2 trace: PolarisFeedRootPaginationCachedQuery_subscribe.
// Instagram response:
// data.xdt_api__v1__feed__timeline__connection.edges[].node.media
// data.xdt_api__v1__feed__timeline__connection.page_info.end_cursor
import Foundation
import CoreFoundation

extension MagnistraHomeService {
    // Process-local UUID, never logged and never stored in .mgsession.
    static let homeGraphQLDeviceID: String = {
        let uuid = CFUUIDCreate(kCFAllocatorDefault)
        let text = CFUUIDCreateString(kCFAllocatorDefault, uuid)
        var characters = [CChar](repeating: 0, count: 64)
        if let text = text {
            let ok = characters.withUnsafeMutableBufferPointer { ptr in
                CFStringGetCString(text, ptr.baseAddress, CFIndex(ptr.count),
                    CFStringBuiltInEncodings.UTF8.rawValue)
            }
            if ok { return String(cString: characters) }
        }
        return "00000000-0000-4000-8000-000000000000"
    }()

    // A browser sends cookies only if their domain and path match the
    // requested host. The generic legacy Session loader flattens all
    // *.instagram.com cookies, which is correct for its existing legacy
    // requests but NOT a faithful web GraphQL cookie context.
    // This routine is Home-only and never writes cookies to disk.
    static func homeWWWSessionContext(
        fallbackCookies: String, fallbackCSRF: String
    ) -> (cookies: String, csrf: String, deviceID: String,
          source: String, deviceSource: String) {
        var snapshot = MagnistraV2SessionCache.snapshot()
        if snapshot == nil, let folder = documentsPath() {
            let path = (folder as NSString).appendingPathComponent("MagnistraSession.mgsession")
            if let disk = try? Data(contentsOf: URL(fileURLWithPath: path)),
               !disk.starts(with: [77,71,83,69,83,83,73,79,78,50,0,0]) {
                snapshot = disk
            }
        }
        var resolved = fallbackCookies
        var csrf = fallbackCSRF
        var source = "legacy_fallback"
        if let content = snapshot,
           let decoded = try? MagnistraJSONKit.jsonObject(with: content, options: []),
           let root = decoded as? [String: Any],
           let list = root["cookies"] as? [[String: Any]] {
            var best: [String: (value: String, rank: Int)] = [:]
            let now = Date().timeIntervalSince1970
            for cookie in list {
                guard let name = cookie["name"] as? String,
                      let value = cookie["value"] as? String,
                      let rawDomain = cookie["domain"] as? String,
                      !name.isEmpty, !value.isEmpty,
                      !name.contains(";"), !name.contains("\r"), !name.contains("\n"),
                      !value.contains(";"), !value.contains("\r"), !value.contains("\n")
                else { continue }
                let host = rawDomain.lowercased()
                // Parent-domain cookies and exact www-host cookies only.
                // Exclude host-only i.instagram.com and unrelated subdomains.
                let rank: Int
                if host == "www.instagram.com" { rank = 2 }
                else if host == ".instagram.com" || host == "instagram.com" { rank = 1 }
                else { continue }
                let path = (cookie["path"] as? String) ?? "/"
                guard path == "/" else { continue }
                if let expires = cookie["expires"] as? NSNumber,
                   expires.doubleValue > 0 && expires.doubleValue <= now { continue }
                if let previous = best[name], previous.rank > rank { continue }
                best[name] = (value: value, rank: rank)
            }
            if let selectedCSRF = best["csrftoken"]?.value,
               let selectedSession = best["sessionid"]?.value,
               !selectedCSRF.isEmpty, !selectedSession.isEmpty {
                resolved = best.keys.sorted().compactMap { key in
                    best[key].map { key + "=" + $0.value }
                }.joined(separator: "; ")
                csrf = selectedCSRF
                source = "web_host_scoped"
            }
        }
        var device = homeGraphQLDeviceID
        var deviceSource = "generated"
        let parts = resolved.components(separatedBy: "; ")
        if let field = parts.first(where: { $0.hasPrefix("ig_did=") }) {
            let candidate = String(field.dropFirst("ig_did=".count))
            let segments = candidate.split(separator: "-", omittingEmptySubsequences: false)
            let expected = [8,4,4,4,12]
            let valid = segments.count == 5 && zip(segments,expected).allSatisfy { seg,count in
                seg.count == count && seg.utf8.allSatisfy { byte in
                    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) ||
                    (byte >= 97 && byte <= 102)
                }
            }
            if valid {
                device = candidate
                deviceSource = "session_ig_did"
            }
        }
        // No tokens, identifiers, values or hashes appear in logs.
        return (cookies: resolved, csrf: csrf, deviceID: device,
                source: source, deviceSource: deviceSource)
    }

    // H4 verified this five-key data map with HTTP 200 and 5 feed edges. A later
    // pagination request also contained feed_view_info, which is optional.
    // H4 live: variant=home, first=12, and flags verified; initial cursor not observed.
    // Explicit device identity derived from the imported browser's ig_did
    // when available; a process-local UUID is only a last resort.
    static func homeGraphQLVariables(cursor: String, deviceID: String) -> [String: Any] {
        return [
            "after": cursor,
            "before": NSNull(),
            "data": [
                "device_id": deviceID,
                "is_async_ads_double_request": "0",
                "is_async_ads_in_headload_enabled": "0",
                "is_async_ads_rti": "0",
                "rti_delivery_backend": "0"
            ],
            "first": 12,
            "last": NSNull(),
            "variant": "home",
            "__relay_internal__pv__PolarisAdDebugToolEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider": true,
            // Five fields present in modern browser FULL Home trace, absent in R12.
            // Browser values are redacted by the trace; false is a typed default.
            "__relay_internal__pv__PolarisProductTagIndicatorEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisMultiCaptionCarouselEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisThreadsStyleCommentsEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisReelsRecoDebugOverlayEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisSuggestedUserFeedUnitCardsEnabledrelayprovider": false
        ]
    }

    static func homeGraphQLPage(
        root: [String: Any],
        previousCursor: String?
    ) -> (rows: [[String: Any]], nextCursor: String?)? {
        guard
            let data = root["data"] as? [String: Any],
            let connection = data["xdt_api__v1__feed__timeline__connection"] as? [String: Any],
            let edges = connection["edges"] as? [[String: Any]]
        else {
            return nil
        }

        var rows: [[String: Any]] = []
        rows.reserveCapacity(edges.count)

        for edge in edges {
            guard let node = edge["node"] as? [String: Any] else {
                continue
            }
            // FULL H1-H6+FULL shows native media and explore_story media units.
            // Preserve the existing post builder's ["media_or_ad"] interface.
            var selectedMedia = node["media"] as? [String: Any]
            if selectedMedia == nil,
                let explore = node["explore_story"] as? [String: Any] {
                selectedMedia = explore["media"] as? [String: Any]
            }
            guard let media = selectedMedia else {
                // Ads and non-media units need their own decoders; don't fake posts.
                continue
            }

            var normalized = media
            // Web GraphQL commonly calls the media author 'owner'.
            // Old Home post builder expects 'user'; preserve if already present.
            if normalized["user"] == nil,
                let owner = normalized["owner"] as? [String: Any] {
                normalized["user"] = owner
            }
            rows.append(["media_or_ad": normalized])
        }

        var cursor: String? = nil
        if
            let pageInfo = connection["page_info"] as? [String: Any],
            boolValue(pageInfo["has_next_page"]) == true,
            let next = pageInfo["end_cursor"] as? String,
            !next.isEmpty,
            next != previousCursor
        {
            cursor = next
        }
        return (rows: rows, nextCursor: cursor)
    }
}
