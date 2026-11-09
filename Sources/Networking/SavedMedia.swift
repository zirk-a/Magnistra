// Overview: Saved media: rich posts, playable video and activity-referenced posts.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func loadSavedRichMedia(mediaID: String,
                                        shortcode: String) -> MagnistraRealPost? {
        let rawID = mediaID.split(separator: "_").first.map(String.init) ?? ""
        if !rawID.isEmpty && rawID.allSatisfy({ $0 >= "0" && $0 <= "9" }) {
            if let root = try? profileRESTFeedRoot(urls: [
                    "https://i.instagram.com/api/v1/media/" + rawID + "/info/",
                    "https://www.instagram.com/api/v1/media/" + rawID + "/info/"
                ]),
                let items = root["items"] as? [[String: Any]],
                let media = items.first,
                let rich = savedRichPost(media: media),
                rich.mediaID.split(separator: "_").first == mediaID.split(separator: "_").first {
                return rich
            }
        }
        if !shortcode.isEmpty,
           let post = try? loadActivityReferencedPost(shortcode: shortcode),
           post.mediaID.split(separator: "_").first == mediaID.split(separator: "_").first {
            return post
        }
        return nil
    }

    static func loadProfileRichOpenPost(original: MagnistraRealPost) throws -> MagnistraRealPost {
        let rawID = original.mediaID.split(separator: "_").first.map(String.init) ?? ""
        var richer: MagnistraRealPost? = nil
        if !rawID.isEmpty && rawID.allSatisfy({ $0 >= "0" && $0 <= "9" }) {
            if let root = try? profileRESTFeedRoot(urls: [
                "https://i.instagram.com/api/v1/media/" + rawID + "/info/",
                "https://www.instagram.com/api/v1/media/" + rawID + "/info/"
            ]), let items = root["items"] as? [[String: Any]],
               let media = items.first,
               let parsed = savedRichPost(media: media),
               parsed.mediaID.split(separator: "_").first == original.mediaID.split(separator: "_").first {
                richer = parsed
            }
        }

        var videoFallback: MagnistraRealPost? = nil
        if original.isVideo && richer?.videoURL == nil {
            videoFallback = try? loadSavedPlayableVideo(
                mediaID: original.mediaID, shortcode: original.shortcode)
        }
        guard let detail = richer ?? videoFallback else {
            throw NSError(domain: "MagnistraProfileMediaReady", code: 9570,
                userInfo: [NSLocalizedDescriptionKey: "Full media is currently unavailable."])
        }
        let playableURL = original.videoURL ?? detail.videoURL ?? videoFallback?.videoURL
        let musicURL = original.musicAudioURL ?? detail.musicAudioURL
        if original.isVideo && playableURL == nil {
            throw NSError(domain: "MagnistraProfileMediaReady", code: 9571,
                userInfo: [NSLocalizedDescriptionKey: "The video is not available yet."])
        }
        if (original.musicTitle != nil || original.musicArtist != nil) &&
           musicURL == nil && !original.isVideo {
            throw NSError(domain: "MagnistraProfileMediaReady", code: 9572,
                userInfo: [NSLocalizedDescriptionKey: "The music is not available yet."])
        }

        var updated = MagnistraRealPost(
            mediaID: original.mediaID, userID: original.userID,
            username: original.username, fullName: original.fullName,
            caption: original.caption, commentCount: original.commentCount,
            previewComments: original.previewComments, likes: original.likes,
            location: original.location, takenAt: original.takenAt,
            imagePath: original.imagePath, imageURL: original.imageURL,
            imageCacheKey: original.imageCacheKey,
            avatarPath: original.avatarPath, avatarURL: original.avatarURL,
            avatarCacheKey: original.avatarCacheKey,
            musicTitle: original.musicTitle ?? detail.musicTitle,
            musicArtist: original.musicArtist ?? detail.musicArtist,
            musicAudioURL: musicURL,
            musicStartTimeMs: original.musicAudioURL != nil
                ? original.musicStartTimeMs : detail.musicStartTimeMs,
            photoMusicImageURLFallback: original.photoMusicImageURLFallback ??
                detail.photoMusicImageURLFallback,
            videoURL: playableURL,
            videoWidth: playableURL == original.videoURL
                ? original.videoWidth : (videoFallback?.videoWidth ?? detail.videoWidth),
            videoHeight: playableURL == original.videoURL
                ? original.videoHeight : (videoFallback?.videoHeight ?? detail.videoHeight))
        updated.isVideo = original.isVideo || detail.isVideo || playableURL != nil
        updated.shortcode = original.shortcode
        updated.carouselMedia = original.carouselMedia.isEmpty
            ? detail.carouselMedia : original.carouselMedia
        return updated
    }

    static func loadSavedPlayableVideo(
        mediaID: String,
        shortcode: String
    ) throws -> MagnistraRealPost {
        let rawID = mediaID.split(separator: "_").first.map(String.init) ?? ""
        if !rawID.isEmpty && rawID.allSatisfy({ $0 >= "0" && $0 <= "9" }) {
            do {
                let root = try profileRESTFeedRoot(urls: [
                    "https://i.instagram.com/api/v1/media/" + rawID + "/info/",
                    "https://www.instagram.com/api/v1/media/" + rawID + "/info/"
                ])
                if let items = root["items"] as? [[String: Any]],
                    let media = items.first,
                    let post = activityReferencePost(
                        media: media, actorUser: nil, actorAvatarURL: nil
                    ), post.videoURL != nil,
                    post.mediaID.split(separator: "_").first == mediaID.split(separator: "_").first {
                    return post
                }
            } catch {

            }
        }
        if !shortcode.isEmpty {
            let post = try loadActivityReferencedPost(shortcode: shortcode)
            if post.videoURL != nil &&
                post.mediaID.split(separator: "_").first == mediaID.split(separator: "_").first { return post }
        }
        throw NSError(domain: "MagnistraSavedVideo", code: 9543,
            userInfo: [NSLocalizedDescriptionKey: "Saved video unavailable"])
    }

    static func loadActivityReferencedPost(
        shortcode:
            String
    ) throws -> MagnistraRealPost {
        guard !shortcode.isEmpty else {
            throw NSError(
                domain: "MagnistraActivity",
                code: 7130,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Referenced post shortcode is unavailable."
                ]
            )
        }

        let strategies =
            MagnistraInstagramCompatibility
                .graphqlStrategies(
                    for: .activityPost
                )

        var lastError: NSError? = nil

        for strategy in strategies {
            var variables =
                strategy.staticVariables

            variables["shortcode"] = shortcode

            do {
                let root =
                    try exploreSearchGraphQLRoot(
                        variables: variables,
                        docID: strategy.docID,
                        friendlyName:
                            strategy.friendlyName
                    )

                let dataRoot =
                    root["data"]
                        as? [String: Any]

                let webInfo =
                    dataRoot?[
                        "xdt_api__v1__media__shortcode__web_info"
                    ] as? [String: Any]

                let directItem =
                    (
                        webInfo?["items"]
                            as? [[String: Any]]
                    )?.first

                let media =
                    directItem ??
                    activityFindMedia(
                        root
                    )

                if
                    let post =
                        activityReferencePost(
                            media: media,
                            actorUser: nil,
                            actorAvatarURL: nil
                        )
                {
                    return post
                }

                let errors =
                    root["errors"]
                        as? [[String: Any]]

                let firstError =
                    errors?.first?["message"]
                        as? String

                lastError = NSError(
                    domain: "MagnistraActivity",
                    code: 7135,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            firstError ??
                            (
                                "Activity strategy " +
                                strategy.identifier +
                                " returned no usable post."
                            )
                    ]
                )
            }
            catch {
                lastError = error as NSError
            }
        }

        throw lastError ?? NSError(
            domain: "MagnistraActivity",
            code: 7136,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "No usable Instagram Activity post contract is available."
            ]
        )
    }

    static func loadActivity()
        throws -> MagnistraActivityPage
    {
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
                    "MagnistraActivity",
                code:
                    7101,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "CA bundle unavailable."
                ]
            )
        }

        let curlCode:
            Int32 =
                caPath.withCString { ca in
                    session.userAgent
                        .withCString { ua in
                            session.language
                                .withCString { lang in
                                    session.cookieHeader
                                        .withCString { cookies in
                                            session.csrfToken
                                                .withCString { csrf in
                                                    Int32(
                                                        magnistra_activity_fetch(
                                                            ca,
                                                            ua,
                                                            lang,
                                                            cookies,
                                                            csrf
                                                        )
                                                    )
                                                }
                                        }
                                }
                        }
                }

        let status =
            magnistra_activity_http_status()

        let serverErrorDetail:
            String? = {
                let length =
                    Int(
                        magnistra_activity_body_length()
                    )

                guard
                    length > 0,
                    let pointer =
                        magnistra_activity_body()
                else {
                    return nil
                }

                let data =
                    Data(
                        bytes:
                            pointer,
                        count:
                            length
                    )

                guard
                    let object =
                        try?
                            MagnistraJSONKit
                                .jsonObject(
                                    with:
                                        data,
                                    options:
                                        []
                                ),
                    let dictionary =
                        object as?
                            [String: Any]
                else {
                    return nil
                }

                var fields:
                    [String] = []

                for key in [
                    "message",
                    "error_type",
                    "status"
                ] {
                    if
                        let value =
                            dictionary[key]
                                as? String,
                        !value.isEmpty
                    {
                        fields.append(
                            key +
                            "=" +
                            value
                        )
                    }
                }

                if fields.isEmpty {
                    return nil
                }

                return fields
                    .joined(
                        separator:
                            ", "
                    )
            }()

        guard
            curlCode == 0,
            status >= 200,
            status < 300,
            magnistra_activity_tls_verify_result()
                == 0
        else {
            throw NSError(
                domain:
                    "MagnistraActivity",
                code:
                    7102,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Couldn’t load Activity (HTTP " +
                        String(status) +
                        (
                            serverErrorDetail
                                .map {
                                    ", " +
                                    $0
                                } ??
                            ""
                        ) +
                        ")."
                ]
            )
        }

        let length =
            Int(
                magnistra_activity_body_length()
            )

        guard
            length > 0,
            let pointer =
                magnistra_activity_body()
        else {
            return MagnistraActivityPage(
                items: []
            )
        }

        let data =
            Data(
                bytes:
                    pointer,
                count:
                    length
            )

        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with:
                        data,
                    options:
                        []
                )

        guard
            let root =
                object as?
                    [String: Any]
        else {
            throw NSError(
                domain:
                    "MagnistraActivity",
                code:
                    7103,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Activity response was not JSON."
                ]
            )
        }

        var rawStories:
            [[String: Any]] = []

        for key in [
            "new_stories",
            "old_stories",
            "friend_request_stories"
        ] {
            if
                let stories =
                    root[key]
                        as? [[String: Any]]
            {
                rawStories.append(
                    contentsOf:
                        stories
                )
            }
        }

        var seen =
            Set<String>()

        var items:
            [MagnistraActivityItem] = []

        for story in rawStories {
            guard
                let item =
                    parseActivityStory(
                        story
                    )
            else {
                continue
            }

            if seen.contains(
                item.activityID
            ) {
                continue
            }

            seen.insert(
                item.activityID
            )

            items.append(
                item
            )
        }

        items.sort {
            $0.createdAt >
                $1.createdAt
        }

        return MagnistraActivityPage(
            items:
                items
        )
    }
}
