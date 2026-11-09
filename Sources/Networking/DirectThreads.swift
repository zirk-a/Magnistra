// Overview: Direct: resolving recipients and loading a thread.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func resolveDirectForRecipient(
        userID: String
    ) throws -> MagnistraDirectThreadSummary? {
        guard !userID.isEmpty,
            userID.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return nil
        }

        let form = "recipient_users=%5B%22" + userID + "%22%5D"
        let root = try postActionRoot(
            relativePath: "/api/v1/direct_v2/threads/get_by_participants/",
            postBody: form)
        let thread = (root["thread"] as? [String: Any]) ?? root
        let id = stringValue(thread["thread_fbid"]) ??
                 stringValue(thread["thread_id"]) ?? ""
        guard !id.isEmpty, id.rangeOfCharacter(
            from: CharacterSet.decimalDigits.inverted) == nil else { return nil }
        let seq = Int(stringValue(thread["min_uq_seq_id"]) ?? "") ?? 0
        let username = (thread["thread_title"] as? String) ?? ""
        return MagnistraDirectThreadSummary(
            threadFBID: id, minUQSeqID: seq,
            title: username.isEmpty ? "Direct" : username,
            username: "", snippet: "", avatarURL: nil,
            lastActivityMilliseconds: 0, isUnread: false,
            participantUserIDs: [userID], isGroupConversation: false)
    }

    static func loadDirectThread(
        threadFBID: String,
        olderAfterCursor: String? = nil
    ) throws -> MagnistraDirectThreadPayload {
        guard
            !threadFBID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6910,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Direct thread identifier is missing."
                ]
            )
        }

        let root: [String: Any]
        if let afterCursor = olderAfterCursor {

            let variables: [String: Any] = [
                "__relay_internal__pv__IGDInitialMessagePageCountrelayprovider": 20,
                "id": threadFBID,
                "after": afterCursor,
                "before": NSNull(),
                "first": 20,
                "last": NSNull(),
                "newer_than_message_id": NSNull(),
                "older_than_message_id": NSNull()
            ]
            root = try exploreSearchGraphQLRoot(
                variables: variables,
                docID: "29380270148264352",
                friendlyName: "IGDMessageListOffMsysQuery"
            )
        } else {
        let variables:
            [String: Any] = [
                "__relay_internal__pv__IGDEnableOffMsysChatThemesQErelayprovider":
                    false,
                "__relay_internal__pv__IGDInitialMessagePageCountrelayprovider":
                    20,
                "min_uq_seq_id":
                    NSNull(),
                "thread_fbid":
                    threadFBID
            ]

        root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "28047224604940200",
                friendlyName:
                    "IGDThreadDetailQuery"
            )

        }

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let wrapper =
                data[olderAfterCursor == nil ? "get_slide_thread_nullable" : "fetch__SlideThread"] as? [String: Any],
            let thread =
                wrapper[
                    "as_ig_direct_thread"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6911,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram Direct thread payload was not recognized."
                ]
            )
        }

        let viewer =
            thread["viewer"]
                as? [String: Any]

        var viewerIdentifiers =
            Set<String>()

        directInsertIdentifier(
            thread[
                "viewer_id"
            ],
            into:
                &viewerIdentifiers
        )

        directInsertIdentifier(
            viewer?[
                "id"
            ],
            into:
                &viewerIdentifiers
        )

        directInsertIdentifier(
            viewer?[
                "interop_messaging_user_fbid"
            ],
            into:
                &viewerIdentifiers
        )

        let viewerIDFromSession = try? postActionActorID()
        directInsertIdentifier(viewerIDFromSession, into: &viewerIdentifiers)

        directInsertIdentifier(viewer?["pk"], into: &viewerIdentifiers)
        directInsertIdentifier(viewer?["igid"], into: &viewerIdentifiers)

        let identity =
            directThreadDisplayIdentity(
                thread
            )

        let messageGraph =
            thread[
                "slide_messages"
            ] as? [String: Any]

        let edges =
            messageGraph?[
                "edges"
            ] as? [[String: Any]] ??
            []

        var messages:
            [MagnistraDirectMessage] =
                []

        var seen =
            Set<String>()

        for edge in edges {
            guard
                let node =
                    edge["node"]
                        as? [String: Any]
            else {
                continue
            }

            let timestamp =
                directMilliseconds(
                    node[
                        "timestamp_ms"
                    ]
                )

            let messageID =
                stringValue(
                    node[
                        "message_id"
                    ]
                ) ??
                stringValue(
                    node["id"]
                ) ??
                (
                    "time:" +
                    String(
                        timestamp
                    )
                )

            if
                seen.contains(
                    messageID
                )
            {
                continue
            }

            seen.insert(
                messageID
            )

            let sender =
                node[
                    "sender"
                ] as? [String: Any]

            let senderUser =
                sender?[
                    "user_dict"
                ] as? [String: Any]

            var senderIdentifiers =
                Set<String>()

            directInsertIdentifier(
                node[
                    "sender_fbid"
                ],
                into:
                    &senderIdentifiers
            )

            directInsertIdentifier(
                sender?[
                    "id"
                ],
                into:
                    &senderIdentifiers
            )

            directInsertIdentifier(
                sender?[
                    "igid"
                ],
                into:
                    &senderIdentifiers
            )

            directInsertIdentifier(
                senderUser?[
                    "id"
                ],
                into:
                    &senderIdentifiers
            )

            directInsertIdentifier(
                senderUser?[
                    "interop_messaging_user_fbid"
                ],
                into:
                    &senderIdentifiers
            )

            directInsertIdentifier(sender?["pk"], into: &senderIdentifiers)
            directInsertIdentifier(senderUser?["pk"], into: &senderIdentifiers)

            let presentation =
                directMessagePresentation(
                    node
                )

            let mgSenderID = stringValue(node["sender_fbid"]) ??
                stringValue(sender?["id"]) ?? stringValue(senderUser?["id"]) ?? ""
            let mgSenderName = (senderUser?["full_name"] as? String) ??
                (sender?["full_name"] as? String) ??
                (senderUser?["username"] as? String) ??
                (sender?["username"] as? String) ?? mgSenderID

            messages.append(
                MagnistraDirectMessage(
                    messageID:
                        messageID,
                    text:
                        presentation.text,
                    detailText:
                        presentation.detail,
                    previewURL:
                        presentation.previewURL,
                    contentType:
                        presentation.contentType,
                    timestampMilliseconds:
                        timestamp,
                    isOutgoing:
                        directIdentifierSetsIntersect(
                            viewerIdentifiers,
                            senderIdentifiers
                        ),
                    audioURL:
                        presentation.audioURL,
                    audioDurationMilliseconds:
                        presentation.audioDurationMilliseconds,
                    mediaURL:
                        presentation.mediaURL,
                    targetURL:
                        presentation.targetURL,
                    mediaKind:
                        presentation.mediaKind,
                    audioWaveform:
                        presentation.audioWaveform,
                    mediaAspectRatio:
                        presentation.mediaAspectRatio,
                    senderID: mgSenderID,
                    senderName: mgSenderName
                )
            )
        }

        messages.sort {
            if
                $0.timestampMilliseconds ==
                $1.timestampMilliseconds
            {
                return
                    $0.messageID <
                    $1.messageID
            }

            return
                $0.timestampMilliseconds <
                $1.timestampMilliseconds
        }

        let pageInfo =
            messageGraph?[
                "page_info"
            ] as? [String: Any]

        let startCursor =
            stringValue(pageInfo?["end_cursor"]) ??
            stringValue(pageInfo?["start_cursor"])
        let hasPrevious =
            (boolValue(pageInfo?["has_next_page"]) ??
             boolValue(pageInfo?["has_previous_page"]) ?? false) &&
            startCursor?.isEmpty == false

        return
            MagnistraDirectThreadPayload(
                threadFBID:
                    threadFBID,
                title:
                    identity.title,
                messages:
                    messages,
                startCursor:
                    hasPrevious
                        ? startCursor
                        : nil,
                hasPreviousPage:
                    hasPrevious
            )
    }
}
