// Overview: Profile media: timeline requests and parsing for profile grids.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func profileTopLevelJSONFrames(
        _ data: Data
    ) -> [Data] {
        let bytes =
            [UInt8](
                data
            )

        var frames:
            [Data] = []

        var start:
            Int? =
            nil

        var depth =
            0

        var inString =
            false

        var escaped =
            false

        var index =
            0

        while
            index <
                bytes.count
        {
            let byte =
                bytes[index]

            if
                let frameStart =
                    start
            {
                if inString {
                    if escaped {
                        escaped =
                            false
                    }
                    else if
                        byte ==
                            0x5c
                    {
                        escaped =
                            true
                    }
                    else if
                        byte ==
                            0x22
                    {
                        inString =
                            false
                    }
                }
                else {
                    if
                        byte ==
                            0x22
                    {
                        inString =
                            true
                    }
                    else if
                        byte ==
                            0x7b ||
                        byte ==
                            0x5b
                    {
                        depth +=
                            1
                    }
                    else if
                        byte ==
                            0x7d ||
                        byte ==
                            0x5d
                    {
                        depth -=
                            1

                        if
                            depth ==
                                0
                        {
                            frames.append(
                                data.subdata(
                                    in:
                                        frameStart..<(index + 1)
                                )
                            )

                            start =
                                nil
                        }
                    }
                }
            }
            else if
                byte ==
                    0x7b ||
                byte ==
                    0x5b
            {
                start =
                    index

                depth =
                    1

                inString =
                    false

                escaped =
                    false
            }

            index +=
                1
        }

        return frames
    }

    static func profileTimelinePayload(
        _ value: Any
    ) -> [String: Any]? {
        if
            let dict =
                value as?
                    [String: Any]
        {
            if
                dict[
                    "profile_grid_items"
                ] != nil
            {
                return dict
            }

            for child in
                dict.values
            {
                if
                    let found =
                        profileTimelinePayload(
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
            for child in
                array
            {
                if
                    let found =
                        profileTimelinePayload(
                            child
                        )
                {
                    return found
                }
            }
        }

        return nil
    }

    static func normalizeProfileGraphQLMedia(
        _ raw: [String: Any]
    ) -> [String: Any] {
        var media =
            raw

        var user =
            (
                media[
                    "user"
                ] as?
                    [String: Any]
            ) ?? [:]

        if
            user["pk"] ==
                nil,
            let identifier =
                user[
                    "id"
                ]
        {
            user["pk"] =
                identifier
        }

        media["user"] =
            user

        let userID =
            stringValue(
                user[
                    "pk"
                ]
            ) ??
            stringValue(
                user[
                    "id"
                ]
            )

        let mediaID =
            stringValue(
                media[
                    "id"
                ]
            ) ??
            stringValue(
                media[
                    "pk"
                ]
            )

        if
            media[
                "pk"
            ] ==
                nil,
            let mediaID =
                mediaID,
            !mediaID.isEmpty
        {
            let shortID =
                mediaID
                    .components(
                        separatedBy:
                            "_"
                    )
                    .first ??
                mediaID

            media["pk"] =
                shortID
        }

        if
            let mediaID =
                mediaID,
            !mediaID.isEmpty,
            mediaID.range(
                of:
                    "_"
            ) ==
                nil,
            let userID =
                userID,
            !userID.isEmpty
        {
            media["id"] =
                mediaID +
                "_" +
                userID
        }

        if
            media[
                "taken_at"
            ] ==
                nil,
            let taken =
                media[
                    "1ltaken_at"
                ]
        {
            media[
                "taken_at"
            ] =
                taken
        }

        return media
    }

    static func profileTimelineNextCursor(
        _ timeline: [String: Any],
        excluding current: String?
    ) -> String? {
        func usable(
            _ value: Any?
        ) -> String? {
            guard
                let candidate =
                    stringValue(value),
                !candidate.isEmpty,
                candidate != current
            else {
                return nil
            }

            return candidate
        }

        for key in [
            "next_max_id",
            "profile_grid_items_cursor",
            "end_cursor",
            "max_id"
        ] {
            if
                let candidate =
                    usable(
                        timeline[key]
                    )
            {
                return candidate
            }
        }

        for containerKey in [
            "page_info",
            "paging_info",
            "pagination_info"
        ] {
            guard
                let container =
                    timeline[containerKey]
                        as? [String: Any]
            else {
                continue
            }

            for key in [
                "end_cursor",
                "next_max_id",
                "max_id",
                "profile_grid_items_cursor"
            ] {
                if
                    let candidate =
                        usable(
                            container[key]
                        )
                {
                    return candidate
                }
            }
        }

        for value in timeline.values {
            guard
                let child =
                    value as? [String: Any]
            else {
                continue
            }

            if
                let candidate =
                    profileTimelineNextCursor(
                        child,
                        excluding:
                            current
                    )
            {
                return candidate
            }
        }

        return nil
    }

    static func profileGraphQLFallbackRoot(
        userID: String,
        username: String,
        maxID: String?
    ) throws -> [String: Any] {
        let session =
            try loadSession()

        guard
            !userID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6450,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Profile user id unavailable."
                ]
            )
        }

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
                    "MagnistraProfileMedia",
                code:
                    6451,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        let cursor =
            maxID ?? ""

        let curlCode:
            Int32 =
                caPath.withCString { ca in
                    session.userAgent
                        .withCString { ua in
                            session.language
                                .withCString { lang in
                                    session.cookieHeader
                                        .withCString { cookies in
                                            session.csrfToken
                                                .withCString { csrf in
                                                    userID
                                                        .withCString { uid in
                                                            username
                                                                .withCString { uname in
                                                                    cursor
                                                                        .withCString { maxCursor in
                                                                            Int32(
                                                                                magnistra_profile_graphql_media_fetch(
                                                                                    ca,
                                                                                    ua,
                                                                                    lang,
                                                                                    cookies,
                                                                                    csrf,
                                                                                    uid,
                                                                                    uname,
                                                                                    maxCursor,
                                                                                    0
                                                                                )
                                                                            )
                                                                        }
                                                                }
                                                        }
                                                }
                                        }
                                }
                        }
                }

        guard
            curlCode == 0,
            magnistra_profile_media_http_status() >= 200,
            magnistra_profile_media_http_status() < 300,
            magnistra_profile_media_tls_verify_result() == 0
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6452,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram profile fallback request failed."
                ]
            )
        }

        let length =
            Int(
                magnistra_profile_media_body_length()
            )

        guard
            length > 0,
            let body =
                magnistra_profile_media_body()
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6453,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram profile fallback response was empty."
                ]
            )
        }

        let data =
            Data(
                bytes:
                    body,
                count:
                    length
            )

        let frames =
            profileTopLevelJSONFrames(
                data
            )

        func collectTimelines(
            _ value: Any,
            into output:
                inout [[String: Any]]
        ) {
            if
                let dictionary =
                    value as?
                        [String: Any]
            {
                if
                    dictionary[
                        "profile_grid_items"
                    ] != nil
                {
                    output.append(
                        dictionary
                    )
                }

                for child in
                    dictionary.values
                {
                    collectTimelines(
                        child,
                        into:
                            &output
                    )
                }
            }
            else if
                let array =
                    value as?
                        [Any]
            {
                for child in array {
                    collectTimelines(
                        child,
                        into:
                            &output
                    )
                }
            }
        }

        var timelines:
            [[String: Any]] =
                []

        for frame in frames {
            guard
                let object =
                    try?
                        MagnistraJSONKit
                            .jsonObject(
                                with:
                                    frame,
                                options:
                                    []
                            )
            else {
                continue
            }

            collectTimelines(
                object,
                into:
                    &timelines
            )
        }

        guard
            !timelines.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6454,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram profile fallback grid payload was not recognized."
                ]
            )
        }

        var orderedKeys:
            [String] =
                []

        var mediaByKey:
            [String: [String: Any]] =
                [:]

        var nextCursor:
            String? =
                nil

        var sawMoreAvailable =
            false

        for timeline in timelines {
            let gridItems =
                (
                    timeline[
                        "profile_grid_items"
                    ] as?
                        [[String: Any]]
                ) ?? []

            for item in gridItems {
                guard
                    let raw =
                        item[
                            "media"
                        ] as?
                            [String: Any]
                else {
                    continue
                }

                let media =
                    normalizeProfileGraphQLMedia(
                        raw
                    )

                let key =
                    stringValue(
                        media["pk"]
                    ) ??
                    stringValue(
                        media["id"]
                    ) ??
                    ""

                guard
                    !key.isEmpty
                else {
                    continue
                }

                if
                    var existing =
                        mediaByKey[key]
                {
                    for
                        (field, value)
                    in media
                    {
                        if
                            field == "user",
                            let oldUser =
                                existing[
                                    field
                                ] as?
                                    [String: Any],
                            let newUser =
                                value as?
                                    [String: Any]
                        {
                            var mergedUser =
                                oldUser

                            for
                                (userField, userValue)
                            in newUser
                            {
                                mergedUser[
                                    userField
                                ] =
                                    userValue
                            }

                            existing[
                                field
                            ] =
                                mergedUser
                        }
                        else {
                            existing[
                                field
                            ] =
                                value
                        }
                    }

                    mediaByKey[
                        key
                    ] =
                        existing
                }
                else {
                    orderedKeys.append(
                        key
                    )

                    mediaByKey[
                        key
                    ] =
                        media
                }
            }

            if
                let candidate =
                    profileTimelineNextCursor(
                        timeline,
                        excluding:
                            maxID
                    )
            {
                nextCursor =
                    candidate
            }

            if
                boolValue(
                    timeline[
                        "more_available"
                    ]
                ) == true
            {
                sawMoreAvailable =
                    true
            }
        }

        let normalized =
            orderedKeys
                .compactMap {
                    mediaByKey[$0]
                }

        var root:
            [String: Any] = [
                "items":
                    normalized,
                "more_available":
                    sawMoreAvailable
            ]

        if
            let nextCursor =
                nextCursor,
            !nextCursor.isEmpty,
            nextCursor != maxID
        {
            root[
                "next_max_id"
            ] =
                nextCursor
        }

        return root
    }

    static func profileMediaRoot(
        userID: String,
        username: String,
        maxID: String?,
        byUsername: Bool
    ) throws -> [String: Any] {
        let session =
            try loadSession()

        guard
            !userID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Profile user id unavailable."
                ]
            )
        }

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
                    "MagnistraProfileMedia",
                code:
                    6401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        let cursor =
            maxID ?? ""

        let curlCode:
            Int32 =
                caPath.withCString { ca in
                    session.userAgent
                        .withCString { ua in
                            session.language
                                .withCString { lang in
                                    session.cookieHeader
                                        .withCString { cookies in
                                            session.csrfToken
                                                .withCString { csrf in
                                                    userID
                                                        .withCString { uid in
                                                            username
                                                                .withCString { uname in
                                                                    cursor
                                                                        .withCString { maxCursor in
                                                                            Int32(
                                                                                magnistra_profile_media_fetch(
                                                                                    ca,
                                                                                    ua,
                                                                                    lang,
                                                                                    cookies,
                                                                                    csrf,
                                                                                    uid,
                                                                                    uname,
                                                                                    maxCursor,
                                                                                    byUsername
                                                                                        ? 1
                                                                                        : 0
                                                                                )
                                                                            )
                                                                        }
                                                                }
                                                        }
                                                }
                                        }
                                }
                        }
                }

        guard
            curlCode == 0,
            magnistra_profile_media_http_status() >= 200,
            magnistra_profile_media_http_status() < 300,
            magnistra_profile_media_tls_verify_result() == 0
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6402,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram native profile feed request failed."
                ]
            )
        }

        let length =
            Int(
                magnistra_profile_media_body_length()
            )

        guard
            length > 0,
            let body =
                magnistra_profile_media_body()
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6403,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram native profile feed response was empty."
                ]
            )
        }

        let data =
            Data(
                bytes:
                    body,
                count:
                    length
            )

        guard
            let object =
                try
                    MagnistraJSONKit
                        .jsonObject(
                            with:
                                data,
                            options:
                                []
                        )
                    as?
                        [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6404,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram native profile feed payload was not recognized."
                ]
            )
        }

        let items =
            (
                object[
                    "items"
                ] as?
                    [[String: Any]]
            ) ?? []

        var root:
            [String: Any] = [
                "items":
                    items
            ]

        if
            let more =
                object[
                    "more_available"
                ]
        {
            root[
                "more_available"
            ] =
                more
        }

        if
            let next =
                object[
                    "next_max_id"
                ] ??
                object[
                    "max_id"
                ]
        {
            root[
                "next_max_id"
            ] =
                next
        }

        return root
    }

    static func profilePostsWebTimelineRoot(
        username: String,
        maxID: String?
    ) throws -> [String: Any] {
        guard !username.isEmpty else {
            throw NSError(domain: "MagnistraProfileMedia", code: 6470,
                userInfo: [NSLocalizedDescriptionKey: "Profile username unavailable."])
        }
        let isPagination = maxID != nil
        let dataVariables: [String: Any] = [
            "count": 12,
            "include_reel_media_seen_timestamp": false,
            "include_relationship_info": false,
            "latest_besties_reel_media": false,
            "latest_reel_media": false
        ]
        var variables: [String: Any] = [
            "username": username,
            "data": dataVariables,
            "__relay_internal__pv__PolarisMultiCaptionCarouselEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisReelsRecoDebugOverlayEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider": false,
            "__relay_internal__pv__PolarisThreadsStyleCommentsEnabledrelayprovider": false
        ]
        if let cursor = maxID {
            guard !cursor.isEmpty else {
                throw NSError(domain: "MagnistraProfileMedia", code: 6471,
                    userInfo: [NSLocalizedDescriptionKey: "Empty profile pagination cursor."])
            }
            variables["after"] = cursor
            variables["before"] = NSNull()
            variables["first"] = 12
            variables["last"] = NSNull()
            variables["include_multi_captions"] = false
        }

        let response = try exploreSearchGraphQLRoot(
            variables: variables,
            docID: isPagination ? "39229011733413759" : "28834890909485062",
            friendlyName: isPagination
                ? "PolarisProfilePostsTabContentQuery_connection"
                : "PolarisProfilePostsQuery"
        )

        let diagnosticData = response["data"] as? [String: Any]
        let diagnosticConnection = diagnosticData?["xdt_api__v1__feed__user_timeline_graphql_connection"] as? [String: Any]
        let diagnosticEdges = diagnosticConnection?["edges"] as? [[String: Any]]
        print("MAGNISTRA_PROFILE_POSTS_RESPONSE page=\(isPagination ? "next" : "first") errors=\(response["errors"] == nil ? 0 : 1) data=\(diagnosticData == nil ? 0 : 1) connection=\(diagnosticConnection == nil ? 0 : 1) edges=\(diagnosticEdges?.count ?? -1)")
        guard response["errors"] == nil,
              let data = response["data"] as? [String: Any],
              let connection = data["xdt_api__v1__feed__user_timeline_graphql_connection"]
                    as? [String: Any],
              let edges = connection["edges"] as? [[String: Any]]
        else {
            throw NSError(domain: "MagnistraProfileMedia", code: 6472,
                userInfo: [NSLocalizedDescriptionKey: "Profile posts web response unrecognized."])
        }
        var mediaItems: [[String: Any]] = []
        for edge in edges {
            guard let node = edge["node"] as? [String: Any] else { continue }
            mediaItems.append(normalizeProfileGraphQLMedia(node))
        }
        print("MAGNISTRA_PROFILE_POSTS_NORMALIZED page=\(isPagination ? "next" : "first") edges=\(edges.count) media=\(mediaItems.count)")
        let pageInfo = connection["page_info"] as? [String: Any]
        let hasMore = (pageInfo?["has_next_page"] as? Bool) ?? false
        var result: [String: Any] = [
            "items": mediaItems,
            "more_available": hasMore
        ]

        if hasMore && !mediaItems.isEmpty,
           let cursor = pageInfo?["end_cursor"] as? String,
           !cursor.isEmpty,
           cursor != maxID {
            result["next_max_id"] = cursor
        }
        return result
    }

    static func loadProfileMediaPage(
        userID: String,
        username: String,
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {
        profileMediaLock.lock()

        defer {
            profileMediaLock.unlock()
        }

        let webPrefix = "webposts:"
        let gqlPrefix = "gql:"
        let usingGraphQLFallback = maxID?.hasPrefix(gqlPrefix) ?? false
        let effectiveMaxID: String?
        if let rawMaxID = maxID {
            if rawMaxID == "gql:START" {
                effectiveMaxID = nil
            } else if rawMaxID.hasPrefix(gqlPrefix) {
                let suffix = String(rawMaxID.dropFirst(gqlPrefix.count))
                guard !suffix.isEmpty else {
                    throw NSError(domain: "MagnistraProfileMedia", code: 6474,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid profile fallback cursor."])
                }
                effectiveMaxID = suffix
            } else if rawMaxID.hasPrefix(webPrefix) {
                let suffix = String(rawMaxID.dropFirst(webPrefix.count))
                guard !suffix.isEmpty else {
                    throw NSError(domain: "MagnistraProfileMedia", code: 6474,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid profile pagination cursor."])
                }
                effectiveMaxID = suffix
            } else {
                throw NSError(domain: "MagnistraProfileMedia", code: 6473,
                    userInfo: [NSLocalizedDescriptionKey: "Unrecognized profile pagination cursor."])
            }
        } else { effectiveMaxID = nil }
        let root: [String: Any]? = try usingGraphQLFallback
            ? profileGraphQLFallbackRoot(
                userID: userID, username: username, maxID: effectiveMaxID)
            : profilePostsWebTimelineRoot(
                username: username, maxID: effectiveMaxID)

        let rows =
            (
                root?[
                    "items"
                ] as?
                    [[String: Any]]
            )

        guard
            let resolvedRoot =
                root
        else {
            throw NSError(
                domain:
                    "MagnistraProfileMedia",
                code:
                    6314,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Profile posts could not be loaded."
                ]
            )
        }

        let mediaRows =
            rows ?? []

        let photoQuality =
            MagnistraMediaPreferences
                .photoQuality

        var posts:
            [MagnistraRealPost] = []
        var missingImageCount = 0
        var missingUsernameCount = 0

        for row in mediaRows {
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
                missingImageCount += 1
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
                missingUsernameCount += 1
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
                "profile-grid:" +
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
                "profile-grid-avatar:" +
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
                    media
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
        }

        var next =
            stringValue(
                resolvedRoot[
                    "next_max_id"
                ]
            )

        if
            next?.isEmpty == true ||
            next == effectiveMaxID
        {
            next =
                nil
        }

        if let nextValue = next, !nextValue.isEmpty {
            next = (usingGraphQLFallback ? gqlPrefix : webPrefix) + nextValue
        }

        print("MAGNISTRA_PROFILE_POSTS_PARSED page=\(maxID == nil ? "first" : "next") items=\(mediaRows.count) accepted=\(posts.count) no_image=\(missingImageCount) no_username=\(missingUsernameCount) more=\(next == nil ? 0 : 1)")
        return MagnistraProfileMediaPage(
            posts:
                posts,
            nextMaxID:
                next
        )
    }
}
