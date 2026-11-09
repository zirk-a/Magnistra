// Overview: Parsing of Activity (notifications) responses.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func activityImageData(
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

    static func activityString(
        _ value: Any?
    ) -> String? {
        if let value = value as? String {
            return value
        }

        if let value = value as? NSNumber {
            return value.stringValue
        }

        return nil
    }

    static func activityImageURL(
        _ dictionary:
            [String: Any]
    ) -> String? {
        if
            let direct =
                dictionary["profile_pic_url"]
                    as? String,
            !direct.isEmpty
        {
            return direct
        }

        if
            let direct =
                dictionary["profile_image"]
                    as? String,
            !direct.isEmpty
        {
            return direct
        }

        if
            let direct =
                dictionary["media_image"]
                    as? String,
            !direct.isEmpty
        {
            return direct
        }

        if
            let direct =
                dictionary["thumbnail_url"]
                    as? String,
            !direct.isEmpty
        {
            return direct
        }

        if
            let imageVersions =
                dictionary["image_versions2"]
                    as? [String: Any],
            let candidates =
                imageVersions["candidates"]
                    as? [[String: Any]]
        {
            for candidate in candidates {
                if
                    let url =
                        candidate["url"]
                            as? String,
                    !url.isEmpty
                {
                    return url
                }
            }
        }

        return nil
    }

    static func activityFindUser(
        _ value: Any
    ) -> [String: Any]? {
        if
            let dictionary =
                value as?
                    [String: Any]
        {
            if
                let username =
                    dictionary["username"]
                        as? String,
                !username.isEmpty
            {
                return dictionary
            }

            for child in dictionary.values {
                if
                    let found =
                        activityFindUser(
                            child
                        )
                {
                    return found
                }
            }
        }
        else if
            let array =
                value as?
                    [Any]
        {
            for child in array {
                if
                    let found =
                        activityFindUser(
                            child
                        )
                {
                    return found
                }
            }
        }

        return nil
    }

    static func activityFindMedia(
        _ value: Any
    ) -> [String: Any]? {
        if
            let dictionary =
                value as?
                    [String: Any]
        {
            let hasMediaID =
                dictionary["media_id"] != nil ||
                dictionary["media_pk"] != nil ||
                dictionary["image_versions2"] != nil ||
                dictionary["media_type"] != nil

            if hasMediaID {
                return dictionary
            }

            for child in dictionary.values {
                if
                    let found =
                        activityFindMedia(
                            child
                        )
                {
                    return found
                }
            }
        }
        else if
            let array =
                value as?
                    [Any]
        {
            for child in array {
                if
                    let found =
                        activityFindMedia(
                            child
                        )
                {
                    return found
                }
            }
        }

        return nil
    }

    static func activityCleanRichText(
        _ raw:
            String
    ) -> String {
        var result =
            ""

        var cursor =
            raw.startIndex

        while cursor < raw.endIndex {
            if
                raw[cursor] == "{",
                let pipe =
                    raw[cursor...]
                        .firstIndex(
                            of:
                                "|"
                        ),
                let close =
                    raw[pipe...]
                        .firstIndex(
                            of:
                                "}"
                        ),
                pipe > cursor
            {
                let labelStart =
                    raw.index(
                        after:
                            cursor
                    )

                result +=
                    String(
                        raw[
                            labelStart..<pipe
                        ]
                    )

                cursor =
                    raw.index(
                        after:
                            close
                    )

                continue
            }

            result.append(
                raw[cursor]
            )

            cursor =
                raw.index(
                    after:
                        cursor
                )
        }

        return result
    }

    static func activityRichIdentity(
        _ raw:
            String?
    ) -> [String: String]? {
        guard
            let raw = raw,
            let open =
                raw.firstIndex(
                    of:
                        "{"
                ),
            let pipe =
                raw[open...]
                    .firstIndex(
                        of:
                            "|"
                    ),
            let close =
                raw[pipe...]
                    .firstIndex(
                        of:
                            "}"
                    ),
            pipe > open
        else {
            return nil
        }

        let usernameStart =
            raw.index(
                after:
                    open
            )

        let username =
            String(
                raw[
                    usernameStart..<pipe
                ]
            )

        let targetStart =
            raw.index(
                after:
                    pipe
            )

        let target =
            String(
                raw[
                    targetStart..<close
                ]
            )

        var result:
            [String: String] = [:]

        if !username.isEmpty {
            result["username"] =
                username
        }

        if
            let marker =
                target.range(
                    of:
                        "user?id="
                )
        {
            var userID =
                String(
                    target[
                        marker.upperBound...
                    ]
                )

            if
                let separator =
                    userID.firstIndex(
                        of:
                            "&"
                    )
            {
                userID =
                    String(
                        userID[
                            ..<separator
                        ]
                    )
            }

            if !userID.isEmpty {
                result["userID"] =
                    userID
            }
        }

        return
            result.isEmpty
            ? nil
            : result
    }

    static func activityNumberInt(
        _ value:
            Any?
    ) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }

        if
            let string = value as? String,
            let number = Int(string)
        {
            return number
        }

        return 0
    }

    static func activityNumberDouble(
        _ value:
            Any?
    ) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if
            let string = value as? String,
            let number = Double(string)
        {
            return number
        }

        return 0.0
    }

    static func activityCaptionText(
        _ media:
            [String: Any]
    ) -> String {
        if
            let caption =
                media["caption"]
                    as? [String: Any],
            let text =
                caption["text"]
                    as? String
        {
            return text
        }

        if let text =
            media["caption"]
                as? String
        {
            return text
        }

        return ""
    }

    static func activityVideoInfo(
        _ media:
            [String: Any]
    ) -> (
        url: String?,
        width: Int,
        height: Int
    ) {
        if
            let versions =
                media["video_versions"]
                    as? [[String: Any]]
        {
            for version in versions {
                guard
                    let url =
                        version["url"]
                            as? String,
                    !url.isEmpty
                else {
                    continue
                }

                return (
                    url,
                    activityNumberInt(
                        version["width"]
                    ),
                    activityNumberInt(
                        version["height"]
                    )
                )
            }
        }

        if
            let url =
                media["video_url"]
                    as? String,
            !url.isEmpty
        {
            return (
                url,
                activityNumberInt(
                    media["original_width"]
                ),
                activityNumberInt(
                    media["original_height"]
                )
            )
        }

        return (
            nil,
            0,
            0
        )
    }

    static func activityReferencePost(
        media:
            [String: Any]?,
        actorUser:
            [String: Any]?,
        actorAvatarURL:
            String?
    ) -> MagnistraRealPost? {
        guard
            let media = media
        else {
            return nil
        }

        guard
            let mediaID =
                activityString(
                    media["pk"]
                ) ??
                activityString(
                    media["id"]
                ) ??
                activityString(
                    media["media_id"]
                ),
            !mediaID.isEmpty
        else {
            return nil
        }

        let mediaUser =
            (
                media["user"]
                    as? [String: Any]
            ) ??
            actorUser

        let userID =
            activityString(
                mediaUser?["pk"]
            ) ??
            activityString(
                mediaUser?["id"]
            ) ??
            ""

        let username =
            (
                mediaUser?["username"]
                    as? String
            ) ?? ""

        let fullName =
            (
                mediaUser?["full_name"]
                    as? String
            ) ?? ""

        let imageURL =
            activityImageURL(
                media
            ) ?? ""

        let avatarURL =
            mediaUser.flatMap {
                activityImageURL(
                    $0
                )
            } ??
            actorAvatarURL

        let video =
            activityVideoInfo(
                media
            )

        let location =
            (
                (
                    media["location"]
                        as? [String: Any]
                )?["name"]
                    as? String
            ) ?? ""

        var post = MagnistraRealPost(
            mediaID:
                mediaID,
            userID:
                userID,
            username:
                username,
            fullName:
                fullName,
            caption:
                activityCaptionText(
                    media
                ),
            commentCount:
                activityNumberInt(
                    media["comment_count"]
                ),
            previewComments:
                [],
            likes:
                activityNumberInt(
                    media["like_count"]
                ),
            location:
                location,
            takenAt:
                activityNumberDouble(
                    media["taken_at"]
                ),
            imagePath:
                "",
            imageURL:
                imageURL,
            imageCacheKey:
                "activity-reference:" +
                mediaID,
            avatarPath:
                nil,
            avatarURL:
                avatarURL,
            avatarCacheKey:
                "activity-reference-avatar:" +
                userID,
            musicTitle:
                nil,
            musicArtist:
                nil,
            musicAudioURL:
                nil,
            musicStartTimeMs:
                0,
            photoMusicImageURLFallback:
                nil,
            videoURL:
                video.url,
            videoWidth:
                video.width,
            videoHeight:
                video.height
        )

        let mediaType = activityNumberInt(media["media_type"])
        let typename = (media["__typename"] as? String) ?? ""
        let product = (media["product_type"] as? String) ?? ""
        post.isVideo = mediaType == 2 ||
            ((media["is_video"] as? Bool) == true) ||
            typename.contains("Video") || product == "clips" ||
            video.url != nil
        post.shortcode = (media["code"] as? String) ??
            (media["shortcode"] as? String) ?? ""
        return post
    }

    static func activityValidatedShortcode(
        _ raw:
            String
    ) -> String? {
        var candidate =
            raw

        if
            let query =
                candidate.firstIndex(
                    of:
                        "?"
                )
        {
            candidate =
                String(
                    candidate[
                        ..<query
                    ]
                )
        }

        if
            let fragment =
                candidate.firstIndex(
                    of:
                        "#"
                )
        {
            candidate =
                String(
                    candidate[
                        ..<fragment
                    ]
                )
        }

        guard
            candidate.count >= 3,
            candidate.count <= 160
        else {
            return nil
        }

        let allowed =
            candidate.unicodeScalars
                .allSatisfy {
                    scalar in

                    let value =
                        scalar.value

                    return
                        (
                            value >= 48 &&
                            value <= 57
                        ) ||
                        (
                            value >= 65 &&
                            value <= 90
                        ) ||
                        (
                            value >= 97 &&
                            value <= 122
                        ) ||
                        value == 45 ||
                        value == 95
                }

        return
            allowed
                ? candidate
                : nil
    }

    static func activityShortcodeFromRoute(
        _ raw:
            String
    ) -> String? {

        let parts =
            raw.split(
                separator:
                    "/",
                omittingEmptySubsequences:
                    true
            )

        guard parts.count >= 2
        else {
            return nil
        }

        for index in 0..<(parts.count - 1) {
            let kind =
                String(
                    parts[index]
                )

            if
                kind == "p" ||
                kind == "reel"
            {
                return
                    activityValidatedShortcode(
                        String(
                            parts[index + 1]
                        )
                    )
            }
        }

        return nil
    }

    static func activityFindReferencedShortcode(
        _ value:
            Any,
        depth:
            Int = 0
    ) -> String? {

        guard depth <= 10
        else {
            return nil
        }

        if
            let string =
                value as? String
        {
            return
                activityShortcodeFromRoute(
                    string
                )
        }

        if
            let dictionary =
                value as?
                    [String: Any]
        {

            for key in [
                "shortcode",
                "media_shortcode",
                "media_short_code"
            ] {
                if
                    let raw =
                        dictionary[key]
                            as? String,
                    let candidate =
                        activityValidatedShortcode(
                            raw
                        )
                {
                    return candidate
                }
            }

            for key in [
                "href",
                "url",
                "link",
                "route_url",
                "destination",
                "target_url"
            ] {
                if
                    let raw =
                        dictionary[key]
                            as? String,
                    let candidate =
                        activityShortcodeFromRoute(
                            raw
                        )
                {
                    return candidate
                }
            }

            for child in dictionary.values {
                if
                    let found =
                        activityFindReferencedShortcode(
                            child,
                            depth:
                                depth + 1
                        )
                {
                    return found
                }
            }
        }
        else if
            let array =
                value as? [Any]
        {
            for child in array {
                if
                    let found =
                        activityFindReferencedShortcode(
                            child,
                            depth:
                                depth + 1
                        )
                {
                    return found
                }
            }
        }

        return nil
    }
}
