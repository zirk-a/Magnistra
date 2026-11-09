// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room event model, parsing and time formatting.
import Foundation

private enum MagnistraMediaTraceState {
    static var initialized = false
}

func magnistraMediaTrace(_ message: String) {
    guard let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return }
    let path = (docs as NSString).appendingPathComponent("magnistra-media.log")
    let fm = FileManager.default
    if !MagnistraMediaTraceState.initialized {
        _ = fm.createFile(atPath: path, contents: Data(), attributes: nil)
        MagnistraMediaTraceState.initialized = true
    }
    let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
    guard let bytes = (stamp + " " + message + "\n").data(using: .utf8) else { return }
    if !fm.fileExists(atPath: path) {
        _ = fm.createFile(atPath: path, contents: nil, attributes: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    handle.seekToEndOfFile()
    handle.write(bytes)
    handle.closeFile()
}

enum TimeFormat {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    private static let sameYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let otherYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static func shortTime(msSinceEpoch: Double) -> String {
        guard msSinceEpoch > 0 else { return "" }
        return formatter.string(from: Date(timeIntervalSince1970: msSinceEpoch / 1000))
    }

    static func dayKey(msSinceEpoch: Double) -> String {
        guard msSinceEpoch > 0 else { return "" }
        return dayKeyFormatter.string(from: Date(timeIntervalSince1970: msSinceEpoch / 1000))
    }

    static func dateHeader(msSinceEpoch: Double) -> String {
        guard msSinceEpoch > 0 else { return "" }
        let date = Date(timeIntervalSince1970: msSinceEpoch / 1000)
        let now = Date()
        let key = dayKeyFormatter.string(from: date)
        if key == dayKeyFormatter.string(from: now) { return "Today" }
        if key == dayKeyFormatter.string(from: Date(timeIntervalSinceNow: -86400)) { return "Yesterday" }
        let sameYear = yearFormatter.string(from: date) == yearFormatter.string(from: now)
        return (sameYear ? sameYearFormatter : otherYearFormatter).string(from: date)
    }

    static func listStamp(msSinceEpoch: Double) -> String {
        guard msSinceEpoch > 0 else { return "" }
        let date = Date(timeIntervalSince1970: msSinceEpoch / 1000)
        let key = dayKeyFormatter.string(from: date)
        if key == dayKeyFormatter.string(from: Date()) {
            return shortTime(msSinceEpoch: msSinceEpoch)
        }
        for daysAgo in 1...6 {
            let past = Date(timeIntervalSinceNow: -86400 * Double(daysAgo))
            if key == dayKeyFormatter.string(from: past) {
                return weekdayFormatter.string(from: date)
            }
        }

        return key
    }
}

struct VideoAttachment {
    let mxc: String
    let thumbnailMxc: String?
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let width: Int
    let height: Int
    let durationMs: Int

    let isAnimated: Bool
}

struct RoomEvent {
    enum Kind {
        case message(sender: String, body: String, isEmote: Bool)

        case image(sender: String, caption: String, mxc: String, width: Int, height: Int)

        case audio(sender: String, mxc: String, durationMs: Int, caption: String)

        case file(sender: String, mxc: String, filename: String, mimeType: String, sizeBytes: Int)

        case video(sender: String, video: VideoAttachment)
        case membership(description: String)

        case reaction(sender: String, targetEventId: String, key: String)

        case redaction(targetEventId: String)

        case edit(sender: String, targetEventId: String, body: String)
    }

    let eventId: String
    let kind: Kind
    let timestamp: Double

    var replyTo: String? = nil
    var replyQuote: String? = nil
    var replyAuthor: String? = nil

    var bundledReactions: [(key: String, count: Int)] = []

    var transactionId: String? = nil

    static func parse(_ json: [String: Any]) -> RoomEvent? {
        guard var event = parseEvent(json) else { return nil }
        event.bundledReactions = parseBundledReactions(json)
        event.transactionId = (json["unsigned"] as? [String: Any])?["transaction_id"] as? String
        return event
    }

    private static func parseEvent(_ json: [String: Any]) -> RoomEvent? {
        guard let eventId = json["event_id"] as? String,
              let type = json["type"] as? String,
              let sender = json["sender"] as? String else { return nil }
        let timestamp = (json["origin_server_ts"] as? NSNumber)?.doubleValue ?? 0

        switch type {
        case "m.room.message":
            guard let content = json["content"] as? [String: Any] else { return nil }
            let relates = content["m.relates_to"] as? [String: Any]

            if let relates = relates,
               relates["rel_type"] as? String == "m.replace",
               let target = relates["event_id"] as? String {

                var newBody = (content["m.new_content"] as? [String: Any])?["body"] as? String ?? ""
                if newBody.isEmpty {
                    newBody = content["body"] as? String ?? ""
                    if newBody.hasPrefix("* ") { newBody.removeFirst(2) }
                }
                if RoomEvent.isBlank(newBody) { return nil }
                return RoomEvent(eventId: eventId,
                                  kind: .edit(sender: sender, targetEventId: target, body: newBody),
                                  timestamp: timestamp)
            }

            var body = content["body"] as? String ?? ""
            var replyTo: String?
            var replyQuote: String?
            var replyAuthor: String?

            if let inReplyTo = relates?["m.in_reply_to"] as? [String: Any],
               let target = inReplyTo["event_id"] as? String {
                replyTo = target
                let split = RoomEvent.splitReplyFallback(body)
                replyAuthor = split.author
                replyQuote = split.quote
                body = split.rest
            }

            guard let kind = RoomEvent.messageKind(content: content, sender: sender, body: body) else {
                return nil
            }
            return RoomEvent(eventId: eventId, kind: kind, timestamp: timestamp,
                              replyTo: replyTo, replyQuote: replyQuote, replyAuthor: replyAuthor)

        case "m.room.encrypted":
            if let decrypted = MatrixE2EEManager.shared.decryptRoomEvent(json) {
                return RoomEvent.parse(decrypted)
            }

            return RoomEvent(eventId: eventId,
                              kind: .message(sender: sender,
                                             body: MatrixE2EEManager.shared.runtimeStatusText(),
                                             isEmote: false),
                              timestamp: timestamp)

        case "m.reaction":
            guard let content = json["content"] as? [String: Any],
                  let relates = content["m.relates_to"] as? [String: Any],
                  relates["rel_type"] as? String == "m.annotation",
                  let target = relates["event_id"] as? String,
                  let key = relates["key"] as? String, !key.isEmpty else { return nil }
            return RoomEvent(eventId: eventId,
                              kind: .reaction(sender: sender, targetEventId: target, key: key),
                              timestamp: timestamp)

        case "m.room.redaction":

            let target = (json["redacts"] as? String)
                ?? ((json["content"] as? [String: Any])?["redacts"] as? String)
            guard let redacted = target else { return nil }
            return RoomEvent(eventId: eventId, kind: .redaction(targetEventId: redacted),
                              timestamp: timestamp)

        case "m.room.member":
            guard let content = json["content"] as? [String: Any],
                  let membership = content["membership"] as? String else { return nil }
            let name = (content["displayname"] as? String) ?? sender
            let description: String
            switch membership {
            case "join": description = "\(name) joined the room"
            case "leave": description = "\(name) left the room"
            case "invite": description = "\(name) was invited"
            case "ban": description = "\(name) was banned"
            default: description = "\(name): \(membership)"
            }
            return RoomEvent(eventId: eventId, kind: .membership(description: description), timestamp: timestamp)

        case "m.sticker":

            guard let content = json["content"] as? [String: Any],
                  let mxc = content["url"] as? String,
                  mxc.hasPrefix("mxc://") else { return nil }
            let info = content["info"] as? [String: Any]

            let caption = "__magnistra_sticker__"

            let stickerMime = (info?["mimetype"] as? String ?? "").lowercased()
            let stickerName = (content["body"] as? String ?? "").lowercased()
            let stickerExt = (stickerName as NSString).pathExtension

            MediaCache.shared.registerStickerInfo(
                mxc: mxc,
                filename: (content["body"] as? String) ?? "sticker",
                mimeType: stickerMime
            )
            magnistraMediaTrace("STICKER mime=\(stickerMime) ext=\(stickerExt)")

            let sourceW = (info?["w"] as? NSNumber)?.intValue ?? 0
            let sourceH = (info?["h"] as? NSNumber)?.intValue ?? 0
            let stickerMaxSide = 112
            var stickerW = sourceW
            var stickerH = sourceH

            if stickerW <= 0 || stickerH <= 0 {
                stickerW = stickerMaxSide
                stickerH = stickerMaxSide
            } else if stickerW > stickerMaxSide || stickerH > stickerMaxSide {
                if stickerW >= stickerH {
                    stickerH = max(1, stickerH * stickerMaxSide / stickerW)
                    stickerW = stickerMaxSide
                } else {
                    stickerW = max(1, stickerW * stickerMaxSide / stickerH)
                    stickerH = stickerMaxSide
                }
            }

            return RoomEvent(
                eventId: eventId,
                kind: .image(
                    sender: sender,
                    caption: caption,
                    mxc: mxc,
                    width: stickerW,
                    height: stickerH
                ),
                timestamp: timestamp
            )

        default:
            return nil
        }
    }

    private static func messageKind(content: [String: Any], sender: String, body: String) -> Kind? {
        let msgtype = content["msgtype"] as? String ?? "m.text"

        let imageInfo = content["info"] as? [String: Any]
        let imageMime = imageInfo?["mimetype"] as? String ?? ""
        let lowerBody = body.lowercased()
        let bridgeImageLike = (msgtype == "m.video" || msgtype == "m.file")
            && (imageMime.hasPrefix("image/")
                || lowerBody.hasSuffix(".gif")
                || lowerBody.hasSuffix(".webp"))
        if (msgtype == "m.image" || bridgeImageLike),
           let mxc = content["url"] as? String,
           mxc.hasPrefix("mxc://") {
            let w = (imageInfo?["w"] as? NSNumber)?.intValue ?? 0
            let h = (imageInfo?["h"] as? NSNumber)?.intValue ?? 0
            let lowerMime = imageMime.lowercased()
            let isGifImage = lowerMime == "image/gif" || lowerBody.hasSuffix(".gif")
            let imageCaption = isGifImage ? "__magnistra_gif__" : body
            let imageExt = (lowerBody as NSString).pathExtension
            magnistraMediaTrace(
                "IMAGE_CLASS msgtype=\(msgtype.lowercased()) mime=\(lowerMime) ext=\(imageExt) gif=\(isGifImage ? "YES" : "NO") bridge=\(bridgeImageLike ? "YES" : "NO")"
            )
            return .image(sender: sender, caption: imageCaption, mxc: mxc, width: w, height: h)
        }

        if msgtype == "m.audio", let mxc = content["url"] as? String, mxc.hasPrefix("mxc://") {
            let info = content["info"] as? [String: Any]
            let dur = (info?["duration"] as? NSNumber)?.intValue ?? 0
            return .audio(sender: sender, mxc: mxc, durationMs: dur, caption: body)
        }

        if msgtype == "m.file" || msgtype == "m.video",
           let mxc = content["url"] as? String, mxc.hasPrefix("mxc://") {
            let info = content["info"] as? [String: Any]
            let mime = info?["mimetype"] as? String ?? ""
            let size = (info?["size"] as? NSNumber)?.intValue ?? 0
            let name = RoomEvent.isBlank(body) ? "Attachment" : body
            if msgtype == "m.video" {

                func truthyAnimatedMarker(_ value: Any) -> Bool {
                    if let value = value as? Bool { return value }
                    if let value = value as? NSNumber { return value.boolValue }
                    if let value = value as? String {
                        let s = value.lowercased()
                        return s == "1" || s == "true" || s == "yes"
                            || s == "gif" || s == "animated"
                    }
                    return false
                }

                var bridgeAnimated = false
                func scanAnimatedMarkers(_ object: [String: Any]) {
                    for (key, value) in object {
                        let k = key.lowercased()
                        if (k.contains("gif") || k.contains("animated")),
                           truthyAnimatedMarker(value) {
                            bridgeAnimated = true
                        }
                        if let nested = value as? [String: Any] {
                            for (nestedKey, nestedValue) in nested {
                                let nk = nestedKey.lowercased()
                                if (nk.contains("gif") || nk.contains("animated")),
                                   truthyAnimatedMarker(nestedValue) {
                                    bridgeAnimated = true
                                }
                            }
                        }
                    }
                }

                scanAnimatedMarkers(content)
                if let info = info { scanAnimatedMarkers(info) }

                let animationName = ((content["filename"] as? String) ?? name).lowercased()
                if animationName.hasSuffix(".gif.mp4")
                    || animationName.hasSuffix(".gif.mov")
                    || animationName.contains(".gif.")
                    || animationName.contains("animation")
                    || animationName.contains("animated") {

                    bridgeAnimated = true
                }

                let mediaExt = (name.lowercased() as NSString).pathExtension
                magnistraMediaTrace(
                    "VIDEO_CLASS mime=\(mime.lowercased()) ext=\(mediaExt) animated=\(bridgeAnimated ? "YES" : "NO") durationMs=\((info?["duration"] as? NSNumber)?.intValue ?? 0)"
                )

                if bridgeAnimated {
                    MediaCache.shared.registerVideoBackedAnimated(
                        mxc: mxc,
                        filename: name,
                        mimeType: mime
                    )
                    return .image(
                        sender: sender,
                        caption: "__magnistra_whatsapp_webp__",
                        mxc: mxc,
                        width: (info?["w"] as? NSNumber)?.intValue ?? 0,
                        height: (info?["h"] as? NSNumber)?.intValue ?? 0
                    )
                }

                var thumb = info?["thumbnail_url"] as? String
                if thumb?.hasPrefix("mxc://") != true { thumb = nil }
                let video = VideoAttachment(mxc: mxc, thumbnailMxc: thumb, filename: name,
                                            mimeType: mime, sizeBytes: size,
                                            width: (info?["w"] as? NSNumber)?.intValue ?? 0,
                                            height: (info?["h"] as? NSNumber)?.intValue ?? 0,
                                            durationMs: (info?["duration"] as? NSNumber)?.intValue ?? 0,
                                            isAnimated: false)
                return .video(sender: sender, video: video)
            }
            return .file(sender: sender, mxc: mxc, filename: name, mimeType: mime, sizeBytes: size)
        }
        let isEmote = msgtype == "m.emote"

        if !isEmote, RoomEvent.isBlank(body) { return nil }
        return .message(sender: sender, body: body, isEmote: isEmote)
    }

    static func splitReplyFallback(_ body: String) -> (author: String?, quote: String?, rest: String) {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var quoted: [String] = []
        while index < lines.count, lines[index].hasPrefix(">") {
            var line = String(lines[index].dropFirst())
            if line.hasPrefix(" ") { line.removeFirst() }
            quoted.append(line)
            index += 1
        }

        guard !quoted.isEmpty else { return (nil, nil, body) }
        if index < lines.count, lines[index].isEmpty { index += 1 }
        let rest = lines[index...].joined(separator: "\n")

        var author: String?
        var first = quoted[0]
        if first.hasPrefix("<"), let close = first.firstIndex(of: ">") {
            author = String(first[first.index(after: first.startIndex)..<close])
            first = String(first[first.index(after: close)...])
            if first.hasPrefix(" ") { first.removeFirst() }
            quoted[0] = first
        }

        let quote = quoted.joined(separator: " ")
        return (author, RoomEvent.isBlank(quote) ? nil : quote, rest)
    }

    private static func parseBundledReactions(_ json: [String: Any]) -> [(key: String, count: Int)] {
        guard let unsigned = json["unsigned"] as? [String: Any],
              let relations = unsigned["m.relations"] as? [String: Any],
              let annotation = relations["m.annotation"] as? [String: Any],
              let chunk = annotation["chunk"] as? [[String: Any]] else { return [] }
        var result: [(key: String, count: Int)] = []
        for entry in chunk {
            guard (entry["type"] as? String) == "m.reaction",
                  let key = entry["key"] as? String, !key.isEmpty,
                  let count = (entry["count"] as? NSNumber)?.intValue, count > 0 else { continue }
            result.append((key: key, count: count))
        }
        return result
    }

    static func isBlank(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20,
                 0x85, 0xA0,
                 0x2000...0x200A, 0x2028, 0x2029,
                 0x202F, 0x205F, 0x3000,
                 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF:
                continue
            default:
                return false
            }
        }
        return true
    }
}
