// Overview: Saved media and REST profile feeds.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func savedRichPost(media: [String: Any]) -> MagnistraRealPost? {
        var normalized = timelineDisplayMedia(from: media)
        if normalized["carousel_media"] == nil,
           let sidecar = media["edge_sidecar_to_children"] as? [String: Any],
           let edges = sidecar["edges"] as? [[String: Any]] {
            normalized["carousel_media"] = edges.compactMap { $0["node"] as? [String: Any] }
        }

        if normalized["image_versions2"] == nil {
            if let display = normalized["display_url"] as? String,
               !display.isEmpty {
                normalized["image_versions2"] = [
                    "candidates": [["url": display]]
                ]
            } else if let resources = normalized["display_resources"] as? [[String: Any]] {
                let candidates = resources.compactMap { entry -> [String: Any]? in
                    guard let url = entry["src"] as? String, !url.isEmpty else { return nil }
                    return ["url": url, "width": entry["config_width"] ?? 0,
                            "height": entry["config_height"] ?? 0]
                }
                if !candidates.isEmpty {
                    normalized["image_versions2"] = ["candidates": candidates]
                }
            }
        }
        guard let base = activityReferencePost(media: normalized,
            actorUser: nil, actorAvatarURL: nil) else { return nil }
        let music = photoMusicInfo(from: normalized)

        let quality = MagnistraMediaPreferences.photoQuality
        let preferred = preferredFeedImageURL(from: normalized, quality: quality)
            ?? activityImageURL(normalized) ?? base.imageURL
        let previewKey = "explore:" + quality.cacheToken + ":" + base.mediaID
        let previewPath = cachedPublicImagePathIfPresent(
            kind: .post, stableKey: previewKey) ?? ""
        let fallback = music == nil ? nil : photoMusicFallbackImageURL(
            from: normalized, excluding: preferred)
        var detailed = MagnistraRealPost(
            mediaID: base.mediaID, userID: base.userID,
            username: base.username, fullName: base.fullName,
            caption: base.caption, commentCount: base.commentCount,
            previewComments: base.previewComments, likes: base.likes,
            location: base.location, takenAt: base.takenAt,
            imagePath: previewPath, imageURL: preferred,
            imageCacheKey: previewKey, avatarPath: base.avatarPath,
            avatarURL: base.avatarURL, avatarCacheKey: base.avatarCacheKey,
            musicTitle: music?.title, musicArtist: music?.artist,
            musicAudioURL: music?.audioURL,
            musicStartTimeMs: music?.startTimeMs ?? 0,
            photoMusicImageURLFallback: fallback,
            videoURL: base.videoURL, videoWidth: base.videoWidth,
            videoHeight: base.videoHeight)
        detailed.isVideo = base.isVideo
        detailed.shortcode = base.shortcode
        detailed.carouselMedia = carouselMediaItems(
            from: normalized, quality: MagnistraMediaPreferences.photoQuality)

        if detailed.carouselMedia.count < 2,
           let children = normalized["carousel_media"] as? [[String: Any]] {
            var extracted: [MagnistraCarouselMedia] = []
            for (index, child) in children.prefix(20).enumerated() {
                let img = preferredFeedImageURL(from: child,
                    quality: MagnistraMediaPreferences.photoQuality)
                    ?? (child["display_url"] as? String)
                    ?? (child["thumbnail_src"] as? String)
                    ?? ((child["display_resources"] as? [[String: Any]])?.last?["src"] as? String)
                guard let url = img, !url.isEmpty else { continue }
                let id = stringValue(child["pk"]) ?? stringValue(child["id"])
                    ?? (base.mediaID + ":" + String(index))
                let variants = child["video_versions"] as? [[String: Any]] ?? []
                let video = variants.compactMap { $0["url"] as? String }.first
                let width = intValue(variants.first?["width"]) ?? 0
                let height = intValue(variants.first?["height"]) ?? 0
                extracted.append(MagnistraCarouselMedia(
                    mediaID: id, imageURL: url, videoURL: video,
                    videoWidth: width, videoHeight: height))
            }
            if extracted.count > 1 { detailed.carouselMedia = extracted }
        }
        return detailed
    }

    static func savedMediaPage(
        root: [String: Any]
    ) throws -> MagnistraProfileMediaPage {
        guard
            let data =
                root[
                    "data"
                ] as? [String: Any],
            let viewer =
                data[
                    "viewer"
                ] as? [String: Any],
            let saved =
                viewer[
                    "saved_media"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraProfileSaved",
                code:
                    9490,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not return Saved posts."
                ]
            )
        }

        let edges =
            saved[
                "edges"
            ] as? [[String: Any]] ??
            []

        var posts:
            [MagnistraRealPost] = []

        for edge in edges {
            guard
                let media =
                    edge[
                        "node"
                    ] as? [String: Any],
                let post = savedRichPost(media: media)
            else {
                continue
            }

            let user =
                media[
                    "user"
                ] as? [String: Any] ??
                [:]

            rememberPostActionMetadata(
                mediaID:
                    post.mediaID,
                userID:
                    post.userID,
                media:
                    media,
                user:
                    user,
                context:
                    edge
            )

            setCachedPostInteractionState(
                mediaID: post.mediaID,
                liked: nil,
                saved: true,
                likeCount: nil
            )
            posts.append(
                post
            )
        }

        let pageInfo =
            saved[
                "page_info"
            ] as? [String: Any]

        let hasNext =
            boolValue(
                pageInfo?[
                    "has_next_page"
                ]
            ) ??
            false

        let endCursor =
            stringValue(
                pageInfo?[
                    "end_cursor"
                ]
            )

        return
            MagnistraProfileMediaPage(
                posts:
                    posts,
                nextMaxID:
                    (
                        hasNext &&
                        endCursor?.isEmpty != true
                    )
                        ? endCursor
                        : nil
            )
    }

    static func profileRESTFeedRoot(
        urls: [String]
    ) throws -> [String: Any] {
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
                    "MagnistraProfileREST",
                code:
                    9520,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram CA bundle unavailable."
                ]
            )
        }

        var lastError:
            NSError? =
                nil

        exploreSearchLock.lock()

        defer {
            exploreSearchLock.unlock()
        }

        for url in urls {
            let code:
                Int32 =
                    caPath.withCString {
                        ca in

                        session.userAgent
                            .withCString {
                                ua in

                                session.language
                                    .withCString {
                                        lang in

                                        session.cookieHeader
                                            .withCString {
                                                cookies in

                                                session.csrfToken
                                                    .withCString {
                                                        csrf in

                                                        url.withCString {
                                                            rawURL in

                                                            Int32(
                                                                magnistra_explore_rest_get(
                                                                    ca,
                                                                    ua,
                                                                    lang,
                                                                    cookies,
                                                                    csrf,
                                                                    rawURL
                                                                )
                                                            )
                                                        }
                                                    }
                                            }
                                    }
                            }
                    }

            let status =
                magnistra_explore_search_http_status()

            guard
                code == 0,
                status >= 200,
                status < 300,
                magnistra_explore_search_tls_verify_result() ==
                    0
            else {
                lastError =
                    NSError(
                        domain:
                            "MagnistraProfileREST",
                        code:
                            Int(status),
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Instagram feed request failed (HTTP \(status))."
                        ]
                    )
                continue
            }

            let length =
                Int(
                    magnistra_explore_search_body_length()
                )

            guard
                length > 0,
                let pointer =
                    magnistra_explore_search_body()
            else {
                lastError =
                    NSError(
                        domain:
                            "MagnistraProfileREST",
                        code:
                            9521,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Instagram feed returned an empty response."
                        ]
                    )
                continue
            }

            let data =
                Data(
                    bytes:
                        pointer,
                    count:
                        length
                )

            do {
                if
                    let root =
                        try MagnistraJSONKit
                            .jsonObject(
                                with:
                                    data,
                                options:
                                    []
                            ) as? [String: Any]
                {
                    if
                        let statusText =
                            root[
                                "status"
                            ] as? String,
                        statusText ==
                            "fail"
                    {
                        lastError =
                            NSError(
                                domain:
                                    "MagnistraProfileREST",
                                code:
                                    9522,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        (
                                            root[
                                                "message"
                                            ] as? String
                                        ) ??
                                        "Instagram feed returned status=fail."
                                ]
                            )
                        continue
                    }

                    return root
                }
            } catch {
                lastError =
                    error as NSError
            }
        }

        throw
            lastError ??
            NSError(
                domain:
                    "MagnistraProfileREST",
                code:
                    9523,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram feed response was not recognized."
                ]
            )
    }

    static func profileRESTCursorURL(
        _ base: String,
        maxID: String?
    ) -> String {
        guard
            let cursor =
                maxID,
            !cursor.isEmpty
        else {
            return base
        }

        let encoded =
            cursor.addingPercentEncoding(
                withAllowedCharacters:
                    .urlQueryAllowed
            ) ??
            cursor

        return
            base +
            (
                base.contains("?")
                    ? "&max_id="
                    : "?max_id="
            ) +
            encoded
    }

    static func profileRESTMediaPage(
        root: [String: Any]
    ) -> MagnistraProfileMediaPage {
        let rows =
            root[
                "items"
            ] as? [[String: Any]] ??
            []

        var posts:
            [MagnistraRealPost] = []

        var seen =
            Set<String>()

        for row in rows {
            let media =
                row[
                    "media"
                ] as? [String: Any] ??
                row

            var post =
                activityReferencePost(
                    media:
                        media,
                    actorUser:
                        nil,
                    actorAvatarURL:
                        nil
                )

            if post == nil {
                let shortcode =
                    stringValue(
                        media[
                            "code"
                        ]
                    ) ??
                    stringValue(
                        media[
                            "shortcode"
                        ]
                    )

                if
                    let shortcode =
                        shortcode,
                    !shortcode.isEmpty
                {
                    post =
                        try?
                            loadActivityReferencedPost(
                                shortcode:
                                    shortcode
                            )
                }
            }

            guard
                let ready =
                    post,
                !ready.mediaID.isEmpty,
                !seen.contains(
                    ready.mediaID
                )
            else {
                continue
            }

            seen.insert(
                ready.mediaID
            )

            let user =
                media[
                    "user"
                ] as? [String: Any] ??
                [:]

            rememberPostActionMetadata(
                mediaID:
                    ready.mediaID,
                userID:
                    ready.userID,
                media:
                    media,
                user:
                    user,
                context:
                    row
            )

            posts.append(
                ready
            )
        }

        let next =
            stringValue(
                root[
                    "next_max_id"
                ]
            )

        let more =
            boolValue(
                root[
                    "more_available"
                ]
            ) ??
            (
                next?.isEmpty ==
                false
            )

        return
            MagnistraProfileMediaPage(
                posts:
                    posts,
                nextMaxID:
                    (
                        more &&
                        next?.isEmpty !=
                            true
                    )
                        ? next
                        : nil
            )
    }

    static func loadProfileRESTPage(
        kind: String,
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {
        let bases:
            [String]

        if kind == "saved" {
            bases = [
                "https://www.instagram.com/api/v1/feed/saved/posts/?count=50",
                "https://i.instagram.com/api/v1/feed/saved/?count=50"
            ]
        } else {
            bases = [
                "https://www.instagram.com/api/v1/feed/liked/?count=50",
                "https://i.instagram.com/api/v1/feed/liked/?count=50"
            ]
        }

        let urls =
            bases.map {
                profileRESTCursorURL(
                    $0,
                    maxID:
                        maxID
                )
            }

        let root =
            try profileRESTFeedRoot(
                urls:
                    urls
            )

        return
            profileRESTMediaPage(
                root:
                    root
            )
    }

    static func loadProfileSavedPage(
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {
        return
            try loadProfileSavedGraphQLPage(
                maxID:
                    maxID
            )
    }

    static func loadProfileLikedPage(
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {
        return
            try loadProfileLikedWBloksPage(
                maxID:
                    maxID
            )
    }

    static func loadProfileSavedGraphQLPage(
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {
        let variables:
            [String: Any]

        let docID:
            String

        let friendlyName:
            String

        if
            let cursor =
                maxID,
            !cursor.isEmpty
        {
            variables = [
                "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider":
                    false,
                "after":
                    cursor,
                "first":
                    15
            ]

            docID =
                "27995164846829507"

            friendlyName =
                "PolarisProfileSavedPostsTabContentQuery_connection"
        } else {
            variables = [
                "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider":
                    false,
                "first": 15
            ]

            docID =
                "29186072607645952"

            friendlyName =
                "PolarisProfileSavedPostsTabContentQuery"
        }

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    docID,
                friendlyName:
                    friendlyName
            )

        let firstPage = try savedMediaPage(root: root)
        if maxID == nil && firstPage.posts.count < 15 && firstPage.nextMaxID == nil {

            var best = firstPage
            let expandedVariables: [String: Any] = [
                "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider": false,
                "first": 15
            ]
            if let expandedRoot = try? exploreSearchGraphQLRoot(
                    variables: expandedVariables,
                    docID: "27995164846829507",
                    friendlyName: "PolarisProfileSavedPostsTabContentQuery_connection"),
               let expanded = try? savedMediaPage(root: expandedRoot),
               expanded.posts.count > best.posts.count {
                best = expanded
            }

            if best.posts.count < 15,
               let rest = try? loadProfileRESTPage(kind: "saved", maxID: nil) {
                var combined = rest.posts
                var cursor = rest.nextMaxID
                if combined.count < 15, let next = cursor, !next.isEmpty,
                   let restNext = try? loadProfileRESTPage(kind: "saved", maxID: next) {
                    var ids = Set(combined.map { $0.mediaID })
                    for post in restNext.posts where !ids.contains(post.mediaID) {
                        ids.insert(post.mediaID)
                        combined.append(post)
                    }
                    cursor = restNext.nextMaxID
                }
                if combined.count > best.posts.count {
                    best = MagnistraProfileMediaPage(posts: combined, nextMaxID: cursor)
                }
            }
            print("MAGNISTRA_SAVED_FIRST_PAGE_COUNT=\(best.posts.count)")
            return best
        }
        return firstPage
    }
}
