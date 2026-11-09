// Overview: Comments: loading, parsing, liking and posting.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func commentMediaCandidate(
        _ value: Any?,
        depth: Int = 0
    ) -> (String?, Int, Int) {
        guard
            depth <= 10,
            let value = value
        else {
            return (nil, 0, 0)
        }

        if let dictionary =
            value as? [String: Any]
        {
            let width =
                intValue(
                    dictionary["width"]
                ) ?? 0

            let height =
                intValue(
                    dictionary["height"]
                ) ?? 0

            for key in [
                "url",
                "gif_url",
                "webp",
                "mp4"
            ] {
                if
                    let string =
                        dictionary[key] as? String,
                    string.hasPrefix("http")
                {
                    return (
                        string,
                        width,
                        height
                    )
                }
            }

            for key in [
                "first_party_cdn_proxied_images",
                "images",
                "fixed_height",
                "fixed_width",
                "downsized",
                "original"
            ] {
                if let child =
                    dictionary[key]
                {
                    let found =
                        commentMediaCandidate(
                            child,
                            depth:
                                depth + 1
                        )

                    if found.0 != nil {
                        return found
                    }
                }
            }

            for child in dictionary.values {
                let found =
                    commentMediaCandidate(
                        child,
                        depth:
                            depth + 1
                    )

                if found.0 != nil {
                    return found
                }
            }
        }

        if let array =
            value as? [Any]
        {
            for child in array {
                let found =
                    commentMediaCandidate(
                        child,
                        depth:
                            depth + 1
                    )

                if found.0 != nil {
                    return found
                }
            }
        }

        return (nil, 0, 0)
    }

    static func parseComment(
        _ object: [String: Any]
    ) -> MagnistraComment? {
        guard
            let user =
                object["user"]
                    as? [String: Any],
            let username =
                user["username"]
                    as? String,
            !username.isEmpty
        else {
            return nil
        }

        let text =
            (
                object["text"]
                    as? String
            ) ?? ""

        let giphy =
            commentMediaCandidate(
                object[
                    "giphy_media_info"
                ]
            )

        if
            text.isEmpty &&
            giphy.0 == nil
        {
            return nil
        }

        let created =
            intValue(
                object[
                    "created_at_utc"
                ]
            ) ??
            intValue(
                object[
                    "created_at"
                ]
            ) ??
            0

        let commentID =
            stringValue(
                object["pk"]
            ) ??
            stringValue(
                object["id"]
            ) ??
            (
                username +
                ":" +
                String(created) +
                ":" +
                String(
                    (text as NSString)
                        .length
                )
            )

        return
            MagnistraComment(
                commentID:
                    commentID,
                username:
                    username,
                text:
                    text,
                createdAt:
                    Double(created),
                avatarURL:
                    user[
                        "profile_pic_url"
                    ] as? String,
                likeCount:
                    max(
                        0,
                        intValue(
                            object[
                                "comment_like_count"
                            ]
                        ) ?? 0
                    ),
                hasLiked:
                    boolValue(
                        object[
                            "has_liked_comment"
                        ]
                    ) ?? false,
                parentCommentID:
                    stringValue(
                        object[
                            "parent_comment_id"
                        ]
                    ),
                childCommentCount:
                    max(
                        0,
                        intValue(
                            object[
                                "child_comment_count"
                            ]
                        ) ?? 0
                    ),
                giphyURL:
                    giphy.0,
                giphyWidth:
                    giphy.1,
                giphyHeight:
                    giphy.2
            )
    }

    static func localVideoPlaybackURL(
        for post: MagnistraRealPost,
        proxy: StreamProxy =
            StreamProxy.shared,
        prepareForNextReel: Bool = false
    ) throws -> URL? {
        guard
            let remote = post.videoURL,
            !remote.isEmpty
        else {
            return nil
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
                    "MagnistraVideo",
                code:
                    5401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        return proxy
            .localURL(
                for:
                    remote,
                caPath:
                    caPath,
                userAgent:
                    session.userAgent,
                prepareForNextReel:
                    prepareForNextReel
            )
    }

    static func setCommentLiked(
        commentID: String,
        liked: Bool
    ) throws {
        let actorID =
            try postActionActorID()

        let variables:
            [String: Any] = [
                "input": [
                    "actor_id":
                        actorID,
                    "client_mutation_id":
                        postActionNextMutationID(),
                    "comment_id":
                        commentID
                ]
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    liked
                        ? "25746541371686622"
                        : "26466515576331833",
                friendlyName:
                    liked
                        ? "usePolarisCommentLikeMutation"
                        : "usePolarisCommentUnlikeMutation"
            )

        try postActionValidateGraphQL(
            root,
            action:
                liked
                    ? "Like comment"
                    : "Unlike comment"
        )
    }

    static func loadChildComments(
        mediaID: String,
        parentCommentID: String
    ) throws -> [MagnistraComment] {
        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        let variables:
            [String: Any] = [
                "__relay_internal__pv__PolarisIsLoggedInrelayprovider":
                    true,
                "after":
                    NSNull(),
                "before":
                    NSNull(),
                "first":
                    NSNull(),
                "is_chronological":
                    NSNull(),
                "last":
                    NSNull(),
                "media_id":
                    mediaPK,
                "parent_comment_id":
                    parentCommentID
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "28027289793632076",
                friendlyName:
                    "PolarisPostChildCommentsQuery"
            )

        guard
            let data =
                root[
                    "data"
                ] as? [String: Any],
            let connection =
                data[
                    "xdt_api__v1__media__media_id__comments__parent_comment_id__child_comments__connection"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraCommentReplies",
                code:
                    9480,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not return comment replies."
                ]
            )
        }

        let edges =
            connection[
                "edges"
            ] as? [[String: Any]] ??
            []

        var result:
            [MagnistraComment] = []

        for edge in edges {
            guard
                let node =
                    edge[
                        "node"
                    ] as? [String: Any],
                let parsed =
                    parseComment(
                        node
                    )
            else {
                continue
            }

            result.append(
                parsed
            )
        }

        return result
    }

    static func addComment(
        mediaID: String,
        text: String,
        repliedToCommentID: String? = nil
    ) throws -> MagnistraComment? {
        let trimmed =
            text.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return nil
        }

        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        var data:
            [String: Any] = [
                "comment_text":
                    trimmed,
                "media_id":
                    mediaPK
            ]

        if
            let replyID =
                repliedToCommentID,
            let numericReplyID =
                Int64(
                    replyID
                )
        {
            data[
                "replied_to_comment_id"
            ] =
                numericReplyID
        }

        let variables:
            [String: Any] = [
                "connections":
                    [] as [String],
                "data":
                    data
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "27261905640092552",
                friendlyName:
                    "PolarisPostCommentInputRevampedMutation"
            )

        try postActionValidateGraphQL(
            root,
            action:
                repliedToCommentID == nil
                    ? "Comment"
                    : "Reply"
        )

        guard
            let responseData =
                root[
                    "data"
                ] as? [String: Any],
            let create =
                responseData[
                    "xig_comment_create"
                ] as? [String: Any],
            let dictionary =
                create[
                    "comment_dict"
                ] as? [String: Any]
        else {
            return nil
        }

        return
            parseComment(
                dictionary
            )
    }

    static func loadComments(
        mediaID: String,
        maxID: String?
    ) throws -> MagnistraCommentsPage {
        let mediaPK =
            mediaID
                .components(
                    separatedBy:
                        "_"
                )
                .first ??
            mediaID

        guard
            !mediaPK.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraComments",
                code:
                    5200,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Comment media id is unavailable."
                ]
            )
        }

        var variables:
            [String: Any] = [
                "__relay_internal__pv__PolarisIsLoggedInrelayprovider":
                    true,
                "before":
                    NSNull(),
                "first":
                    10,
                "last":
                    NSNull(),
                "media_id":
                    mediaPK,
                "sort_order":
                    "popular"
            ]

        if
            let cursor = maxID,
            !cursor.isEmpty
        {
            variables["after"] =
                cursor
        } else {
            variables["after"] =
                NSNull()
        }

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "28428885330094742",
                friendlyName:
                    "PolarisPostCommentsPaginationQuery"
            )

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let connection =
                data[
                    "xdt_api__v1__media__media_id__comments__connection"
                ] as? [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraComments",
                code:
                    5205,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not return the comments connection."
                ]
            )
        }

        let edges =
            connection["edges"]
                as? [[String: Any]] ??
            []

        var comments:
            [MagnistraComment] = []

        for edge in edges {
            guard
                let node =
                    edge["node"]
                        as? [String: Any],
                let comment =
                    parseComment(node)
            else {
                continue
            }

            comments.append(comment)
        }

        let pageInfo =
            connection["page_info"]
                as? [String: Any]

        let hasNext =
            boolValue(
                pageInfo?["has_next_page"]
            ) ?? false

        let endCursor =
            stringValue(
                pageInfo?["end_cursor"]
            )

        let next:
            String?

        if
            hasNext,
            let cursor = endCursor,
            !cursor.isEmpty,
            cursor != maxID
        {
            next = cursor
        } else {
            next = nil
        }

        return MagnistraCommentsPage(
            comments:
                comments,
            nextMaxID:
                next
        )
    }
}
