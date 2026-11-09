// Overview: Timeline state: seen posts and feed view info payloads.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func exploreNextMaxID(
        _ value: Any,
        excluding previous:
            String?
    ) -> String? {
        if
            let object =
                value as?
                    [String: Any]
        {
            if
                let next =
                    stringValue(
                        object[
                            "next_max_id"
                        ]
                    ),
                !next.isEmpty,
                next != previous
            {
                return next
            }

            for child in object.values {
                if
                    let next =
                        exploreNextMaxID(
                            child,
                            excluding:
                                previous
                        )
                {
                    return next
                }
            }

            return nil
        }

        if
            let array =
                value as?
                    [Any]
        {
            for child in array {
                if
                    let next =
                        exploreNextMaxID(
                            child,
                            excluding:
                                previous
                        )
                {
                    return next
                }
            }
        }

        return nil
    }

    static func timelineMediaID(
        from row:
            [String: Any]
    ) -> String? {
        let media =
            timelineDisplayMedia(
                from:
                    row
            )

        if let value =
            media["id"] as? String,
            !value.isEmpty
        {
            return value
        }

        return stringValue(
            media["pk"]
        )
    }

    static func resetTimelineSeenPosts() {
        timelineSeenMediaIDs
            .removeAll(
                keepingCapacity:
                    true
            )
    }

    static func rememberTimelineRows(
        _ rows:
            [[String: Any]]
    ) {
        var known =
            Set(
                timelineSeenMediaIDs
            )

        for row in rows {
            guard
                let mediaID =
                    timelineMediaID(
                        from:
                            row
                    ),
                !mediaID.isEmpty,
                !known.contains(
                    mediaID
                )
            else {
                continue
            }

            timelineSeenMediaIDs
                .append(
                    mediaID
                )

            known.insert(
                mediaID
            )
        }

        if
            timelineSeenMediaIDs.count >
            timelineSeenMediaLimit
        {
            timelineSeenMediaIDs =
                Array(
                    timelineSeenMediaIDs
                        .suffix(
                            timelineSeenMediaLimit
                        )
                )
        }
    }

    static func timelineSeenPostsPayload()
        -> String
    {
        return timelineSeenMediaIDs
            .joined(
                separator:
                    ","
            )
    }

    static func timelineFeedViewInfoPayload()
        -> String
    {
        if timelineSeenMediaIDs.isEmpty {
            return "[]"
        }

        let timestamp =
            Int64(
                Date()
                    .timeIntervalSince1970 *
                1000.0
            )

        var objects:
            [[String: Any]] = []

        for mediaID in
            timelineSeenMediaIDs
        {
            objects.append(
                [
                    "media_id":
                        mediaID,
                    "version":
                        24,
                    "media_pct":
                        1.0,
                    "time_info":
                        [
                            "10": 1,
                            "25": 1,
                            "50": 1,
                            "75": 1
                        ],
                    "latest_timestamp":
                        timestamp
                ]
            )
        }

        guard
            let data =
                try? MagnistraJSONKit
                    .data(
                        withJSONObject:
                            objects,
                        options:
                            []
                    ),
            let text =
                String(
                    data:
                        data,
                    encoding:
                        .utf8
                )
        else {
            return "[]"
        }

        return text
    }

    static func timelinePaginationJSON(
        cursor: String
    ) -> String {
        if cursor.isEmpty {
            return ""
        }

        let requestTime =
            String(
                Int64(
                    Date()
                        .timeIntervalSince1970 *
                    1000.0
                )
            )

        let seenPosts =
            timelineSeenPostsPayload()

        let feedViewInfo =
            timelineFeedViewInfoPayload()

        var object:
            [String: Any] = [
                "app_start_time":
                    requestTime,
                "client_recorded_request_time_ms":
                    requestTime,
                "has_camera_permission":
                    "1",
                "feed_view_info":
                    feedViewInfo,
                "client_seen_store_media_list":
                    "",
                "client_view_state_media_list":
                    "[]",
                "feed_reshare_info":
                    "",
                "reason":
                    "pagination",
                "is_pull_to_refresh":
                    "0",
                "is_prefetch":
                    "0",
                "max_id":
                    cursor,
                "organic_realtime_information":
                    "[]",
                "pagination_source":
                    "feed_recs",
                "triggered_by_visible_spinner":
                    "false",
                "battery_level":
                    100,
                "include_attribution_ui_data":
                    "true"
            ]

        if !seenPosts.isEmpty {
            object["seen_posts"] =
                seenPosts
        }

        guard
            let data =
                try? MagnistraJSONKit
                    .data(
                        withJSONObject:
                            object,
                        options:
                            []
                    ),
            let text =
                String(
                    data:
                        data,
                    encoding:
                        .utf8
                )
        else {
            return ""
        }

        return text
    }
}
