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

        // Home uses browser-like domain/path cookie scoping; do not mutate
        // persisted credentials or any shared authentication state.
        let homeContext = homeWWWSessionContext(
            fallbackCookies: session.cookieHeader,
            fallbackCSRF: session.csrfToken)
        NSLog("MAGNISTRA_HOME_SESSION_SCOPE source=%@ device=%@",
            homeContext.source, homeContext.deviceSource)
        let cursor = maxID ?? ""
        // H3 verified request key structure (21 Nov 2026), including
        // first=12 and the two Relay feature flags. H3 masks sensitive
        // parameter values, so device_id and variant remain experimental.
        // The minimal five-field data shape was observed with HTTP 200.
        let inputs = homeGraphQLVariables(cursor: cursor,
            deviceID: homeContext.deviceID)
        let inputData = try MagnistraJSONKit.data(withJSONObject: inputs, options: [])
        guard let variablesJSON = String(data: inputData, encoding: .utf8) else {
            throw NSError(domain: "MagnistraHome", code: 5016,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid Home query inputs."])
        }
        let curlCode: Int32 = caPath.withCString { ca in
            session.userAgent.withCString { ua in
                session.language.withCString { lang in
                    homeContext.cookies.withCString { cookies in
                        homeContext.csrf.withCString { csrf in
                            variablesJSON.withCString { vars in
                                Int32(magnistra_home_graphql_fetch(
                                    ca, ua, lang, cookies, csrf, vars))
                            }
                        }
                    }
                }
            }
        }

        // Safe native-context presence flags only, never private values.
        NSLog("MAGNISTRA_HOME_NATIVE_CONTEXT bootstrap_http=%ld bootstrap_bytes=%lld form_bytes=%lld flags=%lu",
            magnistra_home_graphql_bootstrap_status(),
            magnistra_home_graphql_bootstrap_bytes(),
            magnistra_home_graphql_post_bytes(),
            magnistra_home_graphql_ctx_flags())
        NSLog("MAGNISTRA_HOME_COOKIE_CONTEXT seeded=%d after_get=%d csrf_changed=%d seed_failed=%d",
            magnistra_home_graphql_cookie_seeded(),
            magnistra_home_graphql_cookie_after_get(),
            magnistra_home_graphql_cookie_csrf_changed(),
            magnistra_home_graphql_cookie_seed_failed())
        NSLog("MAGNISTRA_HOME_BROWSER_HEADERS claim_ajax_flags=%d",
            magnistra_home_graphql_browser_header_flags())
        if curlCode != 0 {
            NSLog("MAGNISTRA_HOME_GRAPHQL stage=%ld transport_rc=%ld http=%ld", 
                Int(magnistra_home_graphql_stage()), Int(curlCode), magnistra_home_graphql_http_status())
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

        let magnistraSafetyStatus = Int(magnistra_home_graphql_http_status())
        NSLog("MAGNISTRA_HOME_GRAPHQL http=%ld body_bytes=%lld", 
            magnistraSafetyStatus, magnistra_home_graphql_body_length())
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
            magnistra_home_graphql_http_status()
                == 200,
            magnistra_home_graphql_tls_verify_result()
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
                magnistra_home_graphql_body_length()
            )

        guard
            bodyLength > 0,
            let body =
                magnistra_home_graphql_body()
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

        guard let root = object as? [String: Any] else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5014,
                userInfo: [NSLocalizedDescriptionKey:
                    "Home feed JSON root was not recognized."]
            )
        }
        // GraphQL may reject queries with HTTP 200. Log fixed categories and
        // numeric server codes only: never the raw error message or user data.
        if let errors = root["errors"] as? [Any], !errors.isEmpty {
            NSLog("MAGNISTRA_HOME_GRAPHQL application_errors_count=%ld", errors.count)
            // The R11 fallback incorrectly reused the Explore route.
            for (index, error) in errors.prefix(8).enumerated() {
                guard let item = error as? [String: Any] else {
                    NSLog("MAGNISTRA_HOME_NATIVE_ERROR shape=%@", error is String ? "STRING" : "NON_DICTIONARY")
                    continue
                }
                let message = (item["message"] as? String ?? "").lowercased()
                let category: String
                if message.contains("missing_required_variable") || message.contains("missing required") {
                    category = "MISSING_VARIABLE"
                } else if message.contains("variable") || message.contains("validation") || message.contains("argument") {
                    category = "VARIABLE_VALIDATION"
                } else if message.contains("doc_id") || message.contains("document") || message.contains("query not found") {
                    category = "DOCUMENT"
                } else if message.contains("csrf") || message.contains("dtsg") || message.contains("token") {
                    category = "CSRF_TOKEN"
                } else if message.contains("login") || message.contains("authentication") || message.contains("permission") {
                    category = "AUTHORIZATION"
                } else if message.contains("rate") || message.contains("limit") || message.contains("thrott") {
                    category = "RATE_LIMIT"
                } else if message.contains("execution") || message.contains("server error") {
                    category = "SERVER_EXECUTION"
                } else {
                    category = "OTHER"
                }
                // Never output raw messages. The following exact words reveal
                // error class while excluding arbitrary private text.
                let safeTerms: [String] = [
                    "graphql", "execution", "server", "failed", "error", "unknown",
                    "invalid", "missing", "required", "variable", "document", "token",
                    "csrf", "authentication", "permission", "unauthorized", "login",
                    "rate", "limit", "expired", "signature", "operation", "query",
                    "not", "found", "null", "field", "internal", "unexpected",
                    "user", "viewer", "forbidden", "denied", "unsupported",
                    "exception", "temporary", "try", "again", "something", "wrong"
                ]
                let words = message.components(separatedBy: CharacterSet.alphanumerics.inverted)
                let safeMatches = safeTerms.filter { words.contains($0) }
                let errorKeys = item.keys.filter {
                    ["message", "code", "extensions", "path", "locations", "severity", "type"].contains($0)
                }.sorted().joined(separator: ",")
                let ext = item["extensions"] as? [String: Any] ?? [:]
                let extensionKeys = ext.keys.filter {
                    ["code", "error_type", "severity", "is_transient", "fbtrace_id"].contains($0)
                }.sorted().joined(separator: ",")
                NSLog("MAGNISTRA_HOME_NATIVE_ERROR shape=%@ extensions=%@ words=%@ chars=%ld",
                    errorKeys, extensionKeys, safeMatches.joined(separator: ","), message.count)
                let serverCode = intValue(item["code"]) ?? -1
                NSLog("MAGNISTRA_HOME_GRAPHQL error_index=%ld category=%@ code=%ld",
                    index, category, serverCode)
            }
            throw NSError(domain: "MagnistraHome", code: 5017,
                userInfo: [NSLocalizedDescriptionKey: "Instagram rejected the Home query."])
        }

        let rows: [[String: Any]]
        var nextMaxID: String?
        if let nativeRows = root["feed_items"] as? [[String: Any]] {
            rows = nativeRows
            nextMaxID = stringValue(root["next_max_id"])
            if nextMaxID?.isEmpty == true || nextMaxID == maxID {
                nextMaxID = nil
            }
        } else if let page = homeGraphQLPage(root: root, previousCursor: maxID) {
            rows = page.rows
            nextMaxID = page.nextCursor
        } else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5014,
                userInfo: [NSLocalizedDescriptionKey:
                    "Home feed format was not recognized."]
            )
        }

        NSLog("MAGNISTRA_HOME_GRAPHQL parsed_rows=%ld cursor_present=%d",
            rows.count, nextMaxID == nil ? 0 : 1)
        rememberTimelineRows(rows)

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
