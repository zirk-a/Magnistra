// Instagram Direct media lookup helpers extracted from DirectMessageParsing.swift.
import Foundation


// Pure helpers extracted from directMessagePresentation; fallback precedence unchanged.
extension MagnistraHomeService {

    static func directNestedMeaningfulText(
        _ value: Any?,
        depth:
            Int = 0
    ) -> String? {
        guard
            depth <= 6
        else {
            return nil
        }

        if
            let dictionary =
                value as? [String: Any]
        {
            let preferredKeys = [
                "text_body",
                "xma_text_body",
                "text",
                "title_text",
                "title",
                "subtitle_text",
                "subtitle",
                "header_title_text",
                "description"
            ]

            for key in preferredKeys {
                if
                    let candidate =
                        directCleanString(
                            dictionary[
                                key
                            ]
                        ),
                    candidate.lowercased() !=
                        "message"
                {
                    return
                        candidate
                }
            }

            for nested in dictionary.values {
                if
                    let candidate =
                        directNestedMeaningfulText(
                            nested,
                            depth:
                                depth + 1
                        )
                {
                    return
                        candidate
                }
            }
        } else if
            let array =
                value as? [Any]
        {
            for nested in array {
                if
                    let candidate =
                        directNestedMeaningfulText(
                            nested,
                            depth:
                                depth + 1
                        )
                {
                    return
                        candidate
                }
            }
        }

        return nil
    }

    static func directFirstAnimatedCandidate(_ value: Any?, depth: Int = 0) -> String? {
        if depth > 5 { return nil }
        if let obj = value as? [String: Any] {
            for key in ["url", "image_url", "gif_url", "preview_image_url", "cdn_url"] {
                if let raw = obj[key] as? String, let u = URL(string: raw),
                   u.scheme?.lowercased() == "https", let host = u.host?.lowercased(),
                   (host.hasSuffix(".fbcdn.net") || host.hasSuffix(".instagram.com") ||
                    host.hasSuffix(".giphy.com") || host.hasSuffix(".tenor.com")) {
                    return raw
                }
            }
            for key in ["animated_media", "sticker", "images", "fixed_height",
                        "fixed_width", "original", "preview_image", "xma"] {
                if let found = directFirstAnimatedCandidate(obj[key], depth: depth + 1) { return found }
            }
        }
        return nil
    }

    static func directLegacyAnimatedURL(_ value: Any?) -> String? {
        guard let raw = value as? String, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased()
        else { return nil }
        let allowed = [".fbcdn.net", ".instagram.com", ".giphy.com",
                       ".tenor.com", ".giphyusercontent.com"]
        guard allowed.contains(where: { host.hasSuffix($0) }) else { return nil }
        return raw
    }

    static func directLegacyAnimatedMedia(_ obj: Any?, depth: Int = 0) -> String? {
        if depth > 7 { return nil }
        if let dict = obj as? [String: Any] {
            for key in ["gif_url", "animated_url", "attachment_cdn_url", "image_url",
                        "preview_cdn_url", "preview_image_url", "preview_url",
                        "media_url", "url", "uri", "src"] {
                if let value = directLegacyAnimatedURL(dict[key]) { return value }
            }
            for key in ["animated_media", "sticker", "sticker_info", "gif", "giphy",
                        "images", "original", "fixed_height", "fixed_width",
                        "preview_image", "media", "media_info", "renditions", "xma"] {
                if let value = directLegacyAnimatedMedia(dict[key], depth: depth + 1) { return value }
            }
        } else if let array = obj as? [Any] {
            for item in array.prefix(8) {
                if let value = directLegacyAnimatedMedia(item, depth: depth + 1) { return value }
            }
        }
        return nil
    }

    static func directCompatibleAnimatedURL(_ value: Any?, depth: Int = 0) -> String? {
        if depth > 7 { return nil }
        if let raw = value as? String,
           let url = URL(string: raw),
           url.scheme?.lowercased() == "https",
           let host = url.host?.lowercased() {
            let domains = ["instagram.com", "cdninstagram.com", "fbcdn.net",
                           "giphy.com", "giphyusercontent.com", "tenor.com", "tenor.co"]
            if domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return raw
            }
        }
        if let dict = value as? [String: Any] {
            let urlKeys = ["gif_url", "image_url", "animated_url", "url",
                           "attachment_cdn_url", "preview_cdn_url", "media_url",
                           "preview_image_url", "preview_url", "src", "uri",
                           "fallback_url", "attachment_cdn_fallback_url"]
            for key in urlKeys {
                if let result = directCompatibleAnimatedURL(dict[key], depth: depth + 1) { return result }
            }
            let nestedKeys = ["gif", "animated_media", "sticker", "sticker_info",
                              "images", "fixed_height", "fixed_width", "original",
                              "preview_image", "renditions", "media", "media_info", "xma"]
            for key in nestedKeys {
                if let result = directCompatibleAnimatedURL(dict[key], depth: depth + 1) { return result }
            }
        } else if let array = value as? [Any] {
            for item in array.prefix(12) {
                if let result = directCompatibleAnimatedURL(item, depth: depth + 1) { return result }
            }
        }
        return nil
    }

    static func directSafeImageURL(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let normalized = raw.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: normalized),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return nil }
        let domains = ["instagram.com", "cdninstagram.com", "fbcdn.net",
                       "giphy.com", "giphyusercontent.com", "tenor.com",
                       "tenor.co"]
        guard domains.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return nil }
        let path = url.path.lowercased()
        if path.hasSuffix(".mp4") || path.hasSuffix(".webm") ||
           path.hasSuffix(".mov") || path.hasSuffix(".m3u8") {
            return nil
        }
        return normalized
    }

    static func directMediaImageCandidate(_ value: Any?, depth: Int = 0) -> String? {
        if depth > 9 { return nil }
        if let imageURL = directSafeImageURL(value) { return imageURL }
        if let dict = value as? [String: Any] {

            let keys = ["gif_url", "gifUrl", "sticker_url", "stickerUrl",
                        "animated_url", "animatedUrl", "image_url", "imageUrl",
                        "preview_image_url", "previewImageUrl", "thumbnail_url",
                        "thumbnailUrl", "display_url", "displayUrl",
                        "attachment_cdn_url", "attachment_cdn_fallback_url",
                        "preview_cdn_url", "preview_cdn_fallback_url",
                        "url", "uri", "src", "fallback_url"]
            for key in keys {
                if let found = directSafeImageURL(dict[key]) { return found }
            }

            let branches = ["images", "image_versions2", "imageVersions2",
                            "candidates", "fixed_height", "fixed_width", "downsized",
                            "original", "media", "media_info", "visual_media",
                            "image", "preview_image", "poster", "thumbnail",
                            "sticker", "sticker_info", "sticker_data", "stickers",
                            "animated_media", "animatedMedia", "gif", "giphy",
                            "renditions", "attachments", "items", "payload",
                            "content", "image_versions"]
            for key in branches {
                if let result = directMediaImageCandidate(dict[key], depth: depth + 1) { return result }
            }
        } else if let items = value as? [Any] {
            for item in items.prefix(12) {
                if let result = directMediaImageCandidate(item, depth: depth + 1) { return result }
            }
        }
        return nil
    }

}
