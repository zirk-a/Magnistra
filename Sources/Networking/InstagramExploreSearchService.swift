// Overview: Explore search: user and tag search requests.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func makeExploreSearchSessionID()
        -> String
    {
        guard
            let uuid =
                CFUUIDCreate(
                    kCFAllocatorDefault
                ),
            let value =
                CFUUIDCreateString(
                    kCFAllocatorDefault,
                    uuid
                )
        else {
            return
                String(
                    Int(
                        Date()
                            .timeIntervalSince1970 *
                        1000.0
                    )
                )
        }

        return value as String
    }

    static func exploreSearchGraphQLRoot(
        variables: [String: Any],
        docID: String,
        friendlyName: String
    ) throws -> [String: Any] {
        exploreSearchLock.lock()

        defer {
            exploreSearchLock.unlock()
        }

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
                    "MagnistraExploreSearch",
                code:
                    6800,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Search CA bundle unavailable."
                ]
            )
        }

        let variablesData =
            try MagnistraJSONKit.data(
                withJSONObject:
                    variables,
                options:
                    []
            )

        guard
            let variablesJSON =
                String(
                    data:
                        variablesData,
                    encoding:
                        .utf8
                )
        else {
            throw NSError(
                domain:
                    "MagnistraExploreSearch",
                code:
                    6801,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Couldn’t encode search request."
                ]
            )
        }

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
                                                    variablesJSON
                                                        .withCString { vars in
                                                            docID
                                                                .withCString { doc in
                                                                    friendlyName
                                                                        .withCString { friendly in
                                                                            Int32(
                                                                                magnistra_explore_graphql_fetch(
                                                                                    ca,
                                                                                    ua,
                                                                                    lang,
                                                                                    cookies,
                                                                                    csrf,
                                                                                    vars,
                                                                                    doc,
                                                                                    friendly
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

        let status =
            magnistra_explore_search_http_status()

        guard
            curlCode == 0,
            status >= 200,
            status < 300,
            magnistra_explore_search_tls_verify_result() == 0
        else {
            throw NSError(
                domain:
                    "MagnistraExploreSearch",
                code:
                    Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Search request failed (HTTP \(status))."
                ]
            )
        }

        let length =
            Int(
                magnistra_explore_search_body_length()
            )

        guard
            length > 0,
            let body =
                magnistra_explore_search_body()
        else {
            throw NSError(
                domain:
                    "MagnistraExploreSearch",
                code:
                    6802,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Search returned an empty response."
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
            let root =
                try MagnistraJSONKit
                    .jsonObject(
                        with:
                            data,
                        options:
                            []
                    )
                    as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraExploreSearch",
                code:
                    6803,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Search response was not recognized."
                ]
            )
        }

        return root
    }

    static func loadExploreUserSearch(
        query: String,
        searchSessionID: String,
        rankToken: String
    ) throws -> MagnistraExploreUserSearchPage {
        let variables:
            [String: Any] = [
                "data": [
                    "context":
                        "blended",
                    "include_reel":
                        "true",
                    "query":
                        query,
                    "rank_token":
                        rankToken,
                    "search_session_id":
                        searchSessionID,
                    "search_surface":
                        "web_top_search"
                ],
                "hasQuery":
                    true
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "27706427925724183",
                friendlyName:
                    "PolarisSearchBoxRefetchableQuery"
            )

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let connection =
                data[
                    "xdt_api__v1__fbsearch__topsearch_connection"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraExploreSearch",
                code:
                    6810,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram user-search payload was not recognized."
                ]
            )
        }

        let rows =
            connection["users"]
                as? [[String: Any]] ??
            []

        var users:
            [MagnistraExploreSearchUser] =
                []

        for row in rows {
            guard
                let user =
                    row["user"]
                        as? [String: Any]
            else {
                continue
            }

            let username =
                (
                    user["username"]
                        as? String
                ) ?? ""

            if username.isEmpty {
                continue
            }

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

            let hdURL =
                (
                    user[
                        "hd_profile_pic_url_info"
                    ] as?
                        [String: Any]
                )?["url"]
                    as? String

            let avatarURL =
                hdURL ??
                (
                    user["profile_pic_url"]
                        as? String
                )

            users.append(
                MagnistraExploreSearchUser(
                    userID:
                        userID,
                    username:
                        username,
                    fullName:
                        (
                            user["full_name"]
                                as? String
                        ) ?? "",
                    avatarURL:
                        avatarURL,
                    isVerified:
                        boolValue(
                            user["is_verified"]
                        ) ?? false
                )
            )
        }

        return
            MagnistraExploreUserSearchPage(
                users:
                    users,
                rankToken:
                    stringValue(
                        connection[
                            "rank_token"
                        ]
                    ) ?? ""
            )
    }

    static func exploreTagThumbnailURL(
        _ media: [String: Any]
    ) -> String {
        guard
            let versions =
                media["image_versions2"]
                    as? [String: Any],
            let candidates =
                versions["candidates"]
                    as? [[String: Any]],
            !candidates.isEmpty
        else {
            return ""
        }

        var selectedURL = ""
        var selectedArea =
            Int.max

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

            let area =
                (
                    width > 0 &&
                    height > 0
                )
                    ? width * height
                    : Int.max - 1

            if
                selectedURL.isEmpty ||
                area < selectedArea
            {
                selectedURL =
                    url
                selectedArea =
                    area
            }
        }

        return selectedURL
    }

    static func loadExploreTagSearchPage(
        tag: String,
        searchSessionID: String,
        after: String?
    ) throws -> MagnistraExploreTagSearchPage {
        var variables:
            [String: Any] = [
                "query":
                    tag,
                "search_session_id":
                    searchSessionID,
                "serp_session_id":
                    searchSessionID
            ]

        let isPagination =
            after != nil &&
            after?.isEmpty == false

        if
            let after =
                after,
            !after.isEmpty
        {
            variables[
                "after"
            ] =
                after

            variables[
                "first"
            ] =
                24
        }

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    isPagination
                        ? "28656899673911396"
                        : "37324993597144881",
                friendlyName:
                    isPagination
                        ? "PolarisKeywordSearchExplorePageRelayPaginationQuery"
                        : "PolarisKeywordSearchExplorePageRelayQuery"
            )

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let graph =
                data[
                    "xdt_fbsearch__top_serp_graphql"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraExploreSearch",
                code:
                    6820,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram tag-search payload was not recognized."
                ]
            )
        }

        let edges =
            graph["edges"]
                as? [[String: Any]] ??
            []

        var items:
            [MagnistraExploreTagSearchItem] =
                []
        var seen =
            Set<String>()

        for edge in edges {
            guard
                let node =
                    edge["node"]
                        as? [String: Any],
                let mediaItems =
                    node["items"]
                        as? [[String: Any]]
            else {
                continue
            }

            for media in mediaItems {
                let shortcode =
                    (
                        media["code"]
                            as? String
                    ) ?? ""

                if shortcode.isEmpty {
                    continue
                }

                let mediaID =
                    stringValue(
                        media["pk"]
                    ) ??
                    stringValue(
                        media["id"]
                    ) ??
                    shortcode

                if
                    seen.contains(
                        mediaID
                    )
                {
                    continue
                }

                seen.insert(
                    mediaID
                )

                items.append(
                    MagnistraExploreTagSearchItem(
                        mediaID:
                            mediaID,
                        shortcode:
                            shortcode,
                        thumbnailURL:
                            exploreTagThumbnailURL(
                                media
                            ),
                        isVideo:
                            intValue(
                                media[
                                    "media_type"
                                ]
                            ) == 2 ||
                            media[
                                "video_versions"
                            ] is
                                [[String: Any]]
                    )
                )
            }
        }

        let pageInfo =
            graph["page_info"]
                as? [String: Any]

        let cursor =
            stringValue(
                pageInfo?[
                    "end_cursor"
                ]
            )

        let hasNext =
            (
                boolValue(
                    pageInfo?[
                        "has_next_page"
                    ]
                ) ?? false
            ) &&
            cursor?.isEmpty == false

        return
            MagnistraExploreTagSearchPage(
                items:
                    items,
                endCursor:
                    hasNext
                        ? cursor
                        : nil,
                hasNextPage:
                    hasNext
            )
    }
}
