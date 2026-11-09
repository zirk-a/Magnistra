// Overview: Home feed: page request and pagination (post building lives in FeedPostBuilder.swift).
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func loadPage(
        maxID: String?
    ) throws
        -> (
            posts: [MagnistraRealPost],
            nextMaxID: String?
        )
    {
        let networkStageStartedAt = MagnistraFeedTiming.now()
        defer { MagnistraFeedTiming.mark("HOME", "SERVICE_TOTAL", networkStageStartedAt) }

        let session =
            try loadSession()

        guard let caPath =
            Bundle.main.path(
                forResource:
                    "CACert",
                ofType: "pem"
            )
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5010,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        if
            maxID == nil ||
            maxID?.isEmpty == true
        {
            resetTimelineSeenPosts()
        }

        let cursor =
            maxID ?? ""

        let paginationJSON =
            timelinePaginationJSON(
                cursor:
                    cursor
            )

        let curlCode: Int32 =
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
                                    .withCString {
                                        maxIDCString in
                                    paginationJSON
                                        .withCString {
                                            paginationCString in

                                            Int32(
                                                magnistra_transport_fetch_feed(
                                                    ca,
                                                    ua,
                                                    lang,
                                                    cookies,
                                                    csrf,
                                                    maxIDCString,
                                                    paginationCString
                                                )
                                            )
                                        }
                                    }
                            }
                        }
                    }
                }
            }

        guard curlCode == 0 else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5011,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Home feed transport failed."
                ]
            )
        }

        let magnistraSafetyStatus = Int(magnistra_transport_http_status())
        if magnistraSafetyStatus == 401 || magnistraSafetyStatus == 403 {
            throw NSError(
                domain: "MagnistraInstagramSafety",
                code: magnistraSafetyStatus,
                userInfo: [NSLocalizedDescriptionKey:
                    "Instagram requires attention to the account. Check the official Instagram app."]
            )
        }
        if magnistraSafetyStatus == 429 {
            throw NSError(
                domain: "MagnistraInstagramSafety",
                code: 429,
                userInfo: [NSLocalizedDescriptionKey:
                    "Instagram is temporarily limiting requests. Wait before refreshing."]
            )
        }

        guard
            magnistra_transport_http_status()
                == 200,
            magnistra_transport_tls_verify_result()
                == 0
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5012,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not return the Home feed."
                ]
            )
        }

        let bodyLength =
            Int(
                magnistra_transport_body_length()
            )

        guard
            bodyLength > 0,
            let body =
                magnistra_transport_body()
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5013,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Home feed response was empty."
                ]
            )
        }

        let feedData =
            Data(
                bytes: body,
                count: bodyLength
            )

        let jsonDecodeStartedAt = MagnistraFeedTiming.now()
        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with: feedData,
                    options: []
                )
        MagnistraFeedTiming.mark("HOME", "JSON_DECODE", jsonDecodeStartedAt)

        guard
            let root =
                object as? [String: Any],
            let rows =
                root["feed_items"]
                    as? [[String: Any]]
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5014,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Home feed format was not recognized."
                ]
            )
        }

        rememberTimelineRows(
            rows
        )

        var nextMaxID =
            stringValue(
                root["next_max_id"]
            )

        if
            nextMaxID?.isEmpty == true ||
            nextMaxID == maxID
        {
            nextMaxID = nil
        }

        let postBuildStartedAt = MagnistraFeedTiming.now()
        defer { MagnistraFeedTiming.mark("HOME", "POST_BUILD", postBuildStartedAt) }

        var posts:
            [MagnistraRealPost] = []

        let photoQuality =
            MagnistraMediaPreferences
                .photoQuality

        for row in rows {
            if let post = makeFeedPost(from: row, photoQuality: photoQuality) {
                posts.append(post)
            }
        }

        return (
            posts: posts,
            nextMaxID: nextMaxID
        )
    }
}
