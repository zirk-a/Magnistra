// Overview: Profiles: avatar and profile requests.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func profileImageURLs(
        from user: [String: Any]
    ) -> (
        primary: String?,
        fallback: String?
    ) {
        var urls: [String] = []

        func appendURL(
            _ value: Any?
        ) {
            guard
                let url =
                    value as? String,
                !url.isEmpty,
                !urls.contains(url)
            else {
                return
            }

            urls.append(url)
        }

        if
            let info =
                user[
                    "hd_profile_pic_url_info"
                ] as? [String: Any]
        {
            appendURL(
                info["url"]
            )
        }

        if
            let versions =
                user[
                    "hd_profile_pic_versions"
                ] as? [[String: Any]]
        {
            for version in versions {
                appendURL(
                    version["url"]
                )
            }
        }

        appendURL(
            user[
                "profile_pic_url_hd"
            ]
        )

        appendURL(
            user[
                "profile_pic_url"
            ]
        )

        return (
            primary:
                urls.first,
            fallback:
                urls.count > 1
                    ? urls[1]
                    : nil
        )
    }

    static func loadProfileAvatar(
        primaryURL: String?,
        fallbackURL: String?
    ) -> UIImage? {
        guard
            let session =
                try? loadSession(),
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                )
        else {
            return nil
        }

        var urls: [String] = []

        if
            let primary =
                primaryURL,
            !primary.isEmpty
        {
            urls.append(primary)
        }

        if
            let fallback =
                fallbackURL,
            !fallback.isEmpty,
            !urls.contains(fallback)
        {
            urls.append(fallback)
        }

        for url in urls {
            guard
                let data =
                    MagnistraLazyImageTransport
                        .fetch(
                            url:
                                url,
                            caPath:
                                caPath,
                            userAgent:
                                session.userAgent
                        ),
                let image =
                    UIImage(
                        data:
                            data
                    ),
                image.size.width > 0.0,
                image.size.height > 0.0
            else {
                continue
            }

            return image
        }

        return nil
    }

    static func loadCurrentProfile()
        throws -> MagnistraProfileInfo
    {
        let session =
            try loadSession()

        let prefix =
            "ds_user_id="

        var currentUserID =
            ""

        for pair in
            session.cookieHeader
                .components(
                    separatedBy:
                        "; "
                )
        {
            if pair.hasPrefix(prefix) {
                currentUserID =
                    (pair as NSString)
                        .substring(
                            from:
                                prefix.count
                        )
                break
            }
        }

        guard
            !currentUserID.isEmpty,
            currentUserID
                .rangeOfCharacter(
                    from:
                        CharacterSet
                            .decimalDigits
                            .inverted
                ) == nil
        else {
            throw NSError(
                domain:
                    "MagnistraProfile",
                code:
                    5110,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Current Instagram account id is unavailable."
                ]
            )
        }

        return try loadProfile(
            userID:
                currentUserID,
            fallbackUsername:
                "Profile",
            fallbackFullName:
                ""
        )
    }

    static func isCurrentAccountProfile(userID: String) -> Bool {
        guard let actor = try? postActionActorID() else { return false }
        return actor == userID
    }

    static func loadProfile(
        userID: String,
        fallbackUsername: String,
        fallbackFullName: String
    ) throws -> MagnistraProfileInfo {
        guard
            !userID.isEmpty,
            userID.rangeOfCharacter(
                from:
                    CharacterSet
                        .decimalDigits
                        .inverted
            ) == nil
        else {
            throw NSError(
                domain: "MagnistraProfile",
                code: 5100,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Profile user id is unavailable."
                ]
            )
        }

        let strategies =
            MagnistraInstagramCompatibility
                .graphqlStrategies(
                    for: .profile
                )

        var lastError: NSError? = nil

        for strategy in strategies {
            var variables =
                strategy.staticVariables

            variables["id"] = userID

            do {
                let root =
                    try exploreSearchGraphQLRoot(
                        variables: variables,
                        docID: strategy.docID,
                        friendlyName:
                            strategy.friendlyName
                    )

                guard
                    let user =
                        MagnistraInstagramCompatibility
                            .profileUser(
                                in: root
                            )
                else {
                    lastError = NSError(
                        domain: "MagnistraProfile",
                        code: 5112,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Profile strategy " +
                                strategy.identifier +
                                " returned no usable user."
                        ]
                    )
                    continue
                }

                let username =
                    (
                        user["username"]
                            as? String
                    ) ??
                    fallbackUsername

                let fullName =
                    (
                        user["full_name"]
                            as? String
                    ) ??
                    fallbackFullName

                let biography =
                    (
                        user["biography"]
                            as? String
                    ) ?? ""

                let profileImages =
                    profileImageURLs(
                        from: user
                    )

                let friendship = user["friendship_status"] as? [String: Any]
                let viewerFollows =
                    boolValue(friendship?["following"]) ??
                    boolValue(user["followed_by_viewer"]) ??
                    boolValue(user["is_following"])

                return MagnistraProfileInfo(
                    userID:
                        stringValue(
                            user["pk"]
                        ) ??
                        stringValue(
                            user["id"]
                        ) ??
                        userID,
                    username: username,
                    fullName: fullName,
                    biography: biography,
                    profilePicURL:
                        profileImages.primary,
                    profilePicURLFallback:
                        profileImages.fallback,
                    followerCount:
                        intValue(
                            user["follower_count"]
                        ) ?? 0,
                    followingCount:
                        intValue(
                            user["following_count"]
                        ) ?? 0,
                    mediaCount:
                        intValue(
                            user["media_count"]
                        ) ?? 0,
                    isPrivate:
                        boolValue(
                            user["is_private"]
                        ) ?? false,
                    viewerFollows:
                        viewerFollows
                )
            }
            catch {
                lastError = error as NSError
            }
        }

        throw lastError ?? NSError(
            domain: "MagnistraProfile",
            code: 5113,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "No usable Instagram profile contract is available."
            ]
        )
    }
}
