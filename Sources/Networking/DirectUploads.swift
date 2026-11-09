// Overview: Direct: uploading and sending attachments.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func directUploadAttachment(
        filePath:
            String,
        fileName:
            String,
        mimeType:
            String,
        voiceClip: Bool,
        waveform: [Double] = []
    ) throws -> String {

        let actualPath: String
        let actualMIME: String
        let actualName: String
        if voiceClip {
            let destination = (filePath as NSString).deletingPathExtension + ".ogg"
            let encodeStatus: Int32 = filePath.withCString { source in
                destination.withCString { output in
                    magnistraDirectVoiceWAVToOGG(source, output)
                }
            }
            guard encodeStatus == 0 else {
                throw NSError(domain: "MagnistraDirectMedia", code: 7600 + Int(abs(encodeStatus)),
                    userInfo: [NSLocalizedDescriptionKey:
                        "Voice Ogg/Opus conversion failed (stage \(encodeStatus)). No message was sent."])
            }
            actualPath = destination
            actualMIME = "audio/ogg"
            actualName = "voice.ogg"
        } else {
            actualPath = filePath
            actualMIME = mimeType
            actualName = fileName
        }
        guard let fileBytes = NSData(contentsOfFile: actualPath) else {
            throw NSError(domain: "MagnistraDirectMedia", code: 7111,
                userInfo: [NSLocalizedDescriptionKey: "Selected media could not be read."])
        }
        let payload = Data(bytes: fileBytes.bytes, count: fileBytes.length)

        return try magnistraWebUploadAttachment(data: payload,
            mime: actualMIME, filename: actualName,
            isVoice: voiceClip, waveform: waveform)
    }

    static func sendDirectAttachment(
        threadFBID:
            String,
        minUQSeqID:
            Int,
        filePath:
            String,
        fileName:
            String,
        mimeType:
            String,
        voiceClip: Bool,
        waveform: [Double] = []
    ) throws -> MagnistraDirectSendResult {
        _ =
            minUQSeqID

        let attachmentFBID =
            try directUploadAttachment(
                filePath:
                    filePath,
                fileName:
                    fileName,
                mimeType:
                    mimeType,
                voiceClip: voiceClip,
                waveform: waveform
            )

        let variables:
            [String: Any] = [
                "attachment_fbid":
                    attachmentFBID,
                "forwarded_from_thread_id":
                    NSNull(),
                "is_forwarded_from_own_message":
                    NSNull(),
                "offline_threading_id":
                    directOfflineThreadingID(),
                "reply_to_message_id":
                    NSNull(),
                "thread_id":
                    threadFBID
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "25766288509716264",
                friendlyName:
                    "IGDirectMediaSendMutation"
            )

        guard
            let data =
                root[
                    "data"
                ] as?
                    [String: Any],
            let response =
                data[
                    "xig_direct_media_send_with_slide_messaging_response"
                ] as?
                    [String: Any],
            let messageID =
                stringValue(
                    response[
                        "message_id"
                    ]
                ) ??
                stringValue(
                    response[
                        "id"
                    ]
                ),
            !messageID.isEmpty
        else {
            let hasErrors =
                (
                    root[
                        "errors"
                    ] as?
                        [Any]
                )?
                .isEmpty ==
                false

            let hasData =
                root[
                    "data"
                ] is
                    [String: Any]

            let hasExpectedResponse =
                (
                    root[
                        "data"
                    ] as?
                        [String: Any]
                )?[
                    "xig_direct_media_send_with_slide_messaging_response"
                ] is
                    [String: Any]

            let reason:
                String

            if hasErrors {
                reason =
                    "GraphQL returned errors"
            } else if !hasData {
                reason =
                    "response has no data object"
            } else if !hasExpectedResponse {
                reason =
                    "media-send response field is absent"
            } else {
                reason =
                    "media-send response has no message id"
            }

            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6934,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not confirm the Direct attachment (" +
                        reason +
                        ")."
                ]
            )
        }

        let timestamp =
            directMilliseconds(
                response[
                    "timestamp_ms"
                ]
            )

        return
            MagnistraDirectSendResult(
                messageID:
                    messageID,
                timestampMilliseconds:
                    timestamp > 0.0
                        ? timestamp
                        : Date()
                            .timeIntervalSince1970 *
                            1000.0
            )
    }

    static func magnistraWebUploadAttachment(
        data: Data, mime: String, filename: String,
        isVoice: Bool, waveform: [Double]
    ) throws -> String {
        magnistraWebMediaUploadLock.lock()
        defer { magnistraWebMediaUploadLock.unlock() }
        let session = try loadSession()
        let caPath = Bundle.main.path(forResource: "CACert", ofType: "pem") ?? ""
        let prepareCode: Int32 = caPath.withCString { ca in
            session.userAgent.withCString { ua in
                session.language.withCString { lang in
                    session.cookieHeader.withCString { cookie in
                        session.csrfToken.withCString { csrf in
                            magnistraDirectMediaPrepareAuth(ca, ua, lang, cookie, csrf)
                        }
                    }
                }
            }
        }
        guard prepareCode == 0 else {
            throw NSError(domain: "MagnistraDirectMedia", code: Int(prepareCode),
                userInfo: [NSLocalizedDescriptionKey:
                    "Instagram Web upload authentication could not be prepared (stage \(prepareCode)). No attachment was sent."])
        }
        let uploadDTSG = String(cString: magnistraDirectMediaAuthDTSG())
        let uploadJazoest = String(cString: magnistraDirectMediaAuthJazoest())
        let boundary = "MagnistraMedia" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var body = Data()
        func add(_ text: String) { if let bytes = text.data(using: .utf8) { body.append(bytes) } }

        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"__a\"\r\n\r\n1\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"__req\"\r\n\r\n1\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"fb_dtsg\"\r\n\r\n\(uploadDTSG)\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"jazoest\"\r\n\r\n\(uploadJazoest)\r\n")
        if isVoice {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"voice_clip\"\r\n\r\ntrue\r\n")
            let jsonData = try MagnistraJSONKit.data(withJSONObject: waveform, options: [])
            let json = String(data: jsonData, encoding: .utf8) ?? "[]"
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"voice_clip_waveform_data\"\r\n\r\n\(json)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"farr\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        add("\r\n--\(boundary)--\r\n")

        let contentType = "multipart/form-data; boundary=\(boundary)"
        let code: Int32 = caPath.withCString { ca in
            session.userAgent.withCString { ua in
                session.language.withCString { lang in
                    session.cookieHeader.withCString { cookie in
                        session.csrfToken.withCString { csrf in
                            contentType.withCString { mime in
                                body.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int32 in
                                    magnistraDirectMediaCurlUpload(ca, ua, lang, cookie, csrf, mime,
                                        buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), body.count)
                                }
                            }
                        }
                    }
                }
            }
        }
        let http = Int(magnistraDirectMediaHTTPStatus())
        guard code == 0, (200..<300).contains(http) else {
            throw NSError(domain: "MagnistraDirectMedia", code: http > 0 ? http : Int(code),
                          userInfo: [NSLocalizedDescriptionKey: "Media upload failed (HTTP \(http), transport \(code))."])
        }
        let length = Int(magnistraDirectMediaResponseLength())
        guard length > 0, let ptr = magnistraDirectMediaResponseData() else {
            throw NSError(domain: "MagnistraDirectMedia", code: 7101,
                          userInfo: [NSLocalizedDescriptionKey: "Instagram returned no attachment response."])
        }
        let payload = Data(bytes: ptr, count: length)

        if let initial = String(data: payload.prefix(96), encoding: .utf8),
           initial.lowercased().contains("<html") || initial.lowercased().contains("<!doctype") {
            let kind = String(cString: magnistraDirectMediaResponseType())
            throw NSError(domain: "MagnistraDirectMedia", code: 7112,
                userInfo: [NSLocalizedDescriptionKey:
                    "Instagram returned HTML instead of a media attachment (HTTP \(http), \(length) bytes, Content-Type \(kind), upload endpoint \(magnistraDirectMediaEndpointMatches() == 1 ? "matched" : "different"))."])
        }
        let parsedData: Data
        if let head = String(data: payload.prefix(9), encoding: .utf8),
           head == "for (;;);" {
            parsedData = Data(payload.dropFirst(9))
        } else {
            parsedData = payload
        }
        let object = try MagnistraJSONKit.jsonObject(with: parsedData, options: [])

        guard let envelope = object as? [String: Any],
              let uploadPayload = envelope["payload"] as? [String: Any],
              let meta = uploadPayload["metadata"],
              let firstFile = ((meta as? [String: Any])?["0"] as? [String: Any])
                  ?? (meta as? [[String: Any]])?.first else {
            let serverError = (object as? [String: Any]) ?? [:]
            let rawCode = (serverError["error"] as? NSNumber)?.stringValue ??
                (serverError["error"] as? String) ?? ""
            let codeText = rawCode.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil
                ? rawCode : "unavailable"
            func safeServerErrorText(_ key: String) -> String {
                guard let raw = serverError[key] as? String, !raw.isEmpty,
                      raw.count <= 120,
                      raw.range(of: "^[A-Za-z0-9 .,;:!?()_/-]{1,120}$", options: .regularExpression) != nil,
                      !["token", "cookie", "csrf", "session", "password", "secret", "bearer"].contains(where: { raw.lowercased().contains($0) })
                else { return "(unavailable)" }
                return raw
            }
            let safeSummary = safeServerErrorText("errorSummary")
            let safeDetail = safeServerErrorText("errorDescription")
            throw NSError(domain: "MagnistraDirectMedia", code: 7102,
                userInfo: [NSLocalizedDescriptionKey:

                    "Upload rejected (HTTP \(http); error " + codeText +
                    "; summary: " + safeSummary + "; detail: " + safeDetail +
                    "). No message sent."])
        }

        let photoID = (firstFile["fbid"] as? String)
            ?? (firstFile["fbid"] as? NSNumber)?.stringValue
        let id: String?
        if isVoice {
            let acceptedNames = ["fbid", "attachment_fbid", "audio_id", "file_id", "attachmentID"]
            var candidates: [String] = []
            for key in acceptedNames {
                let value: String?
                if let text = firstFile[key] as? String {
                    value = text
                } else if let number = firstFile[key] as? NSNumber {
                    value = number.stringValue
                } else {
                    value = nil
                }
                if let candidate = value,
                   candidate.range(of: "^[0-9]{5,25}$", options: .regularExpression) != nil,
                   !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
            }
            id = candidates.count == 1 ? candidates[0] : nil
        } else {
            id = photoID
        }
        guard let attachmentID = id,
              attachmentID.range(of: "^[0-9]{5,25}$", options: .regularExpression) != nil else {

            func keyTypes(_ item: [String: Any], limit: Int) -> String {
                let keys = item.keys.filter { key in
                    key.range(of: "^[A-Za-z_][A-Za-z0-9_-]{0,47}$", options: .regularExpression) != nil
                }.sorted().prefix(limit)
                return keys.map { key -> String in
                    let value = item[key]!
                    let kind: String
                    if value is NSNull { kind = "0" }
                    else if value is String { kind = "s" }
                    else if value is NSNumber { kind = "n" }
                    else if value is [String: Any] { kind = "o" }
                    else if value is [Any] { kind = "a" }
                    else { kind = "?" }
                    return "\(key):\(kind)"
                }.joined(separator: ",")
            }
            let description = isVoice
                ? "Voice upload has no verified ID (file: \(keyTypes(firstFile, limit: 14)); payload: \(keyTypes(uploadPayload, limit: 8)); root: \(keyTypes(envelope, limit: 8))). No message sent."
                : "Instagram did not return a valid attachment FBID. No message was sent."
            throw NSError(domain: "MagnistraDirectMedia", code: 7103,
                userInfo: [NSLocalizedDescriptionKey: description])
        }
        return attachmentID
    }

    static func sendDirectWebMedia(
        threadFBID: String, data: Data, mime: String, filename: String,
        isVoice: Bool, waveform: [Double]
    ) throws -> MagnistraDirectSendResult {
        let attachmentID = try magnistraWebUploadAttachment(
            data: data, mime: mime, filename: filename,
            isVoice: isVoice, waveform: waveform)
        let variables: [String: Any] = [
            "attachment_fbid": attachmentID,
            "forwarded_from_thread_id": NSNull(),
            "is_forwarded_from_own_message": NSNull(),
            "offline_threading_id": directOfflineThreadingID(),
            "reply_to_message_id": NSNull(),
            "thread_id": threadFBID
        ]
        let root = try exploreSearchGraphQLRoot(
            variables: variables,
            docID: "25766288509716264",
            friendlyName: "IGDirectMediaSendMutation")
        guard let response = (root["data"] as? [String: Any])?["xig_direct_media_send_with_slide_messaging_response"] as? [String: Any],
            let messageID = stringValue(response["message_id"]) ?? stringValue(response["id"]),
            !messageID.isEmpty else {
            throw NSError(domain: "MagnistraDirectMedia", code: 7103,
                          userInfo: [NSLocalizedDescriptionKey: "Instagram did not confirm the attachment message."])
        }
        let timestamp = directMilliseconds(response["timestamp_ms"])
        return MagnistraDirectSendResult(messageID: messageID,
            timestampMilliseconds: timestamp > 0 ? timestamp : Date().timeIntervalSince1970 * 1000.0)
    }

    static func magnistraIGCatalog(kind: String, search: String) throws -> [MagnistraIGCatalogEntry] {
        let isGIF = kind == "gif"
        let document = isGIF ? "26614196041607789" : "27793508156903587"
        let friendly = isGIF ? "IGDComposerRichContentGifsV2Query" :
            "IGDComposerRichContentStickersV2Query"
        let variables: [String: Any] = ["search_query": String(search.prefix(60))]
        let response = try exploreSearchGraphQLRoot(
            variables: variables, docID: document, friendlyName: friendly)
        guard let data = response["data"] as? [String: Any],
              let query = data["xig_igd_stickers_query"] as? [String: Any],
              let sections = query["sections"] as? [String: Any],
              let sectionEdges = sections["edges"] as? [[String: Any]] else {
            throw NSError(domain: "MagnistraIGCatalog", code: 7201,
                userInfo: [NSLocalizedDescriptionKey:
                    "Instagram did not return a recognized sticker catalog."])
        }
        var found: [MagnistraIGCatalogEntry] = []
        var seen = Set<String>()
        for section in sectionEdges.prefix(25) {
            guard let sectionNode = section["node"] as? [String: Any],
                  let stickers = sectionNode["stickers"] as? [String: Any],
                  let edges = stickers["edges"] as? [[String: Any]] else { continue }
            for edge in edges.prefix(200) {
                guard let node = edge["node"] as? [String: Any],
                      let id = node["id"] as? String, !id.isEmpty,
                      id.count <= 128, seen.insert(id).inserted else { continue }
                let animated = node["animated_info"] as? [String: Any]
                let mp4 = animated?["mp4"] as? [String: Any]
                let staticInfo = node["static_info"] as? [String: Any]
                let cover = staticInfo?["image"] as? [String: Any]
                let animatedGIF = animated?["gif"] as? [String: Any]
                let previewCover = (cover?["url"] as? String)
                    ?? (staticInfo?["url"] as? String)
                    ?? (animatedGIF?["url"] as? String)
                var preview: String? = previewCover ?? (mp4?["url"] as? String)
                let w = (mp4?["width"] as? NSNumber)?.intValue ?? 0
                let h = (mp4?["height"] as? NSNumber)?.intValue ?? 0

                if let raw = preview, let url = URL(string: raw),
                   url.scheme?.lowercased() != "https" { preview = nil }
                let label = (node["alt_text"] as? String) ?? ""
                found.append(MagnistraIGCatalogEntry(id: id, kind: kind,
                    previewURL: preview, label: String(label.prefix(90)),
                    width: w, height: h))
                if found.count >= 180 { break }
            }
            if found.count >= 180 { break }
        }
        return found
    }

    static func magnistraIGCatalogPreview(_ raw: String) -> Data? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return nil }
        let allowed = ["instagram.com", "cdninstagram.com", "fbcdn.net",
                       "giphy.com", "giphyusercontent.com", "tenor.com"]
        guard allowed.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              let session = try? loadSession(),
              let caPath = Bundle.main.path(forResource: "CACert", ofType: "pem"),
              let data = MagnistraLazyImageTransport.fetch(
                  url: raw, caPath: caPath, userAgent: session.userAgent),
              data.count > 100, data.count < 7*1024*1024 else { return nil }
        return data
    }

    static func magnistraIGSendCatalogEntry(threadFBID: String,
                                           media: MagnistraIGCatalogEntry) throws -> MagnistraDirectSendResult {
        guard !threadFBID.hasPrefix("!"), !threadFBID.isEmpty,
              !media.id.isEmpty else {
            throw NSError(domain: "MagnistraIGCatalog", code: 7202,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Web Direct destination or sticker."])
        }
        let data: [String: Any] = [
            "is_random": false,
            "is_sticker": media.kind == "sticker",
            "reply_to_message_id": NSNull(),
            "sticker_id": media.id
        ]
        let sendData: [String: Any] = [
            "forwarded_from_thread_id": NSNull(),
            "is_forwarded_from_own_message": NSNull(),
            "offline_threading_id": directOfflineThreadingID(),
            "recipient_users": NSNull(),
            "reply_to_message_id": NSNull(),
            "send_attribution": "direct_chat",
            "thread_id": threadFBID
        ]
        let root = try exploreSearchGraphQLRoot(
            variables: ["data": data, "send_data": sendData],
            docID: "32089613413987432",
            friendlyName: "IGDirectAnimatedMediaSendMutation")
        guard let envelope = root["data"] as? [String: Any],
              let confirmed = envelope["direct_animated_media_send"] as? [String: Any],
              let messageID = confirmed["message_id"] as? String,
              !messageID.isEmpty else {
            throw NSError(domain: "MagnistraIGCatalog", code: 7203,
                userInfo: [NSLocalizedDescriptionKey:
                    "Instagram did not confirm the animated media send."])
        }
        return MagnistraDirectSendResult(messageID: messageID,
            timestampMilliseconds: Date().timeIntervalSince1970 * 1000.0)
    }

    static func sendDirectText(
        threadFBID:
            String,
        minUQSeqID:
            Int,
        text:
            String
    ) throws -> MagnistraDirectSendResult {
        let clean =
            text.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard
            !clean.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6921,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Message text is empty."
                ]
            )
        }

        let pendingPrefix = "pending:"
        let isNewRecipient = threadFBID.hasPrefix(pendingPrefix)
        let recipientID = isNewRecipient ? String(threadFBID.dropFirst(pendingPrefix.count)) : ""
        if isNewRecipient && (recipientID.isEmpty ||
            recipientID.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil) {
            throw NSError(domain: "MagnistraDirect", code: 6923,
                userInfo: [NSLocalizedDescriptionKey: "Invalid recipient ID."])
        }
        let threadIGID: String?
        if isNewRecipient {
            threadIGID = nil
        } else {
            threadIGID = try directThreadIGID(threadFBID: threadFBID,
                                                minUQSeqID: minUQSeqID)
        }

        let variables:
            [String: Any] = [
                "commands":
                    NSNull(),
                "forwarded_from_thread_id":
                    NSNull(),
                "ig_thread_igid":
                    threadIGID as Any? ?? NSNull(),
                "is_forwarded_from_own_message":
                    NSNull(),
                "mentioned_user_ids":
                    [Any](),
                "mentions":
                    [Any](),
                "offline_threading_id":
                    directOfflineThreadingID(),
                "recipient_igids":
                    isNewRecipient ? [recipientID] as Any : NSNull(),
                "replied_to_client_context":
                    NSNull(),
                "replied_to_item_id":
                    NSNull(),
                "reply_to_message_id":
                    NSNull(),
                "sampled":
                    NSNull(),
                "send_attribution":
                    "igd_web_chat_tab:in_thread",
                "text": [
                    "sensitive_string_value":
                        clean
                ]
            ]

        let root =
            try exploreSearchGraphQLRoot(
                variables:
                    variables,
                docID:
                    "26911679871773184",
                friendlyName:
                    "IGDirectTextSendMutation"
            )

        guard
            let data =
                root["data"]
                    as? [String: Any],
            let response =
                data[
                    "xig_direct_text_send_with_slide_messaging_response"
                ] as? [String: Any],
            let messageID =
                stringValue(
                    response[
                        "message_id"
                    ]
                ) ??
                stringValue(
                    response[
                        "id"
                    ]
                ),
            !messageID.isEmpty
        else {
            throw NSError(
                domain:
                    "MagnistraDirect",
                code:
                    6922,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Instagram did not confirm the Direct message."
                ]
            )
        }

        let timestamp =
            directMilliseconds(
                response[
                    "timestamp_ms"
                ]
            )

        return
            MagnistraDirectSendResult(
                messageID:
                    messageID,
                timestampMilliseconds:
                    timestamp > 0.0
                        ? timestamp
                        : Date()
                            .timeIntervalSince1970 *
                            1000.0
            )
    }
}
