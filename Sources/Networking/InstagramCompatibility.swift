// Overview: Compatibility switches for Instagram GraphQL strategies and overrides.
import Foundation

enum MagnistraInstagramCompatibilityFeature: String {
    case profile = "profile"
    case comments = "comments"
    case activityPost = "activity_post"
}

struct MagnistraInstagramGraphQLStrategy {
    let identifier: String
    let docID: String
    let friendlyName: String
    let staticVariables: [String: Any]
    let source: String
}

enum MagnistraInstagramCompatibility {
    private static let resourceName =
        "MagnistraInstagramContracts"

    private static let overrideFileName =
        "MagnistraInstagramContracts.override.json"

    static func graphqlStrategies(
        for feature: MagnistraInstagramCompatibilityFeature
    ) -> [MagnistraInstagramGraphQLStrategy] {
        var roots: [(String, [String: Any])] = []

        for path in overridePaths() {
            if let root = readJSON(path: path) {
                roots.append(("override", root))
                break
            }
        }

        if
            let path = Bundle.main.path(
                forResource: resourceName,
                ofType: "json"
            ),
            let root = readJSON(path: path)
        {
            roots.append(("bundle", root))
        }

        var result: [MagnistraInstagramGraphQLStrategy] = []
        var seen = Set<String>()

        for (source, root) in roots {
            for strategy in parseStrategies(
                feature: feature,
                root: root,
                source: source
            ) {
                let key =
                    strategy.docID + "|" +
                    strategy.friendlyName

                if seen.contains(key) {
                    continue
                }

                seen.insert(key)
                result.append(strategy)
            }
        }

        return result
    }

    static func profileUser(
        in root: [String: Any]
    ) -> [String: Any]? {
        if
            let data = root["data"] as? [String: Any],
            let user = data["user"] as? [String: Any]
        {
            return user
        }

        return findProfileUser(
            root,
            depth: 0
        )
    }

    static func commentsConnection(
        in root: [String: Any]
    ) -> [String: Any]? {
        if let data = root["data"] as? [String: Any] {
            if let found = findCommentsConnection(
                data,
                depth: 0,
                preferred: true
            ) {
                return found
            }
        }

        return findCommentsConnection(
            root,
            depth: 0,
            preferred: true
        )
    }

    private static func overridePaths() -> [String] {
        var paths: [String] = []

        if
            let documents =
                NSSearchPathForDirectoriesInDomains(
                    .documentDirectory,
                    .userDomainMask,
                    true
                ).first
        {
            paths.append(
                (documents as NSString)
                    .appendingPathComponent(
                        overrideFileName
                    )
            )
        }

        paths.append(
            "/var/mobile/Documents/" +
            overrideFileName
        )

        return paths
    }

    private static func readJSON(
        path: String
    ) -> [String: Any]? {
        guard
            let data =
                FileManager.default
                    .contents(
                        atPath: path
                    ),
            let object =
                try? MagnistraJSONKit
                    .jsonObject(
                        with: data,
                        options: []
                    ),
            let root =
                object as? [String: Any],
            let format =
                root["format_version"]
                    as? NSNumber,
            format.intValue == 1
        else {
            return nil
        }

        return root
    }

    private static func parseStrategies(
        feature: MagnistraInstagramCompatibilityFeature,
        root: [String: Any],
        source: String
    ) -> [MagnistraInstagramGraphQLStrategy] {
        guard
            let features =
                root["features"]
                    as? [String: Any],
            let rawStrategies =
                features[feature.rawValue]
                    as? [[String: Any]]
        else {
            return []
        }

        var result: [MagnistraInstagramGraphQLStrategy] = []

        for raw in rawStrategies {
            guard
                let docID = raw["doc_id"] as? String,
                validDocID(docID),
                let friendlyName =
                    raw["friendly_name"]
                        as? String,
                !friendlyName.isEmpty,
                friendlyName.count <= 160
            else {
                continue
            }

            let identifier =
                (
                    raw["id"]
                        as? String
                ) ??
                friendlyName

            let variables =
                raw["variables"]
                    as? [String: Any] ??
                [:]

            result.append(
                MagnistraInstagramGraphQLStrategy(
                    identifier: identifier,
                    docID: docID,
                    friendlyName: friendlyName,
                    staticVariables: variables,
                    source: source
                )
            )
        }

        return result
    }

    private static func validDocID(
        _ value: String
    ) -> Bool {
        if value.count < 5 || value.count > 40 {
            return false
        }

        return value.unicodeScalars.allSatisfy {
            scalar in

            scalar.value >= 48 &&
            scalar.value <= 57
        }
    }

    private static func findProfileUser(
        _ value: Any,
        depth: Int
    ) -> [String: Any]? {
        if depth > 12 {
            return nil
        }

        if let dictionary = value as? [String: Any] {
            let username =
                dictionary["username"]
                    as? String

            let hasIdentity =
                dictionary["pk"] != nil ||
                dictionary["id"] != nil

            var profileSignals = 0
            for key in [
                "biography",
                "follower_count",
                "following_count",
                "media_count",
                "is_private",
                "profile_pic_url"
            ] {
                if dictionary[key] != nil {
                    profileSignals += 1
                }
            }

            if
                username?.isEmpty == false,
                hasIdentity,
                profileSignals >= 2
            {
                return dictionary
            }

            for child in dictionary.values {
                if let found = findProfileUser(
                    child,
                    depth: depth + 1
                ) {
                    return found
                }
            }
        }
        else if let array = value as? [Any] {
            for child in array {
                if let found = findProfileUser(
                    child,
                    depth: depth + 1
                ) {
                    return found
                }
            }
        }

        return nil
    }

    private static func findCommentsConnection(
        _ value: Any,
        depth: Int,
        preferred: Bool
    ) -> [String: Any]? {
        if depth > 12 {
            return nil
        }

        if let dictionary = value as? [String: Any] {
            if
                dictionary["edges"] is [Any],
                dictionary["page_info"] is [String: Any]
            {
                return dictionary
            }

            for (key, child) in dictionary {
                let isCommentKey =
                    key.lowercased()
                        .contains("comment")

                if preferred && !isCommentKey {
                    continue
                }

                if let found = findCommentsConnection(
                    child,
                    depth: depth + 1,
                    preferred: false
                ) {
                    return found
                }
            }

            if preferred {
                for child in dictionary.values {
                    if let found = findCommentsConnection(
                        child,
                        depth: depth + 1,
                        preferred: false
                    ) {
                        return found
                    }
                }
            }
        }
        else if let array = value as? [Any] {
            for child in array {
                if let found = findCommentsConnection(
                    child,
                    depth: depth + 1,
                    preferred: preferred
                ) {
                    return found
                }
            }
        }

        return nil
    }
}
