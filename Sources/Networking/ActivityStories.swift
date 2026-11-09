// Overview: Parsing of story items found in Activity.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func parseActivityStory(
        _ story:
            [String: Any]
    ) -> MagnistraActivityItem? {
        let args =
            (
                story["args"]
                    as? [String: Any]
            ) ?? [:]

        let rawRichText =
            args["rich_text"]
                as? String

        let rawText =
            (
                args["text"]
                    as? String
            ) ??
            rawRichText ??
            (
                story["text"]
                    as? String
            ) ??
            "Activity"

        let text =
            activityCleanRichText(
                rawText
            )

        let richIdentity =
            activityRichIdentity(
                rawRichText ??
                    rawText
            )

        let user =
            activityFindUser(
                story
            )

        let username =
            (
                user?["username"]
                    as? String
            ) ??
            richIdentity?[
                "username"
            ] ??
            ""

        let userID =
            activityString(
                user?["pk"]
            ) ??
            activityString(
                user?["id"]
            ) ??
            activityString(
                args["profile_id"]
            ) ??
            richIdentity?[
                "userID"
            ] ??
            ""

        let fullName =
            (
                user?["full_name"]
                    as? String
            ) ?? ""

        let avatarURL =
            user.flatMap {
                activityImageURL($0)
            } ??
            activityImageURL(args)

        let media =
            activityFindMedia(
                story
            )

        let mediaID =
            activityString(
                media?["pk"]
            ) ??
            activityString(
                media?["id"]
            ) ??
            activityString(
                media?["media_id"]
            ) ??
            activityString(
                args["media_id"]
            )

        let mediaImageURL =
            media.flatMap {
                activityImageURL($0)
            } ??
            (
                args["media_image"]
                    as? String
            )

        let createdAt =
            (
                args["timestamp"]
                    as? NSNumber
            )?.doubleValue ??
            (
                story["timestamp"]
                    as? NSNumber
            )?.doubleValue ??
            0.0

        let activityID =
            activityString(
                story["pk"]
            ) ??
            (
                args["tuuid"]
                    as? String
            ) ??
            (
                username +
                ":" +
                String(createdAt) +
                ":" +
                text
            )

        let referencePost =
            activityReferencePost(
                media:
                    media,
                actorUser:
                    user,
                actorAvatarURL:
                    avatarURL
            )

        let referencedShortcode =
            activityFindReferencedShortcode(
                story
            )

        return MagnistraActivityItem(
            activityID:
                activityID,
            text:
                text,
            createdAt:
                createdAt,
            userID:
                userID,
            username:
                username,
            fullName:
                fullName,
            avatarURL:
                avatarURL,
            mediaID:
                mediaID,
            mediaImageURL:
                mediaImageURL,
            referencePost:
                referencePost,
            referencedShortcode:
                referencedShortcode
        )
    }
}
