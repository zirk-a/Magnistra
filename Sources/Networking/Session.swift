// Overview: Session loading and JSON value helpers for the Instagram service.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func isInstagramDomain(
        _ raw: String
    ) -> Bool {
        var domain = raw.lowercased()

        while domain.hasPrefix(".") {
            domain.removeFirst()
        }

        return domain == "instagram.com" ||
               domain.hasSuffix(
                    ".instagram.com"
               )
    }

    static func loadSession()
        throws -> MagnistraSessionInput {
        guard let docs =
            documentsPath()
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Documents folder unavailable."
                ]
            )
        }

        let path =
            (docs as NSString)
                .appendingPathComponent(
                    "MagnistraSession.mgsession"
                )

        guard
            FileManager.default.fileExists(
                atPath: path
            )
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5002,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No Magnistra session imported."
                ]
            )
        }

        let data: Data
        if let unlocked = MagnistraV2SessionCache.snapshot() {
            data = unlocked
        } else {
            let diskData = try Data(contentsOf: URL(fileURLWithPath: path))
            if diskData.starts(with: [77, 71, 83, 69, 83, 83, 73, 79, 78, 50, 0, 0]) {
                throw NSError(domain: "MagnistraHome", code: 5008,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Encrypted session is locked. Use LOG IN first."])
            }

            data = diskData
        }

        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with: data,
                    options: []
                )

        guard let root =
            object as? [String: Any]
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5003,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid session file."
                ]
            )
        }

        guard
            let format =
                root["format"] as? String,
            format ==
                "magnistra-session-v1"
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5004,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unsupported session format."
                ]
            )
        }

        guard
            let profile =
                root["profile"]
                    as? [String: Any],
            let userAgent =
                profile["userAgent"]
                    as? String,
            !userAgent.isEmpty
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5005,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Session profile is incomplete."
                ]
            )
        }

        guard
            let cookies =
                root["cookies"]
                    as? [[String: Any]]
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5006,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Session cookie jar is missing."
                ]
            )
        }

        let now =
            Date()
                .timeIntervalSince1970

        var pairs: [String] = []
        var csrfToken: String? = nil
        var sessionIDPresent = false

        for cookie in cookies {
            guard
                let name =
                    cookie["name"]
                        as? String,
                let value =
                    cookie["value"]
                        as? String,
                let domain =
                    cookie["domain"]
                        as? String,
                !name.isEmpty,
                isInstagramDomain(
                    domain
                )
            else {
                continue
            }

            if let expires =
                cookie["expires"]
                    as? NSNumber {
                let expiry =
                    expires.doubleValue

                if expiry > 0 &&
                   expiry <= now {
                    continue
                }
            }

            if name == "sessionid" {
                sessionIDPresent = true
            }

            if name == "csrftoken" &&
               !value.isEmpty {
                csrfToken = value
            }

            pairs.append(
                name + "=" + value
            )
        }

        guard
            sessionIDPresent,
            !pairs.isEmpty,
            let csrf = csrfToken,
            !csrf.isEmpty
        else {
            throw NSError(
                domain: "MagnistraHome",
                code: 5007,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram session is incomplete."
                ]
            )
        }

        return MagnistraSessionInput(
            userAgent: userAgent,
            language:
                (
                    profile["pageLanguage"]
                        as? String
                ) ?? "en-US",
            cookieHeader:
                pairs.joined(
                    separator: "; "
                ),
            csrfToken: csrf
        )
    }

    static func intValue(
        _ value: Any?
    ) -> Int? {
        if let number =
            value as? NSNumber {
            return number.intValue
        }

        if let string =
            value as? String {
            return Int(string)
        }

        return nil
    }

    static func stringValue(
        _ value: Any?
    ) -> String? {
        if let string =
            value as? String {
            return string
        }

        if let number =
            value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    static func boolValue(
        _ value: Any?
    ) -> Bool? {
        if let value =
            value as? Bool {
            return value
        }

        if let number =
            value as? NSNumber {
            return number.boolValue
        }

        return nil
    }

    static func doubleValue(
        _ value: Any?
    ) -> Double {
        if let number =
            value as? NSNumber {
            return number.doubleValue
        }

        if
            let string =
                value as? String,
            let result =
                Double(string)
        {
            return result
        }

        return 0
    }

    static func mediaObject(
        from row: [String: Any]
    ) -> [String: Any] {
        if let media =
            row["media_or_ad"]
                as? [String: Any] {
            return media
        }

        if let media =
            row["media"]
                as? [String: Any] {
            return media
        }

        return row
    }
}
