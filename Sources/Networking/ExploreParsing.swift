// Overview: Explore: parsing media out of Explore responses.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func exploreMediaIdentity(
        _ media: [String: Any]
    ) -> String? {
        if
            let value =
                stringValue(
                    media["pk"]
                ),
            !value.isEmpty
        {
            return value
        }

        if
            let value =
                stringValue(
                    media["id"]
                ),
            !value.isEmpty
        {
            return value
        }

        if
            let value =
                media["code"] as? String,
            !value.isEmpty
        {
            return value
        }

        return nil
    }

    static func exploreLooksLikeMedia(
        _ media: [String: Any]
    ) -> Bool {
        let hasIdentity =
            exploreMediaIdentity(
                media
            ) != nil

        let hasUser =
            media["user"]
                is [String: Any]

        let hasVisual =
            media["image_versions2"]
                is [String: Any] ||
            media["video_versions"]
                is [[String: Any]] ||
            media["carousel_media"]
                is [[String: Any]]

        return
            hasIdentity &&
            hasUser &&
            hasVisual
    }

    static func magnistraCollectSectionalMedia(
        _ sections: [Any],
        rows: inout [[String: Any]],
        seen: inout Set<String>
    ) -> Bool {
        if sections.isEmpty { return false }
        var collected: [[String: Any]] = []
        var found = Set<String>()
        for rawSection in sections {
            guard
                let section = rawSection as? [String: Any],
                let content = section["layout_content"] as? [String: Any],
                let items = content["medias"] as? [Any],
                !items.isEmpty
            else { return false }
            for (key, child) in content where key != "medias" {

                if child is [Any] || child is [String: Any] { return false }
            }
            for rawItem in items {
                guard let item = rawItem as? [String: Any] else { return false }
                let media = (item["media"] as? [String: Any]) ?? item
                guard
                    exploreLooksLikeMedia(media),
                    let identity = exploreMediaIdentity(media)
                else { return false }

                if let carousel = media["carousel_media"] as? [Any] {
                    for rawChild in carousel {
                        if let child = rawChild as? [String: Any],
                           exploreLooksLikeMedia(child) { return false }
                    }
                }
                if !found.contains(identity) && !seen.contains(identity) {
                    found.insert(identity)
                    collected.append(["media": media])
                }
            }
        }
        if collected.isEmpty { return false }
        rows.append(contentsOf: collected)
        seen.formUnion(found)
        return true
    }

static func collectExploreMedia(
        _ value: Any,
        rows: inout [[String: Any]],
        seen: inout Set<String>
    ) {
        if
            let array =
                value as? [Any]
        {
            for child in array {
                collectExploreMedia(
                    child,
                    rows:
                        &rows,
                    seen:
                        &seen
                )
            }

            return
        }

        guard
            let object =
                value as?
                    [String: Any]
        else {
            return
        }

        if
            let media =
                object["media"]
                    as?
                    [String: Any],
            exploreLooksLikeMedia(
                media
            ),
            let identity =
                exploreMediaIdentity(
                    media
                ),
            !seen.contains(
                identity
            )
        {
            seen.insert(
                identity
            )

            rows.append(
                [
                    "media":
                        media
                ]
            )
        }

        if
            exploreLooksLikeMedia(
                object
            ),
            let identity =
                exploreMediaIdentity(
                    object
                ),
            !seen.contains(
                identity
            )
        {
            seen.insert(
                identity
            )

            rows.append(
                [
                    "media":
                        object
                ]
            )
        }

        for (key, child) in object {

            if key == "image_versions2" || key == "video_versions" ||
               key == "user" || key == "caption" || key == "location" ||
               key == "preview_comments" || key == "comments" ||
               key == "music_metadata" || key == "usertags" ||
               key == "facepile_top_likers" || key == "likers" {
                continue
            }

            if !(child is [String: Any]) && !(child is [Any]) { continue }
            collectExploreMedia(
                child,
                rows:
                    &rows,
                seen:
                    &seen
            )
        }
    }

    static func exploreRoot(
        maxID: String?
    ) throws -> [String: Any]
    {
        let networkStageStartedAt = MagnistraFeedTiming.now()
        defer { MagnistraFeedTiming.mark("EXPLORE", "ROOT_TOTAL", networkStageStartedAt) }

        let session =
            try loadSession()

        let cursor =
            maxID ?? ""

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
                    "MagnistraExplore",
                code:
                    6400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Explore unavailable."
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
                                                    cursor
                                                        .withCString { maxCursor in
                                                            Int32(
                                                                magnistra_explore_fetch(
                                                                    ca,
                                                                    ua,
                                                                    lang,
                                                                    cookies,
                                                                    csrf,
                                                                    maxCursor
                                                                )
                                                            )
                                                        }
                                                }
                                        }
                                }
                        }
                }

        let httpStatus =
            magnistra_explore_http_status()

        let tlsResult =
            magnistra_explore_tls_verify_result()

        let length =
            Int(
                magnistra_explore_body_length()
            )

        if
            curlCode == 0,
            httpStatus == 400,
            tlsResult == 0,
            length > 0,
            let body =
                magnistra_explore_body()
        {
            let data =
                Data(
                    bytes:
                        body,
                    count:
                        length
                )

            if
                let object =
                    try?
                        MagnistraJSONKit
                            .jsonObject(
                                with:
                                    data,
                                options:
                                    []
                            ),
                let errorRoot =
                    object as?
                        [String: Any],
                let spam =
                    errorRoot["spam"]
                        as? Bool,
                spam
            {
                throw NSError(
                    domain:
                        "MagnistraExplore",
                    code:
                        6401,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Explore temporarily unavailable."
                    ]
                )
            }
        }

        guard
            curlCode == 0,
            httpStatus >= 200,
            httpStatus < 300,
            tlsResult == 0,
            length > 0,
            let body =
                magnistra_explore_body()
        else {
            throw NSError(
                domain:
                    "MagnistraExplore",
                code:
                    6402,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Explore unavailable."
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

        let jsonDecodeStartedAt = MagnistraFeedTiming.now()
        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with:
                        data,
                    options:
                        []
                )
        MagnistraFeedTiming.mark("EXPLORE", "JSON_DECODE", jsonDecodeStartedAt)

        guard
            let root =
                object as?
                    [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraExplore",
                code:
                    6403,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Explore unavailable."
                ]
            )
        }

        return root
    }

    static func reelsRoot(
        maxID: String?
    ) throws -> [String: Any]
    {
        let session =
            try loadSession()

        let cursor =
            maxID ?? ""

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
                    "MagnistraExplore",
                code:
                    6400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Explore unavailable."
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
                                                    cursor
                                                        .withCString { maxCursor in
                                                            Int32(
                                                                magnistra_reels_fetch(
                                                                    ca,
                                                                    ua,
                                                                    lang,
                                                                    cookies,
                                                                    csrf,
                                                                    maxCursor
                                                                )
                                                            )
                                                        }
                                                }
                                        }
                                }
                        }
                }

        let httpStatus =
            magnistra_reels_http_status()

        if httpStatus == 401 || httpStatus == 403 || httpStatus == 429 {
            throw NSError(domain: "MagnistraInstagramSafety",
                          code: Int(httpStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                            "Instagram requires attention. Check the official website before retrying."])
        }

        let tlsResult =
            magnistra_reels_tls_verify_result()

        let length =
            Int(
                magnistra_reels_body_length()
            )

        if
            curlCode == 0,
            httpStatus == 400,
            tlsResult == 0,
            length > 0,
            let body =
                magnistra_reels_body()
        {
            let data =
                Data(
                    bytes:
                        body,
                    count:
                        length
                )

            if
                let object =
                    try?
                        MagnistraJSONKit
                            .jsonObject(
                                with:
                                    data,
                                options:
                                    []
                            ),
                let errorRoot =
                    object as?
                        [String: Any],
                let spam =
                    errorRoot["spam"]
                        as? Bool,
                spam
            {
                throw NSError(
                    domain:
                        "MagnistraExplore",
                    code:
                        6401,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Explore temporarily unavailable."
                    ]
                )
            }
        }

        guard
            curlCode == 0,
            httpStatus >= 200,
            httpStatus < 300,
            tlsResult == 0,
            length > 0,
            let body =
                magnistra_reels_body()
        else {
            throw NSError(
                domain:
                    "MagnistraExplore",
                code:
                    6402,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Explore unavailable."
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

        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with:
                        data,
                    options:
                        []
                )

        guard
            let root =
                object as?
                    [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraExplore",
                code:
                    6403,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Explore unavailable."
                ]
            )
        }

        return root
    }
}
