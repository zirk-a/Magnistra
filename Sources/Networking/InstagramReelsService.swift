// Overview: Reels: page requests.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func reelsNextMaxID(
        from value: Any,
        excluding current: String?
    ) -> String? {
        if let web = value as? [String: Any],
           web["magnistra_web_clips_rows"] != nil {
            let next = (web["next_max_id"] as? String) ?? ""
            return !next.isEmpty && next != current ? next : nil
        }

        guard let root = value as? [String: Any] else {
            return nil
        }

        var envelopes: [[String: Any]] = [root]
        for key in ["data", "response", "clips", "feed"] {
            if let nested = root[key] as? [String: Any] {
                envelopes.append(nested)
            }
        }
        for envelope in envelopes {
            if let paging = envelope["paging_info"] as? [String: Any] {
                if boolValue(paging["more_available"]) == false {
                    return nil
                }
                if let cursor = stringValue(paging["max_id"]),
                   !cursor.isEmpty, cursor != current {
                    return cursor
                }
                if let cursor = stringValue(paging["next_max_id"]),
                   !cursor.isEmpty, cursor != current {
                    return cursor
                }
            }
            if boolValue(envelope["more_available"]) == false {
                return nil
            }
            for key in ["next_max_id", "max_id", "next_cursor"] {
                if let cursor = stringValue(envelope[key]),
                   !cursor.isEmpty, cursor != current {
                    return cursor
                }
            }
        }
        return nil
    }

    static func magnistraWebClipsRoot(
        maxID: String?
    ) throws -> [String: Any] {
        let nextPage = maxID != nil
        let toggles: [String: Any] = [
            "__relay_internal__pv__PolarisReelsRecoDebugOverlayEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider": true,
            "__relay_internal__pv__PolarisThreadsStyleCommentsEnabledrelayprovider": false
        ]
        var variables = toggles
        if let cursor = maxID {
            guard !cursor.isEmpty && cursor.count < 2048 else {
                throw NSError(domain: "MagnistraReelsWeb", code: 7410,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Reels Web page cursor."])
            }
            let seenJSON: String
            if let data = try? MagnistraJSONKit.data(
                withJSONObject: magnistraWebReelSeenIDs, options: []),
               let json = String(data: data, encoding: .utf8) {
                seenJSON = json
            } else {
                seenJSON = "[]"
            }
            variables["after"] = cursor
            variables["before"] = NSNull()
            variables["last"] = NSNull()
            variables["first"] = 10
            variables["data"] = [
                "container_module": "clips_viewer_clips_tab",
                "seen_reels": seenJSON
            ] as [String: Any]
        } else {

            magnistraWebReelSeenIDs.removeAll()

            variables["first"] = 4
            variables["data"] = [
                "container_module": "clips_tab_desktop_page"
            ] as [String: Any]
        }
        let response = try exploreSearchGraphQLRoot(
            variables: variables,
            docID: nextPage ? "39300051022974272" : "28772401909077856",
            friendlyName: nextPage
                ? "PolarisClipsTabRootPaginationQuery"
                : "PolarisClipsHomeRootQuery")
        guard let data = response["data"] as? [String: Any],
              let connection = data["xdt_api__v1__clips__home__connection_v2"]
                    as? [String: Any],
              let edges = connection["edges"] as? [[String: Any]],
              let page = connection["page_info"] as? [String: Any] else {
            throw NSError(domain: "MagnistraReelsWeb", code: 7411,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected Instagram Web Reels response."])
        }
        var videos = [[String: Any]]()
        var pageIDs = [String]()
        var added = Set<String>()
        for edge in edges {
            guard let node = edge["node"] as? [String: Any],
                  let media = node["media"] as? [String: Any],
                  let versions = media["video_versions"] as? [[String: Any]],
                  versions.contains(where: { entry in
                      guard let raw = entry["url"] as? String else { return false }
                      return raw.hasPrefix("https://")
                  }) else { continue }
            let rawID = media["pk"] ?? media["id"]
            let identifier = rawID.map { String(describing: $0) } ?? ""
            if !identifier.isEmpty && !added.insert(identifier).inserted {
                continue
            }
            var resolved = media

            if resolved["media_type"] == nil { resolved["media_type"] = 2 }
            videos.append(resolved)
            if !identifier.isEmpty { pageIDs.append(identifier) }
        }
        let more = (page["has_next_page"] as? Bool) == true
        let cursor = (page["end_cursor"] as? String) ?? ""
        guard !more || !cursor.isEmpty else {
            throw NSError(domain: "MagnistraReelsWeb", code: 7412,
                userInfo: [NSLocalizedDescriptionKey: "Instagram omitted Reels pagination cursor."])
        }
        for identifier in pageIDs where !magnistraWebReelSeenIDs.contains(identifier) {
            magnistraWebReelSeenIDs.append(identifier)
        }
        if magnistraWebReelSeenIDs.count > 200 {
            magnistraWebReelSeenIDs.removeFirst(
                magnistraWebReelSeenIDs.count - 200)
        }

        return [
            "magnistra_web_clips_rows": videos,
            "next_max_id": more ? cursor : "",
            "paging_info": ["more_available": more, "max_id": more ? cursor : ""],
            "more_available": more
        ]
    }

    static func loadReelsPage(
        maxID: String?
    ) throws -> MagnistraReelsPage
    {
        exploreLock.lock()

        defer {
            exploreLock.unlock()
        }

        let pageStart = Date().timeIntervalSince1970
        let root =
            try magnistraWebClipsRoot(
                maxID:
                    maxID
            )
        let networkMs = Int((Date().timeIntervalSince1970 - pageStart) * 1000.0)

        let mediaRows: [[String: Any]] =
            (root["magnistra_web_clips_rows"] as? [[String: Any]]) ?? []

        let username = ""
        let userID = ""

        let photoQuality =
            MagnistraMediaPreferences
                .photoQuality

        var posts:
            [MagnistraRealPost] = []

        for row in mediaRows {
            let media =
                timelineDisplayMedia(
                    from:
                        row
                )

            guard
                intValue(media["media_type"]) == 2,
                let videoVersions = media["video_versions"] as? [[String: Any]],
                !videoVersions.isEmpty
            else { continue }

            guard
                let imageURL =
                    preferredFeedImageURL(
                        from:
                            media,
                        quality:
                            photoQuality
                    )
            else {
                continue
            }

            let user =
                (
                    media["user"]
                        as?
                        [String: Any]
                ) ?? [:]

            let parsedUsername =
                (
                    user["username"]
                        as? String
                ) ??
                username

            if parsedUsername.isEmpty {
                continue
            }

            let parsedUserID =
                stringValue(
                    user["pk"]
                ) ??
                stringValue(
                    user["id"]
                ) ??
                userID

            let mediaID =
                stringValue(
                    media["pk"]
                ) ??
                stringValue(
                    media["id"]
                ) ??
                imageURL

            let fullName =
                (
                    user["full_name"]
                        as? String
                ) ?? ""

            var captionText =
                ""

            if
                let caption =
                    media["caption"]
                        as?
                        [String: Any],
                let text =
                    caption["text"]
                        as?
                        String
            {
                captionText =
                    text
            }

            var locationText =
                ""

            if
                let location =
                    media["location"]
                        as?
                        [String: Any],
                let name =
                    location["name"]
                        as?
                        String
            {
                locationText =
                    name
            }

            let previewObjects =
                (
                    media["preview_comments"]
                        as?
                        [[String: Any]]
                ) ?? []

            var previewComments:
                [MagnistraComment] = []

            for object in previewObjects {
                if
                    let parsed =
                        parseComment(
                            object
                        )
                {
                    previewComments
                        .append(
                            parsed
                        )

                    if
                        previewComments
                            .count >= 2
                    {
                        break
                    }
                }
            }

            let commentCount =
                intValue(
                    media["comment_count"]
                ) ??
                previewComments.count

            let imageCacheKey =
                "explore:" +
                photoQuality.cacheToken +
                ":" +
                mediaID

            let imagePath =
                cachedPublicImagePathIfPresent(
                    kind:
                        .post,
                    stableKey:
                        imageCacheKey
                ) ?? ""

            let avatarURL =
                user["profile_pic_url"]
                    as? String

            let avatarCacheKey =
                "explore-avatar:" +
                parsedUserID

            let avatarPath =
                cachedPublicImagePathIfPresent(
                    kind:
                        .avatar,
                    stableKey:
                        avatarCacheKey
                )

            var videoURL:
                String? =
                    nil

            var videoWidth =
                0

            var videoHeight =
                0

            if
                intValue(
                    media["media_type"]
                ) == 2,
                let versions =
                    media["video_versions"]
                        as?
                        [[String: Any]],
                !versions.isEmpty
            {
                var selected:
                    [String: Any]? =
                        nil

                var selectedBandwidth =
                    Int.max

                for version in versions {
                    guard
                        let candidateURL =
                            version["url"]
                                as? String,
                        !candidateURL.isEmpty
                    else {
                        continue
                    }

                    let bandwidth =
                        intValue(
                            version["bandwidth"]
                        ) ??
                        Int.max

                    if
                        selected == nil ||
                        bandwidth <
                            selectedBandwidth
                    {
                        selected =
                            version

                        selectedBandwidth =
                            bandwidth
                    }
                }

                if
                    let selected =
                        selected
                {
                    videoURL =
                        selected["url"]
                            as? String

                    videoWidth =
                        intValue(
                            selected["width"]
                        ) ?? 0

                    videoHeight =
                        intValue(
                            selected["height"]
                        ) ?? 0
                }
            }

            let photoMusic =
                photoMusicInfo(
                    from:
                        media
                )

            let fallbackImage =
                photoMusic == nil
                    ? nil
                    : photoMusicFallbackImageURL(
                        from:
                            media,
                        excluding:
                            imageURL
                    )

            posts.append(
                MagnistraRealPost(
                    mediaID:
                        mediaID,
                    userID:
                        parsedUserID,
                    username:
                        parsedUsername,
                    fullName:
                        fullName,
                    caption:
                        captionText,
                    commentCount:
                        commentCount,
                    previewComments:
                        previewComments,
                    likes:
                        intValue(
                            media["like_count"]
                        ) ??
                        intValue(
                            media["play_count"]
                        ) ??
                        0,
                    location:
                        locationText,
                    takenAt:
                        doubleValue(
                            media["taken_at"]
                        ),
                    imagePath:
                        imagePath,
                    imageURL:
                        imageURL,
                    imageCacheKey:
                        imageCacheKey,
                    avatarPath:
                        avatarPath,
                    avatarURL:
                        avatarURL,
                    avatarCacheKey:
                        avatarCacheKey,
                    musicTitle:
                        photoMusic?
                            .title,
                    musicArtist:
                        photoMusic?
                            .artist,
                    musicAudioURL:
                        photoMusic?
                            .audioURL,
                    musicStartTimeMs:
                        photoMusic?
                            .startTimeMs ??
                        0,
                    photoMusicImageURLFallback:
                        fallbackImage,
                    videoURL:
                        videoURL,
                    videoWidth:
                        videoWidth,
                    videoHeight:
                        videoHeight
                )
            )
        }

        let next =
            reelsNextMaxID(
                from:
                    root,
                excluding:
                    maxID
            )

        posts =
            posts.filter {
                $0.videoURL != nil
            }
        let totalMs = Int((Date().timeIntervalSince1970 - pageStart) * 1000.0)
        NSLog("MAGNISTRA_REELS_TIMING http_ms=%ld parse_ms=%ld rows=%ld playable=%ld",
              networkMs, max(0, totalMs - networkMs), mediaRows.count, posts.count)

        return MagnistraReelsPage(
            posts:
                posts,
            nextMaxID:
                next
        )
    }
}
