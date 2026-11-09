// Overview: Explore: requests for Explore grid pages.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func loadExploreTwelveInitial(onEarlyPosts: (([MagnistraRealPost]) -> Void)? = nil) throws -> MagnistraExploreTwelveBatch {
        let networkStageStartedAt = MagnistraFeedTiming.now()
        defer { MagnistraFeedTiming.mark("EXPLORE", "FIRST_BATCH_TOTAL", networkStageStartedAt) }

        let first = try loadExplorePage(maxID: nil, onEarlyPosts: onEarlyPosts)
        var all = first.posts
        var cursor = first.nextMaxID

        if all.count < 12, let after = cursor, !after.isEmpty {
            do {
                let next = try loadExplorePage(maxID: after)
                var seen = Set<String>()
                for post in all {
                    seen.insert(post.mediaID)
                }
                for post in next.posts {
                    if seen.insert(post.mediaID).inserted {
                        all.append(post)
                    }
                }
                cursor = next.nextMaxID
            } catch {

                cursor = nil
            }
        }

        let visible = Array(all.prefix(12))
        let overflow = Array(all.dropFirst(12))
        let presentedCursor = overflow.isEmpty
            ? cursor
            : "__magnistra_explore_twelve_buffer__"
        return MagnistraExploreTwelveBatch(
            page: MagnistraExplorePage(posts: visible, nextMaxID: presentedCursor),
            deferredPosts: overflow,
            deferredNextMaxID: cursor
        )
    }

    static func loadExplorePage(
        maxID: String?
    , onEarlyPosts: (([MagnistraRealPost]) -> Void)? = nil) throws -> MagnistraExplorePage
    {
        MagnistraExploreCounters.begin()
        defer { MagnistraExploreCounters.finish() }

        let networkStageStartedAt = MagnistraFeedTiming.now()
        defer { MagnistraFeedTiming.mark("EXPLORE", "PAGE_TOTAL", networkStageStartedAt) }

        exploreLock.lock()

        defer {
            exploreLock.unlock()
        }

        let root =
            try exploreRoot(
                maxID:
                    maxID
            )
        let postBuildStartedAt = MagnistraFeedTiming.now()
        defer { MagnistraFeedTiming.mark("EXPLORE", "POST_BUILD", postBuildStartedAt) }

        let exploreMediaWalkStartedAt = MagnistraFeedTiming.now()
        var mediaRows:
            [[String: Any]] = []

        var seen =
            Set<String>()

        if
            let sectional =
                root["sectional_items"]
                    as? [Any]
        {
            if magnistraCollectSectionalMedia(
                sectional, rows: &mediaRows, seen: &seen
            ) {
                MagnistraFeedTiming.mark("EXPLORE", "MEDIA_DIRECT_USED", MagnistraFeedTiming.now())
            } else {
                collectExploreMedia(sectional, rows: &mediaRows, seen: &seen)
                MagnistraFeedTiming.mark("EXPLORE", "MEDIA_FALLBACK_USED", MagnistraFeedTiming.now())
            }
        } else {
            collectExploreMedia(
                root,
                rows:
                    &mediaRows,
                seen:
                    &seen
            )
        }

        let username = ""
        let userID = ""

        MagnistraFeedTiming.mark("EXPLORE", "MEDIA_WALK", exploreMediaWalkStartedAt)

        let photoQuality =
            MagnistraMediaPreferences
                .photoQuality

        var posts:
            [MagnistraRealPost] = []

        for row in mediaRows {
            let exploreMediaRowStartedAt = MagnistraFeedTiming.now()
            defer { MagnistraFeedTiming.mark("EXPLORE", "MEDIA_ROW", exploreMediaRowStartedAt) }

            let media =
                timelineDisplayMedia(
                    from:
                        row
                )

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

            rememberPostActionMetadata(
                mediaID:
                    mediaID,
                userID:
                    parsedUserID,
                media:
                    media,
                user:
                    user,
                context:
                    row
            )

            var parsedPost = MagnistraRealPost(
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
            parsedPost.carouselMedia = carouselMediaItems(from: media, quality: photoQuality)
            posts.append(parsedPost)
            if posts.count == 6 {
                onEarlyPosts?(posts)
            }

        }

        let next =
            exploreNextMaxID(
                root,
                excluding:
                    maxID
            )

        return MagnistraExplorePage(
            posts:
                posts,
            nextMaxID:
                next
        )
    }
}
