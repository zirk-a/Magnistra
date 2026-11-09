// Overview: Direct inbox: loading threads and thread identity helpers.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func directInsertIdentifier(
        _ value: Any?,
        into set:
            inout Set<String>
    ) {
        guard
            let string =
                stringValue(
                    value
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
            !string.isEmpty
        else {
            return
        }

        set.insert(
            string
        )
    }

    static func directIdentifierSetsIntersect(
        _ lhs: Set<String>,
        _ rhs: Set<String>
    ) -> Bool {
        for value in lhs {
            if
                rhs.contains(
                    value
                )
            {
                return true
            }
        }

        return false
    }

    static func directThreadDisplayIdentity(
        _ thread: [String: Any]
    ) -> (
        title: String,
        username: String,
        avatarURL: String?
    ) {
        let viewer =
            thread["viewer"]
                as? [String: Any]

        let viewerID =
            stringValue(
                thread["viewer_id"]
            ) ??
            stringValue(
                viewer?["id"]
            ) ??
            ""

        let users =
            thread["users"]
                as? [[String: Any]] ??
            []

        var participant:
            [String: Any]? =
                nil

        for user in users {
            let userID =
                stringValue(
                    user["id"]
                ) ??
                stringValue(
                    user["fbid_v2"]
                ) ??
                ""

            if
                viewerID.isEmpty ||
                userID != viewerID
            {
                participant =
                    user
                break
            }
        }

        if participant == nil {
            participant =
                users.first
        }

        let username =
            (
                participant?[
                    "username"
                ] as? String
            ) ?? ""

        let fullName =
            (
                participant?[
                    "full_name"
                ] as? String
            ) ?? ""

        let rawTitle =
            (
                thread[
                    "thread_title"
                ] as? String
            )?
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            ) ?? ""

        let title:
            String

        if !rawTitle.isEmpty {
            title =
                rawTitle
        } else if !fullName.isEmpty {
            title =
                fullName
        } else if !username.isEmpty {
            title =
                username
        } else {
            title =
                "Direct"
        }

        let threadAvatar =
            (
                thread[
                    "thread_image_url"
                ] as? String
            )?
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        let participantAvatar =
            (
                participant?[
                    "profile_pic_url"
                ] as? String
            )?
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        let avatarURL:
            String?

        if
            let value =
                threadAvatar,
            !value.isEmpty
        {
            avatarURL =
                value
        } else if
            let value =
                participantAvatar,
            !value.isEmpty
        {
            avatarURL =
                value
        } else {
            avatarURL =
                nil
        }

        return (
            title,
            username,
            avatarURL
        )
    }

    static func loadDirectInbox()
        throws -> MagnistraDirectInboxPage
    {
        let variables:
            [String: Any] = [
                "__relay_internal__pv__IGDIsProfessionalAccountGKrelayprovider":
                    false,
                "__relay_internal__pv__IGDMaxUnreadMessagesCountrelayprovider":
                    5,
                "__relay_internal__pv__IGDPinnedThreadsRenderEnabledGKrelayprovider":
                    true,
                "__relay_internal__pv__IGDThreadListActionsEnabledGKrelayprovider":
                    true,
                "device_id_for_iris_subscription":
                    directDeviceID()
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "28534349112836579",
                friendlyName:
                    "PolarisDirectInboxMobileQuery"
            )

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let mailbox =
                data[
                    "get_slide_mailbox_for_iris_subscription"
                ] as? [String: Any],
            let graph =
                mailbox[
                    "threads_by_folder"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6900,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Direct inbox payload was not recognized."
                ]
            )
        }

        let minUQSeqID =
            Int(
                stringValue(
                    mailbox[
                        "iris_inactive_subscription_uq_seq_id"
                    ]
                ) ??
                ""
            ) ??
            0

        let edges =
            graph["edges"]
                as? [[String: Any]] ??
            []

        var threads:
            [MagnistraDirectThreadSummary] =
                []

        var seen =
            Set<String>()

        for edge in edges {
            guard
                let node =
                    edge["node"]
                        as? [String: Any],
                let thread =
                    node[
                        "as_ig_direct_thread"
                    ] as? [String: Any]
            else {
                continue
            }

            let threadFBID =
                stringValue(
                    thread[
                        "thread_fbid"
                    ]
                ) ??
                stringValue(
                    thread[
                        "thread_id"
                    ]
                ) ??
                stringValue(
                    thread["id"]
                ) ??
                ""

            if
                threadFBID.isEmpty ||
                seen.contains(
                    threadFBID
                )
            {
                continue
            }

            seen.insert(
                threadFBID
            )

            let identity =
                directThreadDisplayIdentity(
                    thread
                )

            let viewer = thread["viewer"] as? [String: Any]
            let viewerID =
                stringValue(thread["viewer_id"]) ??
                stringValue(viewer?["id"]) ?? ""
            let users = thread["users"] as? [[String: Any]] ?? []
            var participantIDs: [String] = []
            for user in users {
                for key in ["id", "pk", "instagram_user_id", "fbid_v2"] {
                    guard let value = stringValue(user[key]),
                          !value.isEmpty, value != viewerID else { continue }
                    if !participantIDs.contains(value) { participantIDs.append(value) }
                }
            }

            let messageGraph =
                thread[
                    "slide_messages"
                ] as? [String: Any]

            let messageEdges =
                messageGraph?[
                    "edges"
                ] as? [[String: Any]] ??
                []

            var snippet =
                ""

            var snippetTime =
                0.0

            for messageEdge in messageEdges {
                guard
                    let message =
                        messageEdge[
                            "node"
                        ] as? [String: Any]
                else {
                    continue
                }

                let timestamp =
                    directMilliseconds(
                        message[
                            "timestamp_ms"
                        ]
                    )

                if
                    snippet.isEmpty ||
                    timestamp >=
                        snippetTime
                {
                    snippet =
                        directMessageText(
                            message
                        )

                    snippetTime =
                        timestamp
                }
            }

            let activityTime =
                max(
                    directMilliseconds(
                        thread[
                            "last_activity_timestamp_ms"
                        ]
                    ),
                    snippetTime
                )

            threads.append(
                MagnistraDirectThreadSummary(
                    threadFBID:
                        threadFBID,
                    minUQSeqID:
                        minUQSeqID,
                    title:
                        identity.title,
                    username:
                        identity.username,
                    snippet:
                        snippet.isEmpty
                            ? "Message"
                            : snippet,
                    avatarURL:
                        identity.avatarURL,
                    lastActivityMilliseconds:
                        activityTime,
                    isUnread:
                        boolValue(
                            thread[
                                "marked_as_unread"
                            ]
                        ) ?? false,
                    participantUserIDs:
                        participantIDs,
                    isGroupConversation:
                        (boolValue(thread["is_group"]) ?? false) || (users.count > 2)
                )
            )
        }

        threads.sort {
            $0.lastActivityMilliseconds >
            $1.lastActivityMilliseconds
        }

        let pageInfo =
            graph["page_info"]
                as? [String: Any]

        let endCursor =
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
            endCursor?.isEmpty == false

        return
            MagnistraDirectInboxPage(
                threads:
                    threads,
                endCursor:
                    hasNext
                        ? endCursor
                        : nil,
                hasNextPage:
                    hasNext
            )
    }

    static func directOfflineThreadingID()
        -> String
    {
        let milliseconds =
            Int64(
                Date()
                    .timeIntervalSince1970 *
                1000.0
            )

        let suffix =
            Int64(
                arc4random_uniform(
                    1000000
                )
            )

        return
            String(
                milliseconds *
                1000000 +
                suffix
            )
    }

    static func directThreadIGID(
        threadFBID:
            String,
        minUQSeqID:
            Int
    ) throws -> String {
        let variables:
            [String: Any] = [
                "min_uq_seq_id":
                    max(
                        0,
                        minUQSeqID
                    ),
                "thread_fbid":
                    threadFBID
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "37896212640025711",
                friendlyName:
                    "IGDInboxHeaderOffMsysQuery"
            )

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let wrapper =
                data[
                    "get_slide_thread_nullable"
                ] as? [String: Any],
            let thread =
                wrapper[
                    "as_ig_direct_thread"
                ] as? [String: Any],
            let threadIGID =
                stringValue(
                    thread[
                        "thread_igid"
                    ]
                ),
            !threadIGID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6920,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not provide the Direct thread routing identifier."
                ]
            )
        }

        return
            threadIGID
    }

    static func directAttachmentIdentifier(
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
            let dictionary =
                value as?
                    [String: Any]
        {
            let keys = [
                "image_id",
                "video_id",
                "audio_id",
                "attachmentID",
                "attachment_id",
                "file_id",
                "fbid"
            ]

            for key in keys {
                if
                    let identifier =
                        stringValue(
                            dictionary[
                                key
                            ]
                        ),
                    !identifier.isEmpty
                {
                    return identifier
                }
            }

            for nested in dictionary.values {
                if
                    let identifier =
                        directAttachmentIdentifier(
                            nested,
                            depth:
                                depth + 1
                        )
                {
                    return identifier
                }
            }
        } else if
            let array =
                value as?
                    [Any]
        {
            for nested in array {
                if
                    let identifier =
                        directAttachmentIdentifier(
                            nested,
                            depth:
                                depth + 1
                        )
                {
                    return identifier
                }
            }
        }

        return nil
    }

    static func directMercuryAttachmentIdentifier(
        _ root:
            [String: Any]
    ) -> String? {
        guard
            let payload =
                root[
                    "payload"
                ] as?
                    [String: Any]
        else {
            return nil
        }

        if
            let metadata =
                payload[
                    "metadata"
                ]
        {
            if
                let identifier =
                    directAttachmentIdentifier(
                        metadata
                    ),
                !identifier.isEmpty
            {
                return
                    identifier
            }
        }

        if
            let attachment =
                payload[
                    "attachment"
                ]
        {
            if
                let identifier =
                    directAttachmentIdentifier(
                        attachment
                    ),
                !identifier.isEmpty
            {
                return
                    identifier
            }
        }

        return nil
    }
}
