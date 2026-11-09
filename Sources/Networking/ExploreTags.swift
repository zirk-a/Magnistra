// Overview: Explore: tag (hashtag) page requests.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func loadExploreTagExplorePage(
        tag: String,
        searchSessionID: String,
        maxID: String?
    ) throws -> MagnistraExplorePage {
        var variables: [String: Any] = [
            "query": tag,
            "search_session_id": searchSessionID,
            "serp_session_id": searchSessionID
        ]

        let paginating =
            maxID != nil &&
            maxID?.isEmpty == false

        if let cursor = maxID,
           !cursor.isEmpty {
            variables["after"] = cursor
            variables["first"] = 15
        } else {

            variables["first"] = 15
        }

        let root =
            try exploreSearchGraphQLRoot(
                variables: variables,
                docID:
                    paginating
                        ? "28656899673911396"
                        : "37324993597144881",
                friendlyName:
                    paginating
                        ? "PolarisKeywordSearchExplorePageRelayPaginationQuery"
                        : "PolarisKeywordSearchExplorePageRelayQuery"
            )

        guard
            let data = root["data"] as? [String: Any],
            let graph =
                data[
                    "xdt_fbsearch__top_serp_graphql"
                ] as? [String: Any]
        else {
            throw NSError(
                domain: "MagnistraExploreTagParity",
                code: 6830,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram tag payload was not recognized."
                ]
            )
        }

        let edges =
            graph["edges"]
                as? [[String: Any]] ??
            []

        var mediaRows: [[String: Any]] = []
        var seenRaw = Set<String>()

        for edge in edges {
            guard
                let node =
                    edge["node"] as? [String: Any],
                let items =
                    node["items"] as? [[String: Any]]
            else {
                continue
            }

            for item in items {
                let rawID =
                    stringValue(item["pk"]) ??
                    stringValue(item["id"]) ??
                    (item["code"] as? String) ??
                    ""

                if !rawID.isEmpty {
                    if seenRaw.contains(rawID) {
                        continue
                    }
                    seenRaw.insert(rawID)
                }

                mediaRows.append(item)
            }
        }

        let photoQuality =
            MagnistraMediaPreferences.photoQuality

        var posts: [MagnistraRealPost] = []

        for row in mediaRows {
            let media =
                timelineDisplayMedia(
                    from: row
                )

            guard
                let imageURL =
                    preferredFeedImageURL(
                        from: media,
                        quality: photoQuality
                    )
            else {
                continue
            }

            let user =
                (
                    media["user"]
                        as? [String: Any]
                ) ?? [:]

            let username =
                (
                    user["username"]
                        as? String
                ) ?? ""

            if username.isEmpty {
                continue
            }

            let userID =
                stringValue(user["pk"]) ??
                stringValue(user["id"]) ??
                ("username:" + username)

            let mediaID =
                stringValue(media["pk"]) ??
                stringValue(media["id"]) ??
                (media["code"] as? String) ??
                imageURL

            let fullName =
                (
                    user["full_name"]
                        as? String
                ) ?? ""

            var captionText = ""
            if
                let caption =
                    media["caption"] as? [String: Any],
                let text =
                    caption["text"] as? String
            {
                captionText = text
            }

            var locationText = ""
            if
                let location =
                    media["location"] as? [String: Any],
                let name =
                    location["name"] as? String
            {
                locationText = name
            }

            let previewObjects =
                (
                    media["preview_comments"]
                        as? [[String: Any]]
                ) ?? []

            var previewComments: [MagnistraComment] = []

            for object in previewObjects {
                if let parsed = parseComment(object) {
                    previewComments.append(parsed)
                    if previewComments.count >= 2 {
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
                "tag-explore:" +
                photoQuality.cacheToken +
                ":" +
                mediaID

            let imagePath =
                cachedPublicImagePathIfPresent(
                    kind: .post,
                    stableKey: imageCacheKey
                ) ?? ""

            let avatarURL =
                user["profile_pic_url"]
                    as? String

            let avatarCacheKey =
                "tag-explore-avatar:" +
                userID

            let avatarPath =
                cachedPublicImagePathIfPresent(
                    kind: .avatar,
                    stableKey: avatarCacheKey
                )

            var videoURL: String? = nil
            var videoWidth = 0
            var videoHeight = 0

            if
                let versions =
                    media["video_versions"]
                        as? [[String: Any]],
                !versions.isEmpty
            {
                var selected: [String: Any]? = nil
                var selectedBandwidth = Int.max

                for version in versions {
                    guard
                        let candidateURL =
                            version["url"] as? String,
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
                        bandwidth < selectedBandwidth
                    {
                        selected = version
                        selectedBandwidth = bandwidth
                    }
                }

                if let selected = selected {
                    videoURL =
                        selected["url"] as? String
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
                    from: media
                )

            let musicTitle =
                photoMusic?.title
            let musicArtist =
                photoMusic?.artist
            let musicAudioURL =
                photoMusic?.audioURL
            let musicStartTimeMs =
                photoMusic?.startTimeMs ??
                0

            let photoMusicImageURLFallback =
                photoMusic == nil
                    ? nil
                    : photoMusicFallbackImageURL(
                        from: media,
                        excluding: imageURL
                    )

            rememberPostActionMetadata(
                mediaID:
                    mediaID,
                userID:
                    userID,
                media:
                    media,
                user:
                    user,
                context:
                    row
            )

            var parsedPost = MagnistraRealPost(
                    mediaID: mediaID,
                    userID: userID,
                    username: username,
                    fullName: fullName,
                    caption: captionText,
                    commentCount: commentCount,
                    previewComments: previewComments,
                    likes:
                        intValue(
                            media["like_count"]
                        ) ?? 0,
                    location: locationText,
                    takenAt:
                        doubleValue(
                            media["taken_at"]
                        ),
                    imagePath: imagePath,
                    imageURL: imageURL,
                    imageCacheKey: imageCacheKey,
                    avatarPath: avatarPath,
                    avatarURL: avatarURL,
                    avatarCacheKey: avatarCacheKey,
                    musicTitle: musicTitle,
                    musicArtist: musicArtist,
                    musicAudioURL: musicAudioURL,
                    musicStartTimeMs: musicStartTimeMs,
                    photoMusicImageURLFallback:
                        photoMusicImageURLFallback,
                    videoURL: videoURL,
                    videoWidth: videoWidth,
                    videoHeight: videoHeight
                )
            parsedPost.carouselMedia = carouselMediaItems(from: media, quality: photoQuality)
            posts.append(parsedPost)
        }

        let pageInfo =
            graph["page_info"]
                as? [String: Any]

        var next =
            stringValue(
                pageInfo?["end_cursor"]
            )

        let hasNext =
            boolValue(
                pageInfo?["has_next_page"]
            ) ??
            false

        if
            !hasNext ||
            next?.isEmpty == true ||
            next == maxID
        {
            next = nil
        }

        return
            MagnistraExplorePage(
                posts: posts,
                nextMaxID: next
            )
    }
}
