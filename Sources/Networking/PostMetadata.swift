// Overview: Post action metadata: identifiers and lookups used by post actions.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func postActionMediaPK(
        _ mediaID: String
    ) -> String {
        return
            mediaID
                .components(
                    separatedBy:
                        "_"
                )
                .first ??
            mediaID
    }

    static func postActionActorID()
        throws -> String
    {
        let session =
            try loadSession()

        for rawPair in
            session.cookieHeader
                .components(
                    separatedBy:
                        ";"
                )
        {
            let pair =
                rawPair.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

            if pair.hasPrefix(
                "ds_user_id="
            ) {
                let value =
                    (pair as NSString)
                        .substring(
                            from:
                                "ds_user_id=".count
                        )

                if
                    !value.isEmpty,
                    value.rangeOfCharacter(
                        from:
                            CharacterSet
                                .decimalDigits
                                .inverted
                    ) == nil
                {
                    return value
                }
            }
        }

        throw NSError(
            domain:
                "MagnistraPostAction",
            code:
                9400,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Instagram account ID is missing from the imported session."
            ]
        )
    }

    static func postActionNextMutationID()
        -> String
    {
        postActionMetadataLock.lock()

        postActionMutationCounter += 1

        let value =
            postActionMutationCounter

        postActionMetadataLock.unlock()

        return
            String(
                value
            )
    }

    static func postActionFindString(
        key: String,
        in value: Any,
        depth: Int = 0
    ) -> String? {
        let isMetricTrackingEnabled = depth == 0 && MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("META_STRING", metricStartedAt) } }

        if depth > 8 {
            return nil
        }

        if let dictionary =
            value as? [String: Any]
        {
            if
                let direct =
                    stringValue(
                        dictionary[key]
                    ),
                !direct.isEmpty
            {
                return direct
            }

            for (branchKey, child) in dictionary {
                if (branchKey == "image_versions2" || branchKey == "video_versions") &&
                    MagnistraExploreCounters.active {
                    continue
                }
                if let found =
                    postActionFindString(
                        key:
                            key,
                        in:
                            child,
                        depth:
                            depth + 1
                    )
                {
                    return found
                }
            }

            return nil
        }

        if let array =
            value as? [Any]
        {
            for child in array {
                if let found =
                    postActionFindString(
                        key:
                            key,
                        in:
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

    static func postActionFindInt(
        key: String,
        in value: Any,
        depth: Int = 0
    ) -> Int? {
        let isMetricTrackingEnabled = depth == 0 && MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("META_INTEGER", metricStartedAt) } }

        if depth > 10 {
            return nil
        }

        if let dictionary =
            value as? [String: Any]
        {
            if let direct =
                intValue(
                    dictionary[key]
                )
            {
                return direct
            }

            for (branchKey, child) in dictionary {
                if (branchKey == "image_versions2" || branchKey == "video_versions") &&
                    MagnistraExploreCounters.active {
                    continue
                }
                if let found =
                    postActionFindInt(
                        key:
                            key,
                        in:
                            child,
                        depth:
                            depth + 1
                    )
                {
                    return found
                }
            }

            return nil
        }

        if let array =
            value as? [Any]
        {
            for child in array {
                if let found =
                    postActionFindInt(
                        key:
                            key,
                        in:
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

    static func postActionFindDictionary(
        key: String,
        in value: Any,
        depth: Int = 0
    ) -> [String: Any]? {
        let isMetricTrackingEnabled = depth == 0 && MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("META_DICTIONARY", metricStartedAt) } }

        if depth > 12 {
            return nil
        }

        if let dictionary =
            value as? [String: Any]
        {
            if let direct =
                dictionary[key]
                    as? [String: Any]
            {
                return direct
            }

            for (branchKey, child) in dictionary {
                if (branchKey == "image_versions2" || branchKey == "video_versions") &&
                    MagnistraExploreCounters.active {
                    continue
                }
                if let found =
                    postActionFindDictionary(
                        key:
                            key,
                        in:
                            child,
                        depth:
                            depth + 1
                    )
                {
                    return found
                }
            }

            return nil
        }

        if let array =
            value as? [Any]
        {
            for child in array {
                if let found =
                    postActionFindDictionary(
                        key:
                            key,
                        in:
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

    static func postActionFindRepostNoteID(
        in value: Any,
        actorID: String,
        depth: Int = 0
    ) -> String? {
        let isMetricTrackingEnabled = depth == 0 && MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("META_REPOST", metricStartedAt) } }

        if depth > 12 {
            return nil
        }

        if let dictionary =
            value as? [String: Any]
        {
            if
                let notes =
                    dictionary[
                        "media_notes"
                    ] as? [String: Any],
                let items =
                    notes[
                        "items"
                    ] as? [[String: Any]]
            {
                for item in items {
                    let user =
                        item[
                            "user"
                        ] as? [String: Any]

                    let userID =
                        stringValue(
                            item[
                                "user_id"
                            ]
                        ) ??
                        stringValue(
                            user?[
                                "id"
                            ]
                        ) ??
                        stringValue(
                            user?[
                                "pk"
                            ]
                        ) ??
                        ""

                    let style =
                        intValue(
                            item[
                                "note_style"
                            ]
                        )

                    if
                        userID == actorID,
                        (
                            style == nil ||
                            style == 13
                        ),
                        let noteID =
                            stringValue(
                                item[
                                    "id"
                                ]
                            ),
                        !noteID.isEmpty
                    {
                        return noteID
                    }
                }
            }

            let directStyle =
                intValue(
                    dictionary[
                        "note_style"
                    ]
                )

            let directUser =
                stringValue(
                    dictionary[
                        "user_id"
                    ]
                ) ??
                (
                    (
                        dictionary[
                            "user"
                        ] as? [String: Any]
                    ).flatMap {
                        stringValue(
                            $0[
                                "id"
                            ]
                        ) ??
                        stringValue(
                            $0[
                                "pk"
                            ]
                        )
                    }
                )

            if
                (
                    directStyle == 13 ||
                    dictionary[
                        "note_response_info"
                    ] != nil
                ),
                (
                    directUser == nil ||
                    directUser == actorID
                ),
                let directID =
                    stringValue(
                        dictionary[
                            "id"
                        ]
                    ) ??
                    stringValue(
                        dictionary[
                            "note_id"
                        ]
                    ),
                !directID.isEmpty
            {
                return directID
            }

            for (branchKey, child) in dictionary {
                if (branchKey == "image_versions2" || branchKey == "video_versions") &&
                    MagnistraExploreCounters.active {
                    continue
                }
                if let found =
                    postActionFindRepostNoteID(
                        in:
                            child,
                        actorID:
                            actorID,
                        depth:
                            depth + 1
                    )
                {
                    return found
                }
            }

            return nil
        }

        if let array =
            value as? [Any]
        {
            for child in array {
                if let found =
                    postActionFindRepostNoteID(
                        in:
                            child,
                        actorID:
                            actorID,
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

    static func postActionShortcode(
        mediaID: String
    ) -> String? {
        let raw =
            postActionMediaPK(
                mediaID
            )

        guard var value =
            UInt64(raw)
        else {
            return nil
        }

        let alphabet =
            Array(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            )

        var chars:
            [Character] = []

        repeat {
            let index =
                Int(
                    value %
                    64
                )

            chars.append(
                alphabet[index]
            )

            value /=
                64
        } while value > 0

        return
            String(
                chars.reversed()
            )
    }

    static func postActionLoadViewerRepostNoteID(
        mediaID: String,
        actorID: String
    ) throws -> String? {
        guard
            let shortcode =
                postActionShortcode(
                    mediaID:
                        mediaID
                ),
            !shortcode.isEmpty
        else {
            return nil
        }

        let variables:
            [String: Any] = [
                "shortcode":
                    shortcode,
                "__relay_internal__pv__PolarisMultiCaptionCarouselEnabledrelayprovider":
                    false,
                "__relay_internal__pv__PolarisShortDramaEnabledrelayprovider":
                    false
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "29560628263526992",
                friendlyName:
                    "PolarisPostRootQuery"
            )

        return
            postActionFindRepostNoteID(
                in:
                    root,
                actorID:
                    actorID
            )
    }

    static func magnistraIndexedRepostNoteID(
        _ index: MagnistraMetadataIndex?,
        actorID: String
    ) -> String? {
        guard let index = index else { return nil }
        for candidate in index.repostCandidates {
            if candidate.anonymousAllowed {
                if candidate.userID == nil || candidate.userID == actorID {
                    return candidate.noteID
                }
            } else if candidate.userID == actorID {
                return candidate.noteID
            }
        }
        return nil
    }

static func magnistraBuildMetadataIndex(
        _ value: Any
    ) -> MagnistraMetadataIndex {
        var index = MagnistraMetadataIndex()
        let wantedInts: [String] = ["media_repost_count", "reshare_count", "send_count", "share_count", "shares_count"]
        let wantedStrings: [String] = ["inventory_source", "logging_info_token", "nav_chain", "tracking_token"]

        func visit(_ node: Any, _ depth: Int) {
            if depth > 12 { return }
            if let dictionary = node as? [String: Any] {
                if depth <= 8 {
                    for key in wantedStrings where index.strings[key] == nil {
                        if let text = stringValue(dictionary[key]), !text.isEmpty {
                            index.strings[key] = text
                        }
                    }
                }
                if depth <= 10 {
                    for key in wantedInts where index.ints[key] == nil {
                        if let value = intValue(dictionary[key]) {
                            index.ints[key] = value
                        }
                    }
                }

                if let notes = dictionary["media_notes"] as? [String: Any],
                   let items = notes["items"] as? [[String: Any]] {
                    for item in items {
                        let user = item["user"] as? [String: Any]
                        let userID = stringValue(item["user_id"]) ??
                            stringValue(user?["id"]) ??
                            stringValue(user?["pk"]) ?? ""
                        let style = intValue(item["note_style"])
                        if (style == nil || style == 13),
                           let id = stringValue(item["id"]), !id.isEmpty {
                            index.repostCandidates.append(
                                MagnistraRepostCandidate(userID: userID,
                                                            noteID: id,
                                                            anonymousAllowed: false))
                        }
                    }
                }
                let directStyle = intValue(dictionary["note_style"])
                if directStyle == 13 || dictionary["note_response_info"] != nil {
                    let user = dictionary["user"] as? [String: Any]
                    let directUser = stringValue(dictionary["user_id"]) ??
                        stringValue(user?["id"]) ?? stringValue(user?["pk"])
                    if let id = stringValue(dictionary["id"]) ??
                        stringValue(dictionary["note_id"]), !id.isEmpty {
                        index.repostCandidates.append(
                            MagnistraRepostCandidate(userID: directUser,
                                                        noteID: id,
                                                        anonymousAllowed: true))
                    }
                }
                for (branchKey, child) in dictionary {
                    if branchKey == "image_versions2" || branchKey == "video_versions" {
                        continue
                    }
                    visit(child, depth + 1)
                }
            } else if let array = node as? [Any] {
                for child in array { visit(child, depth + 1) }
            }
        }
        visit(value, 0)
        return index
    }

static func rememberPostActionMetadata(
        mediaID: String,
        userID: String,
        media: [String: Any],
        user: [String: Any],
        context: [String: Any]
    ) {
        let useMetadataIndex = MagnistraExploreCounters.active
        let metadataIndexStartedAt: TimeInterval =
            useMetadataIndex ? MagnistraFeedTiming.now() : 0.0
        let mediaMetadataIndex: MagnistraMetadataIndex? =
            useMetadataIndex ? magnistraBuildMetadataIndex(media) : nil
        let contextMetadataIndex: MagnistraMetadataIndex? =
            useMetadataIndex ? magnistraBuildMetadataIndex(context) : nil
        if useMetadataIndex {
            MagnistraExploreCounters.add("META_INDEX", metadataIndexStartedAt)
        }

        let isMetricTrackingEnabled = MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("META_TOTAL", metricStartedAt) } }

        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        let friendship =
            user[
                "friendship_status"
            ] as?
                [String: Any]

        let following =
            boolValue(
                friendship?[
                    "following"
                ]
            )

        let actorID =
            try?
                postActionActorID()

        let repostNoteID =
            actorID.flatMap { actor -> String? in
                if useMetadataIndex {
                    return magnistraIndexedRepostNoteID(
                        contextMetadataIndex, actorID: actor
                    ) ?? magnistraIndexedRepostNoteID(
                        mediaMetadataIndex, actorID: actor
                    )
                }
                return postActionFindRepostNoteID(
                    in: context, actorID: actor
                ) ?? postActionFindRepostNoteID(
                    in: media, actorID: actor
                )
            }

        let repostCount =
            max(
                0,
                (
                    useMetadataIndex
                        ? mediaMetadataIndex?.ints["media_repost_count"]
                        : postActionFindInt(
                    key:
                        "media_repost_count",
                    in:
                        media
                )
                ) ??
                (
                    useMetadataIndex
                        ? contextMetadataIndex?.ints["media_repost_count"]
                        : postActionFindInt(
                    key:
                        "media_repost_count",
                    in:
                        context
                )
                ) ??
                0
            )

        let shareCount = postActionShareCount(
            media: media,
            context: context,
            useIndex: useMetadataIndex,
            mediaIndex: mediaMetadataIndex,
            contextIndex: contextMetadataIndex
        )

        let metadata = postActionConstructMetadata(
            media: media,
            context: context,
            following: following,
            useIndex: useMetadataIndex,
            mediaIndex: mediaMetadataIndex,
            contextIndex: contextMetadataIndex,
            repostCount: repostCount,
            shareCount: shareCount,
            repostNoteID: repostNoteID
        )

        postActionMetadataLock.lock()

        postActionMetadataByMediaID[
            mediaID
        ] =
            metadata

        postActionMetadataByMediaID[
            mediaPK
        ] =
            metadata

        if
            postActionLikeCountByMediaID[
                mediaID
            ] == nil,
            let likeCount =
                intValue(
                    media[
                        "like_count"
                    ]
                )
        {
            postActionLikeCountByMediaID[
                mediaID
            ] =
                max(
                    0,
                    likeCount
                )

            postActionLikeCountByMediaID[
                mediaPK
            ] =
                max(
                    0,
                    likeCount
                )
        }

        if let following =
            following
        {
            postActionFollowingByUserID[
                userID
            ] =
                following
        }

        postActionMetadataLock.unlock()
    }

    static func postActionMetadata(
        mediaID: String
    ) throws -> PostActionMetadata {
        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        postActionMetadataLock.lock()

        if let value =
            postActionMetadataByMediaID[
                mediaID
            ] ??
            postActionMetadataByMediaID[
                mediaPK
            ]
        {
            postActionMetadataLock.unlock()
            return value
        }

        let fallback =
            PostActionMetadata(
                liked:
                    false,
                saved:
                    false,
                following:
                    nil,
                trackingToken:
                    "",
                loggingInfoToken:
                    "",
                inventorySource:
                    "feed_timeline",
                navChain:
                    "PolarisFeedRoot:feedPage:1:via_cold_start",
                repostCount:
                    0,
                shareCount:
                    -1,
                reposted:
                    false,
                repostNoteID:
                    nil
            )

        postActionMetadataByMediaID[
            mediaID
        ] =
            fallback

        postActionMetadataByMediaID[
            mediaPK
        ] =
            fallback

        postActionMetadataLock.unlock()

        return fallback
    }

    static func updatePostActionMetadata(
        mediaID: String,
        liked: Bool? = nil,
        saved: Bool? = nil
    ) {
        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        postActionMetadataLock.lock()

        if var current =
            postActionMetadataByMediaID[
                mediaID
            ] ??
            postActionMetadataByMediaID[
                mediaPK
            ]
        {
            if let liked =
                liked
            {
                current.liked =
                    liked
            }

            if let saved =
                saved
            {
                current.saved =
                    saved
            }

            postActionMetadataByMediaID[
                mediaID
            ] =
                current

            postActionMetadataByMediaID[
                mediaPK
            ] =
                current
        }

        postActionMetadataLock.unlock()
    }

    static func cachedPostInteractionState(
        mediaID: String
    ) -> MagnistraPostInteractionState {
        let metadata =
            (
                try?
                    postActionMetadata(
                        mediaID:
                            mediaID
                    )
            )

        return
            MagnistraPostInteractionState(
                liked:
                    metadata?.liked ??
                    false,
                saved:
                    metadata?.saved ??
                    false
            )
    }

    static func cachedPostLikeCount(
        mediaID: String,
        fallback: Int
    ) -> Int {
        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        postActionMetadataLock.lock()

        let count =
            postActionLikeCountByMediaID[
                mediaID
            ] ??
            postActionLikeCountByMediaID[
                mediaPK
            ] ??
            fallback

        postActionMetadataLock.unlock()

        return
            max(
                0,
                count
            )
    }

    static func setCachedPostInteractionState(
        mediaID: String,
        liked: Bool?,
        saved: Bool?,
        likeCount: Int?
    ) {
        updatePostActionMetadata(
            mediaID:
                mediaID,
            liked:
                liked,
            saved:
                saved
        )

        if let likeCount =
            likeCount
        {
            let mediaPK =
                postActionMediaPK(
                    mediaID
                )

            postActionMetadataLock.lock()

            postActionLikeCountByMediaID[
                mediaID
            ] =
                max(
                    0,
                    likeCount
                )

            postActionLikeCountByMediaID[
                mediaPK
            ] =
                max(
                    0,
                    likeCount
                )

            postActionMetadataLock.unlock()
        }
    }

    static func cachedFollowingState(
        userID: String
    ) -> Bool? {
        postActionMetadataLock.lock()

        let value =
            postActionFollowingByUserID[
                userID
            ]

        postActionMetadataLock.unlock()

        return value
    }

    static func setCachedFollowingState(
        userID: String,
        following: Bool
    ) {
        postActionMetadataLock.lock()

        postActionFollowingByUserID[
            userID
        ] =
            following

        postActionMetadataLock.unlock()
    }

    static func cachedPostSocialState(
        mediaID: String
    ) -> MagnistraPostSocialState {
        let metadata =
            (
                try?
                    postActionMetadata(
                        mediaID:
                            mediaID
                    )
            )

        return
            MagnistraPostSocialState(
                reposted:
                    metadata?
                        .reposted ??
                    false,
                reposts:
                    max(
                        0,
                        metadata?
                            .repostCount ??
                        0
                    ),
                shares:
                    metadata?.shareCount ??
                    -1
            )
    }

    static func setCachedPostRepostState(
        mediaID: String,
        reposted: Bool,
        repostCount: Int,
        noteID: String?
    ) {
        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        postActionMetadataLock.lock()

        if var current =
            postActionMetadataByMediaID[
                mediaID
            ] ??
            postActionMetadataByMediaID[
                mediaPK
            ]
        {
            current.repostCount =
                max(
                    0,
                    repostCount
                )

            current.reposted =
                reposted

            current.repostNoteID =
                reposted
                    ? noteID
                    : nil

            postActionMetadataByMediaID[
                mediaID
            ] =
                current

            postActionMetadataByMediaID[
                mediaPK
            ] =
                current
        }

        postActionMetadataLock.unlock()
    }

    static func postActionValidateGraphQL(
        _ root:
            [String: Any],
        action:
            String
    ) throws {
        if
            let errors =
                root["errors"]
                    as? [Any],
            !errors.isEmpty
        {
            let message =
                (
                    (
                        errors.first
                            as? [String: Any]
                    )?["message"]
                        as? String
                ) ??
                (
                    action +
                    " failed."
                )

            throw NSError(
                domain:
                    "MagnistraPostAction",
                code:
                    9402,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        message
                ]
            )
        }

        guard
            root["data"]
                is [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraPostAction",
                code:
                    9403,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not confirm " +
                        action +
                        "."
                ]
            )
        }
    }
}
