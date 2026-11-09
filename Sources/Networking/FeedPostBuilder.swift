import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {
    // Converts one Home feed row to a post; network request and pagination remain in Feed.swift.
    static func makeFeedPost(from row: [String: Any], photoQuality: MagnistraPhotoQuality) -> MagnistraRealPost? {
            let media =
                timelineDisplayMedia(
                    from:
                        row
                )

            guard
                let user =
                    media["user"]
                        as? [String: Any],
                let username =
                    user["username"]
                        as? String,
                !username.isEmpty,
                let imageURL =
                    preferredFeedImageURL(
                        from:
                            media,
                        quality:
                            photoQuality
                    )
            else {
                return nil
            }

            let mediaID =
                stringValue(
                    media["pk"]
                ) ??
                stringValue(
                    media["id"]
                ) ??
                imageURL

            let imageCacheKey =
                "post:" +
                photoQuality
                    .cacheToken +
                ":" +
                mediaID

            let imagePath =
                cachedPublicImagePathIfPresent(
                    kind:
                        .post,
                    stableKey:
                        imageCacheKey
                ) ?? ""

            let userID =
                stringValue(
                    user["pk"]
                ) ??
                stringValue(
                    user["id"]
                ) ??
                (
                    "username:" +
                    username
                )

            let fullName =
                (
                    user["full_name"]
                        as? String
                ) ?? ""

            let avatarURL =
                (
                    user["profile_pic_url"]
                        as? String
                )

            let avatarCacheKey =
                "avatar:" +
                userID

            let avatarPath =
                cachedPublicImagePathIfPresent(
                    kind:
                        .avatar,
                    stableKey:
                        avatarCacheKey
                )

            var captionText = ""

            if
                let caption =
                    media["caption"]
                        as? [String: Any],
                let value =
                    caption["text"]
                        as? String
            {
                captionText = value
            }

            var locationText = ""

            if
                let location =
                    media["location"]
                        as? [String: Any],
                let name =
                    location["name"]
                        as? String
            {
                locationText = name
            }

            let previewObjects =
                (
                    media["preview_comments"]
                        as? [[String: Any]]
                ) ?? []

            var previewComments:
                [MagnistraComment] = []

            for object in previewObjects {
                if let parsed =
                    parseComment(
                        object
                    )
                {
                    previewComments.append(
                        parsed
                    )

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

            var videoURL:
                String? = nil

            var videoWidth = 0
            var videoHeight = 0

            if
                intValue(
                    media["media_type"]
                ) == 2,
                let versions =
                    media["video_versions"]
                        as? [[String: Any]],
                !versions.isEmpty
            {
                var selected:
                    [String: Any]? = nil

                var selectedBandwidth =
                    Int.max

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
                        ) ?? Int.max

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
                    from:
                        media
                )

            let musicTitle =
                photoMusic?
                    .title

            let musicArtist =
                photoMusic?
                    .artist

            let musicAudioURL =
                photoMusic?
                    .audioURL

            let musicStartTimeMs =
                photoMusic?
                    .startTimeMs ??
                0

            let photoMusicImageURLFallback =
                photoMusic == nil
                    ? nil
                    : photoMusicFallbackImageURL(
                        from: media,
                        excluding: imageURL
                    )

            let rawMediaType =
                intValue(
                    media["media_type"]
                ) ?? 0

            let hasMusicContainer =
                media["music_metadata"] != nil ||
                media["clips_metadata"] != nil

            if
                rawMediaType != 1,
                videoURL == nil,
                hasMusicContainer
            {
                return nil
            }

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
                    commentCount:
                        commentCount,
                    previewComments:
                        previewComments,
                    likes:
                        intValue(
                            media["like_count"]
                        ) ?? 0,
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
                        musicTitle,
                    musicArtist:
                        musicArtist,
                    musicAudioURL:
                        musicAudioURL,
                    musicStartTimeMs:
                        musicStartTimeMs,
                    photoMusicImageURLFallback:
                        photoMusicImageURLFallback,
                    videoURL:
                        videoURL,
                    videoWidth:
                        videoWidth,
                    videoHeight:
                        videoHeight
                )
            parsedPost.carouselMedia = carouselMediaItems(from: media, quality: photoQuality)
            return parsedPost
            }
}
