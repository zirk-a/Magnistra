import Foundation

// Pure extraction of share-count fallback and action metadata construction.
// The original candidate precedence and evaluation order are unchanged.
extension MagnistraHomeService {

    static func postActionShareCount(
        media: [String: Any],
        context: [String: Any],
        useIndex useMetadataIndex: Bool,
        mediaIndex mediaMetadataIndex: MagnistraMetadataIndex?,
        contextIndex contextMetadataIndex: MagnistraMetadataIndex?
    ) -> Int {
        let mediaReshareCount =
            (
                    useMetadataIndex
                        ? mediaMetadataIndex?.ints["reshare_count"]
                        : postActionFindInt(
                key:
                    "reshare_count",
                in:
                    media
            )
                )

        let mediaShareCount =
            (
                    useMetadataIndex
                        ? mediaMetadataIndex?.ints["share_count"]
                        : postActionFindInt(
                key:
                    "share_count",
                in:
                    media
            )
                )

        let mediaSharesCount =
            (
                    useMetadataIndex
                        ? mediaMetadataIndex?.ints["shares_count"]
                        : postActionFindInt(
                key:
                    "shares_count",
                in:
                    media
            )
                )

        let mediaSendCount =
            (
                    useMetadataIndex
                        ? mediaMetadataIndex?.ints["send_count"]
                        : postActionFindInt(
                key:
                    "send_count",
                in:
                    media
            )
                )

        let contextReshareCount =
            (
                    useMetadataIndex
                        ? contextMetadataIndex?.ints["reshare_count"]
                        : postActionFindInt(
                key:
                    "reshare_count",
                in:
                    context
            )
                )

        let contextShareCount =
            (
                    useMetadataIndex
                        ? contextMetadataIndex?.ints["share_count"]
                        : postActionFindInt(
                key:
                    "share_count",
                in:
                    context
            )
                )

        let contextSharesCount =
            (
                    useMetadataIndex
                        ? contextMetadataIndex?.ints["shares_count"]
                        : postActionFindInt(
                key:
                    "shares_count",
                in:
                    context
            )
                )

        let contextSendCount =
            (
                    useMetadataIndex
                        ? contextMetadataIndex?.ints["send_count"]
                        : postActionFindInt(
                key:
                    "send_count",
                in:
                    context
            )
                )

        let shareCount:
            Int

        if let value =
            mediaReshareCount
        {
            shareCount =
                value
        } else if let value =
            mediaShareCount
        {
            shareCount =
                value
        } else if let value =
            mediaSharesCount
        {
            shareCount =
                value
        } else if let value =
            mediaSendCount
        {
            shareCount =
                value
        } else if let value =
            contextReshareCount
        {
            shareCount =
                value
        } else if let value =
            contextShareCount
        {
            shareCount =
                value
        } else if let value =
            contextSharesCount
        {
            shareCount =
                value
        } else if let value =
            contextSendCount
        {
            shareCount =
                value
        } else {
            shareCount =
                -1
        }

        return shareCount
    }

    static func postActionConstructMetadata(
        media: [String: Any],
        context: [String: Any],
        following: Bool?,
        useIndex useMetadataIndex: Bool,
        mediaIndex mediaMetadataIndex: MagnistraMetadataIndex?,
        contextIndex contextMetadataIndex: MagnistraMetadataIndex?,
        repostCount: Int,
        shareCount: Int,
        repostNoteID: String?
    ) -> PostActionMetadata {
        return
            PostActionMetadata(
                liked:
                    boolValue(
                        media[
                            "has_liked"
                        ]
                    ) ?? false,
                saved:
                    boolValue(
                        media[
                            "has_viewer_saved"
                        ]
                    ) ??
                    boolValue(
                        media[
                            "has_viewer_saved_to_collection"
                        ]
                    ) ??
                    false,
                following:
                    following,
                trackingToken:
                    (
                    useMetadataIndex
                        ? contextMetadataIndex?.strings["tracking_token"]
                        : postActionFindString(
                        key:
                            "tracking_token",
                        in:
                            context
                    )
                ) ??
                    (
                    useMetadataIndex
                        ? mediaMetadataIndex?.strings["tracking_token"]
                        : postActionFindString(
                        key:
                            "tracking_token",
                        in:
                            media
                    )
                ) ??
                    "",
                loggingInfoToken:
                    (
                    useMetadataIndex
                        ? mediaMetadataIndex?.strings["logging_info_token"]
                        : postActionFindString(
                        key:
                            "logging_info_token",
                        in:
                            media
                    )
                ) ??
                    (
                    useMetadataIndex
                        ? contextMetadataIndex?.strings["logging_info_token"]
                        : postActionFindString(
                        key:
                            "logging_info_token",
                        in:
                            context
                    )
                ) ??
                    "",
                inventorySource:
                    (
                    useMetadataIndex
                        ? mediaMetadataIndex?.strings["inventory_source"]
                        : postActionFindString(
                        key:
                            "inventory_source",
                        in:
                            media
                    )
                ) ??
                    "feed_timeline",
                navChain:
                    (
                    useMetadataIndex
                        ? mediaMetadataIndex?.strings["nav_chain"]
                        : postActionFindString(
                        key:
                            "nav_chain",
                        in:
                            media
                    )
                ) ??
                    "PolarisFeedRoot:feedPage:1:via_cold_start",
                repostCount:
                    repostCount,
                shareCount:
                    shareCount,
                reposted:
                    repostNoteID != nil,
                repostNoteID:
                    repostNoteID
            )

    }
}
