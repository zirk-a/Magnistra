// Overview: Direct: parsing messages into presentation models.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func directDeviceID()
        -> String
    {
        let defaults =
            UserDefaults.standard

        let key =
            "MagnistraDirectDeviceID"

        if
            let existing =
                defaults.string(
                    forKey:
                        key
                ),
            !existing.isEmpty
        {
            return existing
        }

        let uuid =
            CFUUIDCreate(
                nil
            )

        let raw =
            CFUUIDCreateString(
                nil,
                uuid
            ) as String

        let value =
            raw.lowercased()

        defaults.set(
            value,
            forKey:
                key
        )

        defaults.synchronize()

        return value
    }

    static func directMilliseconds(
        _ value: Any?
    ) -> Double {
        guard
            let raw =
                stringValue(
                    value
                ),
            let number =
                Double(
                    raw
                )
        else {
            return 0.0
        }

        return number
    }

    static func directMessageText(
        _ node: [String: Any]
    ) -> String {
        return
            directMessagePresentation(
                node
            ).text
    }

    static func directCleanString(
        _ value: Any?
    ) -> String? {
        guard
            let raw =
                value as? String
        else {
            return nil
        }

        let clean =
            raw.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        return
            clean.isEmpty
                ? nil
                : clean
    }

    static func directMessagePresentation(
        _ node: [String: Any]
    ) -> (
        text: String,
        detail: String?,
        previewURL: String?,
        contentType: String,
        audioURL: String?,
        audioDurationMilliseconds: Double,
        mediaURL: String?,
        targetURL: String?,
        mediaKind: String,
        audioWaveform: [Double],
        mediaAspectRatio: Double
    ) {
        let magTraceID = (node["message_id"] as? String) ?? (node["item_id"] as? String) ?? (node["id"] as? String) ?? ""
        MagnistraDirectMediaTrace.record("PARSE_ENTER", id: magTraceID, info: MagnistraDirectMediaTrace.describeNode(node))

        let contentType =
            directCleanString(
                node[
                    "content_type"
                ]
            ) ?? ""

        let content =
            node[
                "content"
            ] as? [String: Any]

        let xma =
            content?[
                "xma"
            ] as? [String: Any]

        let attachments =
            content?[
                "attachments"
            ] as? [[String: Any]] ??
            []

        let audioAttachments =
            content?[
                "audio_attachments"
            ] as? [[String: Any]] ??
            []

        let videos =
            content?[
                "videos"
            ] as? [[String: Any]] ??
            []

        let mediaFields = directMessageMediaFields(
            content: content,
            xma: xma,
            attachments: attachments,
            audioAttachments: audioAttachments,
            videos: videos
        )
        var previewURL = mediaFields.previewURL
        let audioURL = mediaFields.audioURL
        let audioDurationMilliseconds = mediaFields.audioDurationMilliseconds
        var mediaURL = mediaFields.mediaURL
        var targetURL = mediaFields.targetURL
        var mediaKind = mediaFields.mediaKind
        let audioWaveform = mediaFields.audioWaveform
        let mediaAspectRatio = mediaFields.mediaAspectRatio

        let textFields = directMessageTextFields(
            node: node,
            content: content,
            xma: xma,
            contentType: contentType,
            attachments: attachments,
            videos: videos,
            audioURL: audioURL,
            previewURL: &previewURL,
            mediaURL: &mediaURL,
            targetURL: &targetURL,
            mediaKind: &mediaKind
        )
        var primary = textFields.primary
        var detail = textFields.detail

        // Animated/sticker formats have several legacy payload layouts.
        updateDirectAnimatedPresentation(
            node: node,
            content: content,
            contentType: contentType,
            audioURL: audioURL,
            primary: &primary,
            detail: &detail,
            previewURL: &previewURL,
            mediaURL: &mediaURL,
            mediaKind: &mediaKind
        )

        MagnistraDirectMediaTrace.record("PARSE_EXIT", id: magTraceID,
            info: "preview=" + MagnistraDirectMediaTrace.urlTag(previewURL) +
                  ";media=" + MagnistraDirectMediaTrace.urlTag(mediaURL) +
                  ";audio=" + (audioURL == nil ? "no" : "yes") +
                  ";kind=" + (mediaKind.isEmpty ? "empty" :
                      (mediaKind == "photo" ? "photo" :
                      (mediaKind == "video" ? "video" : "other"))))

        if mediaKind == "photo",
           let payload = (content?["animated_media"] as? [[String: Any]])?.first,
           let stickerFlag = payload["is_sticker"] as? Bool {
            primary = stickerFlag ? "Sticker" : "GIF"
            detail = nil
        }

return (
            primary,
            detail,
            previewURL,
            contentType,
            audioURL,
            audioDurationMilliseconds,
            mediaURL,
            targetURL,
            mediaKind,
            audioWaveform,
            mediaAspectRatio
        )
    }

    // Keep all historical sticker/GIF fallbacks in their original priority order.
    // This mutates only the presentation fields, never the underlying message.
    private static func updateDirectAnimatedPresentation(
        node: [String: Any],
        content: [String: Any]?,
        contentType: String,
        audioURL: String?,
        primary: inout String,
        detail: inout String?,
        previewURL: inout String?,
        mediaURL: inout String?,
        mediaKind: inout String
    ) {
        if previewURL == nil && mediaURL == nil {
            let ct = contentType.lowercased()
            if ct.contains("sticker") || ct.contains("animated") || ct.contains("gif") {

                if let image = directFirstAnimatedCandidate(content?["animated_media"])
                    ?? directFirstAnimatedCandidate(content?["sticker"])
                    ?? directFirstAnimatedCandidate(node["animated_media"])
                    ?? directFirstAnimatedCandidate(node["sticker"])
                    ?? directFirstAnimatedCandidate(content?["xma"]) {
                    previewURL = image
                    mediaURL = image
                    mediaKind = "photo"
                    primary = ct.contains("sticker") ? "Sticker" : "GIF"
                    detail = nil
                }
            }
        }

        if mediaURL == nil && audioURL == nil {
            let ct = contentType.lowercased()
            let animatedByType = ct.contains("animated") || ct.contains("gif") || ct.contains("sticker")
            let animatedContent = content?["animated_media"] != nil || content?["sticker"] != nil
            let animatedGifs = content?["giphy"] != nil || content?["gif"] != nil
            let animatedNode = node["animated_media"] != nil || node["sticker"] != nil
            let isAnimated = animatedByType || animatedContent || animatedGifs || animatedNode
            if isAnimated {



                var animatedURL: String? = directLegacyAnimatedMedia(content?["animated_media"])
                if animatedURL == nil { animatedURL = directLegacyAnimatedMedia(content?["sticker"]) }
                if animatedURL == nil { animatedURL = directLegacyAnimatedMedia(content?["gif"]) }
                if animatedURL == nil { animatedURL = directLegacyAnimatedMedia(content?["giphy"]) }
                if animatedURL == nil { animatedURL = directLegacyAnimatedMedia(node["animated_media"]) }
                if animatedURL == nil { animatedURL = directLegacyAnimatedMedia(node["sticker"]) }
                if animatedURL == nil { animatedURL = directLegacyAnimatedMedia(content?["xma"]) }
                if animatedURL == nil { animatedURL = previewURL }
                if let url = animatedURL {
                    previewURL = url
                    mediaURL = url
                    let path = (URL(string: url)?.path ?? "").lowercased()
                    mediaKind = path.hasSuffix(".mp4") ? "video" : "photo"
                    primary = (ct.contains("sticker") || content?["sticker"] != nil) ? "Sticker" : "GIF"
                    detail = nil
                }
            }
        }

        let animatedType = contentType.lowercased()
        let isExplicitSticker = animatedType.contains("sticker") || content?["sticker"] != nil
            || node["sticker"] != nil || content?["sticker_info"] != nil
        let isExplicitGIF = animatedType.contains("gif") || animatedType.contains("animated")
            || content?["animated_media"] != nil || content?["giphy"] != nil
            || content?["gif"] != nil || node["animated_media"] != nil
        if audioURL == nil && (isExplicitSticker || isExplicitGIF) {


            let sources: [Any?] = [content?["animated_media"], content?["sticker"],
                content?["gif"], content?["giphy"], content?["sticker_info"],
                node["animated_media"], node["sticker"], node["gif"],
                content?["xma"], content?["attachments"]]
            var chosen: String? = nil
            for source in sources {
                if let url = directCompatibleAnimatedURL(source) { chosen = url; break }
            }
            if let raw = chosen {
                let urlPath = (URL(string: raw)?.path ?? "").lowercased()
                if !urlPath.hasSuffix(".mp4") && !urlPath.hasSuffix(".webm") {
                    previewURL = raw
                    mediaURL = raw
                    mediaKind = "photo"
                    primary = isExplicitSticker ? "Sticker" : "GIF"
                    detail = nil
                } else if previewURL == nil {

                    if let poster = directCompatibleAnimatedURL(content?["preview_image"])
                        ?? directCompatibleAnimatedURL(content?["sticker_info"]) {
                        previewURL = poster
                        mediaURL = poster
                        mediaKind = "photo"
                        primary = isExplicitSticker ? "Sticker" : "GIF"
                        detail = nil
                    }
                }
            } else if previewURL == nil, let oldMedia = mediaURL {

                previewURL = oldMedia
            }
        }

        let schemaType = ([contentType,
            directCleanString(node["item_type"]) ?? "",
            directCleanString(content?["item_type"]) ?? "",
            directCleanString(node["message_type"]) ?? ""])
            .joined(separator: " ").lowercased()
        let explicitSticker = schemaType.contains("sticker") ||
            node["sticker"] != nil || content?["sticker"] != nil ||
            node["sticker_info"] != nil || content?["sticker_info"] != nil ||
            node["sticker_data"] != nil || content?["sticker_data"] != nil
        let explicitAnimated = schemaType.contains("gif") ||
            schemaType.contains("animated") ||
            node["animated_media"] != nil || content?["animated_media"] != nil ||
            node["giphy"] != nil || content?["giphy"] != nil ||
            node["gif"] != nil || content?["gif"] != nil
        if audioURL == nil && !schemaType.contains("raven") &&
           (explicitSticker || explicitAnimated) {


            let mediaSources: [Any?] = [node["animated_media"],
                content?["animated_media"], node["sticker"], content?["sticker"],
                node["sticker_info"], content?["sticker_info"],
                node["sticker_data"], content?["sticker_data"],
                node["gif"], content?["gif"], node["giphy"], content?["giphy"],
                node["visual_media"], content?["visual_media"],
                node["media"], content?["media"],
                node["attachments"], content?["attachments"]]
            var mediaCandidate: String? = nil
            for value in mediaSources {
                if let found = directMediaImageCandidate(value) {
                    mediaCandidate = found
                    break
                }
            }

            if mediaCandidate == nil {
                mediaCandidate = directMediaImageCandidate(content) ?? directMediaImageCandidate(node)
            }
            if let image = mediaCandidate {
                previewURL = image
                mediaURL = image
                mediaKind = "photo"
                primary = explicitSticker ? "Sticker" : "GIF"
                detail = nil
            }
        }
    }

    // Stage 1: read media links and dimensions without classifying message text.
    // Preserve the priority of modern and legacy CDN URL fields.
    private static func directMessageMediaFields(
        content: [String: Any]?,
        xma: [String: Any]?,
        attachments: [[String: Any]],
        audioAttachments: [[String: Any]],
        videos: [[String: Any]]
    ) -> (
        previewURL: String?,
        audioURL: String?,
        audioDurationMilliseconds: Double,
        mediaURL: String?,
        targetURL: String?,
        mediaKind: String,
        audioWaveform: [Double],
        mediaAspectRatio: Double
    ) {
        var previewURL:
            String? =
                nil

        var audioURL:
            String? =
                nil

        var audioDurationMilliseconds:
            Double =
                0.0

        var mediaURL:
            String? =
                nil

        var targetURL:
            String? =
                nil

        var mediaKind =
            ""

        var audioWaveform:
            [Double] =
                []

        var mediaAspectRatio:
            Double =
                1.0

        func dimension(
            _ value:
                Any?
        ) -> Double {
            if let number = value as? NSNumber {
                return number.doubleValue
            }

            if
                let raw =
                    directCleanString(
                        value
                    ),
                let number =
                    Double(
                        raw
                    )
            {
                return number
            }

            return 0.0
        }

        func useDimensions(
            _ dictionary:
                [String: Any]?
        ) {
            guard
                let dictionary =
                    dictionary
            else {
                return
            }

            var width =
                dimension(
                    dictionary["width"]
                )

            var height =
                dimension(
                    dictionary["height"]
                )

            if
                (
                    width <= 0.0 ||
                    height <= 0.0
                ),
                let dimensions =
                    dictionary[
                        "image_dimensions"
                    ] as? [String: Any]
            {
                width =
                    dimension(
                        dimensions["width"]
                    )

                height =
                    dimension(
                        dimensions["height"]
                    )
            }

            if
                width > 0.0,
                height > 0.0
            {
                mediaAspectRatio =
                    max(
                        0.35,
                        min(
                            2.5,
                            width /
                            height
                        )
                    )
            }
        }

        if
            let preview =
                xma?[
                    "preview_image"
                ] as? [String: Any]
        {
            useDimensions(
                preview
            )

            previewURL =
                directCleanString(
                    preview[
                        "url"
                    ]
                ) ??
                directCleanString(
                    preview[
                        "fallback_url"
                    ]
                )
        }

        if
            previewURL == nil,
            let preview =
                xma?[
                    "xmaPreviewImage"
                ] as? [String: Any]
        {
            useDimensions(
                preview
            )

            previewURL =
                directCleanString(
                    preview[
                        "url"
                    ]
                ) ??
                directCleanString(
                    preview[
                        "fallback_url"
                    ]
                )
        }

        if
            let attachment =
                attachments.first
        {
            useDimensions(
                attachment
            )

            mediaURL =
                directCleanString(
                    attachment[
                        "attachment_cdn_url"
                    ]
                ) ??
                directCleanString(
                    attachment[
                        "attachment_cdn_fallback_url"
                    ]
                )

            if mediaURL != nil {
                mediaKind =
                    "photo"
            }
        }

        if
            let video =
                videos.first
        {
            useDimensions(
                video
            )

            mediaURL =
                directCleanString(
                    video[
                        "attachment_cdn_url"
                    ]
                ) ??
                directCleanString(
                    video[
                        "attachment_cdn_fallback_url"
                    ]
                )

            if mediaURL != nil {
                mediaKind =
                    "video"
            }
        }

        targetURL =
            directCleanString(
                xma?[
                    "target_url"
                ]
            ) ??
            directCleanString(
                xma?[
                    "action_url"
                ]
            ) ??
            directCleanString(
                content?[
                    "target_url"
                ]
            ) ??
            directCleanString(
                content?[
                    "action_url"
                ]
            )

        if
            previewURL == nil,
            let attachment =
                attachments.first
        {
            previewURL =
                directCleanString(
                    attachment[
                        "preview_cdn_url"
                    ]
                ) ??
                directCleanString(
                    attachment[
                        "preview_cdn_fallback_url"
                    ]
                ) ??
                directCleanString(
                    attachment[
                        "attachment_cdn_url"
                    ]
                ) ??
                directCleanString(
                    attachment[
                        "attachment_cdn_fallback_url"
                    ]
                )
        }

        if
            previewURL == nil,
            let video =
                videos.first
        {
            previewURL =
                directCleanString(
                    video[
                        "preview_cdn_url"
                    ]
                ) ??
                directCleanString(
                    video[
                        "preview_cdn_fallback_url"
                    ]
                )
        }

        if
            let audio =
                audioAttachments.first
        {
            mediaKind =
                "voice"

            if
                let waveform =
                    audio[
                        "waveform_data"
                    ] as? [NSNumber]
            {
                audioWaveform =
                    waveform.map {
                        $0.doubleValue
                    }
            } else if
                let waveform =
                    audio[
                        "waveform_data"
                    ] as? [Double]
            {
                audioWaveform =
                    waveform
            }

            audioURL =
                directCleanString(
                    audio[
                        "attachment_cdn_url"
                    ]
                )

            if
                let number =
                    audio[
                        "playable_duration_ms"
                    ] as? NSNumber
            {
                audioDurationMilliseconds =
                    number.doubleValue
            } else if
                let raw =
                    directCleanString(
                        audio[
                            "playable_duration_ms"
                        ]
                    ),
                let value =
                    Double(
                        raw
                    )
            {
                audioDurationMilliseconds =
                    value
            }
        }
        return (
            previewURL,
            audioURL,
            audioDurationMilliseconds,
            mediaURL,
            targetURL,
            mediaKind,
            audioWaveform,
            mediaAspectRatio
        )
    }


    // Stage 2: choose the visible title/detail. Unsupported disappearing messages
    // deliberately clear media references before animated-media fallbacks run.
    private static func directMessageTextFields(
        node: [String: Any],
        content: [String: Any]?,
        xma: [String: Any]?,
        contentType: String,
        attachments: [[String: Any]],
        videos: [[String: Any]],
        audioURL: String?,
        previewURL: inout String?,
        mediaURL: inout String?,
        targetURL: inout String?,
        mediaKind: inout String
    ) -> (primary: String, detail: String?) {
        let plain =
            directCleanString(
                node[
                    "text_body"
                ]
            )

        let xmaBody =
            directCleanString(
                content?[
                    "xma_text_body"
                ]
            )

        let deepText =
            directNestedMeaningfulText(
                content
            )

        let sharedHeaderCandidates:
            [String?] = [
                directCleanString(
                    xma?[
                        "header_title_text"
                    ]
                ),
                directCleanString(
                    xma?[
                        "xmaHeaderTitle"
                    ]
                ),
                directCleanString(
                    xma?[
                        "title_text"
                    ]
                ),
                directCleanString(
                    xma?[
                        "xmaTitle"
                    ]
                )
            ]

        var sharedHeaderTitle:
            String? =
                nil

        for candidate in sharedHeaderCandidates {
            if
                let value =
                    candidate,
                value.lowercased() !=
                    "message",
                value.lowercased() !=
                    "shared post",
                value.lowercased() !=
                    "shared reel"
            {
                sharedHeaderTitle =
                    value

                break
            }
        }

        let subtitle =
            directCleanString(
                xma?[
                    "subtitle_text"
                ]
            )

        let upperType =
            contentType
                .uppercased()

        var primary:
            String

        var detail:
            String? =
                nil

        if
            audioURL != nil
        {
            primary =
                "Voice message"

            detail =
                nil
        } else if
            upperType.contains(
                "RAVEN_IMAGE"
            )
        {
            primary =
                "Unsupported message"

            detail =
                nil

            previewURL =
                nil

            mediaURL =
                nil

            targetURL =
                nil

            mediaKind =
                ""
        } else if
            !attachments.isEmpty
        {
            primary =
                plain ??
                deepText ??
                "Photo"
        } else if
            !videos.isEmpty
        {
            primary =
                plain ??
                deepText ??
                "Video"
        } else if
            let value =
                plain,
            value.lowercased() !=
                "message"
        {
            primary =
                value
        } else if
            let value =
                xmaBody,
            value.lowercased() !=
                "message"
        {
            primary =
                value
        } else if
            let value =
                deepText,
            value.lowercased() !=
                "message"
        {
            primary =
                value
        } else if
            previewURL != nil ||
            xma != nil
        {
            primary =
                "Shared post"
        } else if
            let snippet =
                directCleanString(
                    node[
                        "igd_snippet"
                    ]
                ),
            snippet.lowercased() !=
                "message"
        {
            primary =
                snippet
        } else if
            upperType.contains(
                "RAVEN"
            )
        {
            primary =
                "Unsupported message"

            detail =
                nil

            previewURL =
                nil

            mediaURL =
                nil

            targetURL =
                nil

            mediaKind =
                ""
        } else {
            primary =
                contentType.isEmpty
                    ? "Unsupported message"
                    : contentType
                        .replacingOccurrences(
                            of:
                                "_",
                            with:
                                " "
                        )
                        .capitalized
        }

        let isSharedPayload =
            targetURL != nil ||
            (
                xma != nil &&
                previewURL != nil &&
                attachments.isEmpty &&
                videos.isEmpty &&
                audioURL == nil
            )

        if
            detail == nil,
            isSharedPayload
        {
            if
                let value =
                    sharedHeaderTitle,
                value != primary
            {
                detail =
                    value
            }
        } else if
            detail == nil,
            let value =
                subtitle,
            value != primary
        {
            detail =
                value
        }

        if
            mediaKind.isEmpty,
            targetURL != nil
        {
            mediaKind =
                "shared"
        }
        return (primary, detail)
    }
}
