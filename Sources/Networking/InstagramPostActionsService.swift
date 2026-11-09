// Overview: Post actions: like, save, repost, follow and interaction state.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func postActionRoot(
        relativePath: String,
        postBody: String?
    ) throws -> [String: Any] {
        let session =
            try loadSession()

        guard let caPath =
            Bundle.main.path(
                forResource: "CACert",
                ofType: "pem"
            )
        else {
            throw NSError(
                domain: "MagnistraPostAction",
                code: 9302,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        let usePost =
            postBody != nil

        let curlCode: Int32 =
            caPath.withCString { ca in
                session.userAgent.withCString { ua in
                    session.language.withCString { lang in
                        session.cookieHeader.withCString { cookies in
                            session.csrfToken.withCString { csrf in
                                relativePath.withCString { path in
                                    let invoke: (UnsafePointer<CChar>?) -> Int32 = {
                                        body in

                                        return Int32(
                                            magnistra_transport_post_action_request(
                                                ca,
                                                ua,
                                                lang,
                                                cookies,
                                                csrf,
                                                path,
                                                body,
                                                usePost ? 1 : 0
                                            )
                                        )
                                    }

                                    if let postBody = postBody {
                                        return postBody.withCString {
                                            body in
                                            invoke(body)
                                        }
                                    }

                                    return invoke(nil)
                                }
                            }
                        }
                    }
                }
            }

        let httpStatus =
            magnistra_transport_http_status()

        let tlsResult =
            magnistra_transport_tls_verify_result()

        let length =
            magnistra_transport_body_length()

        guard
            curlCode == 0,
            httpStatus >= 200,
            httpStatus < 300,
            tlsResult == 0
        else {
            throw NSError(
                domain: "MagnistraPostAction",
                code: Int(httpStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram action failed (HTTP \(httpStatus))."
                ]
            )
        }

        if
            length > 0,
            let body =
                magnistra_transport_body()
        {
            let data =
                Data(
                    bytes: body,
                    count: Int(length)
                )

            if
                let root =
                    try MagnistraJSONKit
                        .jsonObject(
                            with: data,
                            options: []
                        )
                        as? [String: Any]
            {
                if
                    let status =
                        root["status"] as? String,
                    status != "ok"
                {
                    let message =
                        (
                            root["message"] as? String
                        ) ??
                        "Instagram rejected the action."

                    throw NSError(
                        domain: "MagnistraPostAction",
                        code: 9303,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                message
                        ]
                    )
                }

                return root
            }
        }

        return [:]
    }

    static func setPostReposted(
        mediaID: String,
        reposted: Bool
    ) throws -> String? {
        let actorID =
            try postActionActorID()

        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        var metadata =
            try postActionMetadata(
                mediaID:
                    mediaID
            )

        if reposted {
            let variables:
                [String: Any] = [
                    "input": [
                        "actor_id":
                            actorID,
                        "audience":
                            7,
                        "client_mutation_id":
                            postActionNextMutationID(),
                        "media_id":
                            mediaPK,
                        "note_style":
                            13,
                        "text":
                            ""
                    ]
                ]

            let root =
                try exploreSearchGraphQLRoot(
                    variables:
                        variables,
                    docID:
                        "38542997498680691",
                    friendlyName:
                        "usePolarisCreateMediaRepostMutation"
                )

            try postActionValidateGraphQL(
                root,
                action:
                    "Repost"
            )

            var noteID =
                postActionFindRepostNoteID(
                    in:
                        root,
                    actorID:
                        actorID
                )

            if noteID == nil {
                noteID =
                    try?
                        postActionLoadViewerRepostNoteID(
                            mediaID:
                                mediaID,
                            actorID:
                                actorID
                        )
            }

            metadata.reposted =
                true

            metadata.repostNoteID =
                noteID

            postActionMetadataLock.lock()

            postActionMetadataByMediaID[
                mediaID
            ] =
                metadata

            postActionMetadataByMediaID[
                mediaPK
            ] =
                metadata

            postActionMetadataLock.unlock()

            return noteID
        }

        var noteID =
            metadata.repostNoteID

        if noteID == nil {
            noteID =
                try postActionLoadViewerRepostNoteID(
                    mediaID:
                        mediaID,
                    actorID:
                        actorID
                )
        }

        guard
            let resolvedNoteID =
                noteID,
            !resolvedNoteID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraPostAction",
                code:
                    9450,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram repost ID unavailable. Refresh the post and try again."
                ]
            )
        }

        let variables:
            [String: Any] = [
                "input": [
                    "actor_id":
                        actorID,
                    "client_mutation_id":
                        postActionNextMutationID(),
                    "note_id":
                        resolvedNoteID
                ]
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "26656683127335602",
                friendlyName:
                    "usePolarisDeleteMediaRepostMutation"
            )

        try postActionValidateGraphQL(
            root,
            action:
                "Undo repost"
        )

        metadata.reposted =
            false

        metadata.repostNoteID =
            nil

        postActionMetadataLock.lock()

        postActionMetadataByMediaID[
            mediaID
        ] =
            metadata

        postActionMetadataByMediaID[
            mediaPK
        ] =
            metadata

        postActionMetadataLock.unlock()

        return nil
    }

    static func loadPostInteractionState(
        mediaID: String
    ) throws -> MagnistraPostInteractionState {
        let metadata =
            try postActionMetadata(
                mediaID:
                    mediaID
            )

        return
            MagnistraPostInteractionState(
                liked:
                    metadata.liked,
                saved:
                    metadata.saved
            )
    }

    static func setPostLiked(
        mediaID: String,
        liked: Bool
    ) throws {
        let metadata =
            try postActionMetadata(
                mediaID:
                    mediaID
            )

        let actorID =
            try postActionActorID()

        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        var input:
            [String: Any] = [
                "actor_id":
                    actorID,
                "client_mutation_id":
                    postActionNextMutationID(),
                "container_module":
                    "feed_timeline",
                "media_id":
                    mediaPK
            ]

        if
            !metadata.trackingToken.isEmpty
        {
            input[
                "tracking_token"
            ] =
                metadata.trackingToken
        }

        let variables:
            [String: Any] = [
                "input":
                    input
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    liked
                        ? "27182485238052618"
                        : "27345296031770102",
                friendlyName:
                    liked
                        ? "usePolarisLikeMediaXIGLikeMutation"
                        : "usePolarisLikeMediaXIGUnlikeMutation"
            )

        try postActionValidateGraphQL(
            root,
            action:
                liked
                    ? "Like"
                    : "Unlike"
        )

        updatePostActionMetadata(
            mediaID:
                mediaID,
            liked:
                liked
        )
    }

    static func setPostSaved(
        mediaID: String,
        saved: Bool
    ) throws {
        let metadata =
            try postActionMetadata(
                mediaID:
                    mediaID
            )

        let actorID =
            try postActionActorID()

        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        let variables:
            [String: Any]

        let docID:
            String

        let friendlyName:
            String

        if saved {
            var input:
                [String: Any] = [
                    "actor_id":
                        actorID,
                    "client_mutation_id":
                        postActionNextMutationID(),
                    "container_module":
                        "feed_timeline",
                    "inventory_source":
                        metadata.inventorySource,
                    "media_id":
                        mediaPK,
                    "nav_chain":
                        metadata.navChain
                ]

            if
                !metadata.loggingInfoToken.isEmpty
            {
                input[
                    "logging_info_token"
                ] =
                    metadata.loggingInfoToken
            }

            variables = [
                "input":
                    input
            ]

            docID =
                "27365486596441074"

            friendlyName =
                "usePolarisSaveMediaSaveMutation"
        } else {
            variables = [
                "input": [
                    "actor_id":
                        actorID,
                    "client_mutation_id":
                        postActionNextMutationID(),
                    "media_id":
                        mediaPK
                ]
            ]

            docID =
                "27371251859134880"

            friendlyName =
                "usePolarisSaveMediaUnsaveMutation"
        }

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    docID,
                friendlyName:
                    friendlyName
            )

        try postActionValidateGraphQL(
            root,
            action:
                saved
                    ? "Save"
                    : "Unsave"
        )

        updatePostActionMetadata(
            mediaID:
                mediaID,
            saved:
                saved
        )
    }

    static func loadFollowingState(
        userID: String
    ) throws -> Bool {
        guard
            !userID.isEmpty,
            !userID.hasPrefix(
                "username:"
            )
        else {
            throw NSError(
                domain:
                    "MagnistraPostAction",
                code:
                    9430,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram user ID unavailable."
                ]
            )
        }

        postActionMetadataLock.lock()

        let value =
            postActionFollowingByUserID[
                userID
            ]

        postActionMetadataLock.unlock()

        return
            value ?? false
    }

    static func setFollowing(
        userID: String,
        mediaID: String,
        following: Bool
    ) throws {
        guard
            !userID.isEmpty,
            !userID.hasPrefix(
                "username:"
            )
        else {
            throw NSError(
                domain:
                    "MagnistraPostAction",
                code:
                    9440,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram user ID unavailable."
                ]
            )
        }

        let mediaPK =
            postActionMediaPK(
                mediaID
            )

        let metadata =
            try postActionMetadata(
                mediaID:
                    mediaID
            )

        let variables:
            [String: Any]

        let docID:
            String

        let friendlyName:
            String

        if following {
            variables = [
                "container_module":
                    "feed_timeline",
                "inventory_source":
                    NSNull(),
                "media_id_attribution":
                    mediaPK,
                "nav_chain":
                    metadata.navChain,
                "ranking_info_token":
                    NSNull(),
                "target_user_id":
                    userID
            ]

            docID =
                "29565626759693263"

            friendlyName =
                "usePolarisToggleFollowUserFollowMutation"
        } else {
            variables = [
                "container_module":
                    "feed_timeline",
                "media_id_attribution":
                    mediaPK,
                "nav_chain":
                    metadata.navChain,
                "target_user_id":
                    userID
            ]

            docID =
                "36125934623721145"

            friendlyName =
                "usePolarisToggleFollowUserUnfollowMutation"
        }

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    docID,
                friendlyName:
                    friendlyName
            )

        try postActionValidateGraphQL(
            root,
            action:
                following
                    ? "Follow"
                    : "Unfollow"
        )

        postActionMetadataLock.lock()

        postActionFollowingByUserID[
            userID
        ] =
            following

        postActionMetadataLock.unlock()
    }
}
