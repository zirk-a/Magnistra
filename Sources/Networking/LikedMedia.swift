// Overview: Liked media: requests and parsing.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func likedJSON(
        _ object: [String: Any]
    ) throws -> String {
        let data =
            try MagnistraJSONKit.data(
                withJSONObject:
                    object,
                options:
                    []
            )

        guard
            let value =
                String(
                    data:
                        data,
                    encoding:
                        .utf8
                )
        else {
            throw NSError(
                domain:
                    "MagnistraProfileLiked",
                code:
                    9500,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Couldn’t encode Liked request."
                ]
            )
        }

        return value
    }

    static func likedOrderObject()
        -> [String: Any]
    {
        let type:
            [String: Any] = [
                "py/type":
                    "bloks.apps.instagram.privacy.activity_center.general_constants.ActivityCenterSortAndFilterConstants"
            ]

        let tuple:
            [String: Any] = [
                "py/tuple":
                    [
                        "newest_to_oldest"
                    ]
            ]

        return [
            "py/reduce":
                [
                    type,
                    tuple
                ] as [Any]
        ]
    }

    static func likedRefreshParams()
        throws -> String
    {
        let root:
            [String: Any] = [
                "content_container_id":
                    14155516,
                "content_element_id":
                    14155517,
                "content_spinner_id":
                    14155518,
                "main_order_state_value":
                    false,
                "main_attribute_order_state_value":
                    likedOrderObject(),
                "main_date_start_state_value":
                    -1,
                "main_date_end_state_value":
                    -1,
                "main_authors_state_value":
                    "",
                "main_filter_to_visible_on_facebook_value":
                    false,
                "main_includes_location_value":
                    false,
                "main_liked_privately_value":
                    false,
                "main_content_type_value":
                    0,
                "main_content_types_value":
                    "Posts, Reels",
                "main_account_history_events_state_value":
                    "",
                "entrypoint":
                    "",
                "shared_user_id":
                    "",
                "main_filter_to_visible_from_facebook_value":
                    false
            ]

        return try likedJSON(
            root
        )
    }

    static func likedNextParams(
        cursor: String,
        elementID: String
    ) throws -> String {
        let activity:
            [String: Any] = [
                "py/object":
                    "bloks.apps.instagram.privacy.activity_center.data_types.ActivityCenterParams",
                "initial_cursor":
                    cursor,
                "main_order_state_value":
                    false,
                "main_date_start_state_value":
                    -1,
                "main_date_end_state_value":
                    -1,
                "main_filter_to_visible_on_facebook_value":
                    false,
                "main_includes_location_value":
                    false,
                "main_liked_privately_value":
                    false,
                "main_content_type_value":
                    0,
                "main_content_types_value":
                    "Posts, Reels",
                "main_authors_state_value":
                    "",
                "main_account_history_events_state_value":
                    "",
                "handlers":
                    NSNull(),
                "content_container_id":
                    14155516,
                "content_element_id":
                    14155517,
                "content_spinner_id":
                    14155518,
                "items_for_action":
                    "",
                "number_of_items":
                    0,
                "shared_user_id":
                    NSNull(),
                "main_attribute_order_state_value":
                    likedOrderObject(),
                "main_filter_to_visible_from_facebook_value":
                    false
            ]

        let encodedActivity =
            try likedJSON(
                activity
            )

        let root:
            [String: Any] = [
                "page_size":
                    "9",
                "activity_center_params":
                    encodedActivity,
                "cursor":
                    cursor,
                "container_id":
                    "1454335516",
                "element_id":
                    elementID
            ]

        return try likedJSON(
            root
        )
    }

    static func likedWBloksText(
        appID: String,
        params: String
    ) throws -> String {
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
                    "MagnistraProfileLiked",
                code:
                    9501,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Liked CA bundle unavailable."
                ]
            )
        }

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

                                                    appID
                                                        .withCString {
                                                            app in

                                                            params
                                                                .withCString {
                                                                    body in

                                                                    Int32(
                                                                        magnistra_explore_wbloks_fetch(
                                                                            ca,
                                                                            ua,
                                                                            lang,
                                                                            cookies,
                                                                            csrf,
                                                                            app,
                                                                            "action",
                                                                            body
                                                                        )
                                                                    )
                                                                }
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
            throw NSError(
                domain:
                    "MagnistraProfileLiked",
                code:
                    Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Liked request failed (HTTP \(status))."
                ]
            )
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
            throw NSError(
                domain:
                    "MagnistraProfileLiked",
                code:
                    9502,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Liked returned an empty response."
                ]
            )
        }

        let data =
            Data(
                bytes:
                    pointer,
                count:
                    length
            )

        guard
            let text =
                String(
                    data:
                        data,
                    encoding:
                        .utf8
                )
        else {
            throw NSError(
                domain:
                    "MagnistraProfileLiked",
                code:
                    9503,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Liked response was not readable."
                ]
            )
        }

        return text
    }

    static func likedMediaIDs(
        _ text: String
    ) -> [String] {
        var normalizedText =
            text

        let textReplacements:
            [(String, String)] = [
                ("\\\\u003d", "="),
                ("\\\\u003D", "="),
                ("\\u003d", "="),
                ("\\u003D", "="),
                ("%3D", "="),
                ("%3d", "="),
                ("&amp;", "&"),
                ("\\\\/", "/")
            ]

        for pair in textReplacements {
            normalizedText =
                normalizedText.replacingOccurrences(
                    of:
                        pair.0,
                    with:
                        pair.1
                )
        }

        guard
            let expression =
                try? NSRegularExpression(
                    pattern:
                        "ig_cache_key=([A-Za-z0-9%+/=_-]+)",
                    options:
                        []
                )
        else {
            return []
        }

        let ns =
            normalizedText as NSString

        let matches =
            expression.matches(
                in:
                    normalizedText,
                options:
                    [],
                range:
                    NSRange(
                        location:
                            0,
                        length:
                            ns.length
                    )
            )

        var result:
            [String] = []

        var seen =
            Set<String>()

        for match in matches {
            if match.numberOfRanges < 2 {
                continue
            }

            var raw =
                ns.substring(
                    with:
                        match.range(
                            at:
                                1
                        )
                )

            let replacements:
                [(String, String)] = [
                    ("%2B", "+"),
                    ("%2b", "+"),
                    ("%2F", "/"),
                    ("%2f", "/"),
                    ("%3D", "="),
                    ("%3d", "="),
                    ("%5F", "_"),
                    ("%5f", "_"),
                    ("%2D", "-"),
                    ("%2d", "-")
                ]

            for pair in replacements {
                raw =
                    raw.replacingOccurrences(
                        of:
                            pair.0,
                        with:
                            pair.1
                    )
            }

            if
                let dot =
                    raw.range(
                        of:
                            ".",
                        options:
                            .backwards
                    ),
                raw[
                    dot.upperBound...
                ].rangeOfCharacter(
                    from:
                        CharacterSet
                            .decimalDigits
                            .inverted
                ) == nil
            {
                raw =
                    String(
                        raw[
                            ..<dot.lowerBound
                        ]
                    )
            }

            var normalized =
                raw
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            "+"
                    )
                    .replacingOccurrences(
                        of:
                            "_",
                        with:
                            "/"
                    )

            while
                normalized.count %
                4 !=
                0
            {
                normalized +=
                    "="
            }

            guard
                let data =
                    Data(
                        base64Encoded:
                            normalized
                    ),
                let decoded =
                    String(
                        data:
                            data,
                        encoding:
                            .utf8
                    )
            else {
                continue
            }

            let components =
                decoded.components(
                    separatedBy:
                        CharacterSet
                            .decimalDigits
                            .inverted
                )

            let digits =
                components
                    .first {
                        !$0.isEmpty
                    } ?? ""

            if
                !digits.isEmpty,
                !seen.contains(
                    digits
                )
            {
                seen.insert(
                    digits
                )

                result.append(
                    digits
                )
            }
        }

        return result
    }

    static func likedCursor(
        _ text: String
    ) -> String? {
        guard
            let expression =
                try? NSRegularExpression(
                    pattern:
                        "QVF[A-Za-z0-9_+/=-]{30,}={0,2}",
                    options:
                        []
                )
        else {
            return nil
        }

        let ns =
            text as NSString

        let matches =
            expression.matches(
                in:
                    text,
                options:
                    [],
                range:
                    NSRange(
                        location:
                            0,
                        length:
                            ns.length
                    )
            )

        guard
            let last =
                matches.last
        else {
            return nil
        }

        return
            ns.substring(
                with:
                    last.range
            )
    }

    static func likedShortcode(
        mediaID: String
    ) -> String? {
        guard
            var value =
                UInt64(
                    mediaID
                )
        else {
            return nil
        }

        let alphabet =
            Array(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            )

        if value == 0 {
            return String(
                alphabet[0]
            )
        }

        var output =
            ""

        while value > 0 {
            let index =
                Int(
                    value %
                    64
                )

            output =
                String(
                    alphabet[
                        index
                    ]
                ) +
                output

            value =
                value /
                64
        }

        return output
    }

    static func loadProfileLikedWBloksPage(
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {

        if
            let state =
                maxID,
            !state.isEmpty
        {

            return
                MagnistraProfileMediaPage(
                    posts:
                        [],
                    nextMaxID:
                        nil
                )
        }

        let text =
            try likedWBloksText(
                appID:
                    "com.instagram.privacy.activity_center.liked_media_screen",
                params:
                    "{}"
            )

        let ids =
            likedMediaIDs(
                text
            )

        var posts:
            [MagnistraRealPost] =
                []

        for mediaID in ids {
            guard
                let shortcode =
                    likedShortcode(
                        mediaID:
                            mediaID
                    )
            else {
                continue
            }

            if
                let post =
                    try?
                        loadActivityReferencedPost(
                            shortcode:
                                shortcode
                        )
            {
                posts.append(
                    post
                )
            }
        }

        return
            MagnistraProfileMediaPage(
                posts:
                    posts,
                nextMaxID:
                    nil
            )
    }

    static func loadProfileRepostsPage(
        userID: String,
        maxID: String?
    ) throws -> MagnistraProfileMediaPage {
        guard
            !userID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraProfileReposts",
                code:
                    9460,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Profile user ID unavailable."
                ]
            )
        }

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
                "id":
                    userID,
                "max_id":
                    cursor
            ]

            docID =
                "28844503865240264"

            friendlyName =
                "PolarisProfileRepostsTabContentRefetchQuery"
        } else {
            variables = [
                "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider":
                    false,
                "user_id":
                    userID
            ]

            docID =
                "28594321130221951"

            friendlyName =
                "PolarisProfileRepostsTabContentQuery"
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

        guard
            let timeline =
                postActionFindDictionary(
                    key:
                        "user_reposts_timeline",
                    in:
                        root
                )
        else {
            throw NSError(
                domain:
                    "MagnistraProfileReposts",
                code:
                    9461,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not return the Reposts timeline."
                ]
            )
        }

        let rows =
            timeline[
                "repost_grid_items"
            ] as? [[String: Any]] ??
            []

        var posts:
            [MagnistraRealPost] = []

        for row in rows {
            guard
                let media =
                    row[
                        "media"
                    ] as? [String: Any],
                let post =
                    savedRichPost(media: media)
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
                    row
            )

            posts.append(
                post
            )
        }

        let more =
            boolValue(
                timeline[
                    "repost_more_available"
                ]
            ) ?? false

        let next =
            stringValue(
                timeline[
                    "repost_next_max_id"
                ]
            )

        return
            MagnistraProfileMediaPage(
                posts:
                    posts,
                nextMaxID:
                    (
                        more &&
                        next?.isEmpty != true
                    )
                        ? next
                        : nil
            )
    }
}
