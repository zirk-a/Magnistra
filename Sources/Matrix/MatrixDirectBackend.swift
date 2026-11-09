// Overview: Matrix-backed Direct backend: sending, decrypting and storing media.
import Foundation
import UIKit

final class MagnistraMatrixDirectBackend {
    static let shared =
        MagnistraMatrixDirectBackend()

    private let retryQueue =
        OperationQueue()

    private var client:
        MatrixAPIClient?

    private var activeSessionMarker: String?

    private var sendCounter:
        Int64 = 0

    private init() {
        retryQueue.maxConcurrentOperationCount =
            1
    }

    func prepare() {
        guard MatrixSession.isConfigured,
              let server = MatrixSession.homeserverURL,
              let token = MatrixSession.accessToken,
              let user = MatrixSession.userId,
              let device = MatrixSession.deviceId else {
            if activeSessionMarker != nil {
                MagnistraMatrixCryptoSync.shared.stop()
                DeviceVerificationManager.shared.resetForLogout()
            }
            activeSessionMarker = nil
            client = nil
            return
        }

        let marker = server + "|" + user + "|" + device + "|" + token
        if activeSessionMarker != marker || client == nil {
            if activeSessionMarker != nil {
                MagnistraMatrixCryptoSync.shared.stop()
                DeviceVerificationManager.shared.resetForLogout()
            }
            client = MatrixSession.makeAPIClient()
            activeSessionMarker = marker
        }

        if let api = client {
            guard MatrixDeviceStateMigration.preserveExistingDevice() else {
                NSLog("MATRIX_DEVICE_STATE=MIGRATION_REQUIRES_REVIEW")
                client = nil
                return
            }
            DeviceVerificationManager.shared.attach(api: api)
            MagnistraMatrixCryptoSync.shared.start(api: api)
        }
    }

    func resetForLogout() {
        MagnistraMatrixCryptoSync.shared.stop()
        activeSessionMarker = nil
        client = nil
        DeviceVerificationManager.shared.resetForLogout()
    }

    func normalizedContent(
        _ content:
            [String: Any]
    ) -> [String: Any] {
        return
            MatrixE2EEManager
                .magnistraNormalizedMediaContent(
                    content
                )
    }

    func decryptWithLiveSession(event: [String: Any], roomId: String) -> [String: Any]? {
        prepare()
        guard !roomId.isEmpty else { return nil }
        let manager = MatrixE2EEManager.shared
        manager.beginRoomContext(roomId)
        defer { manager.endRoomContext(roomId) }
        return manager.decryptRoomEvent(event)
    }

    func decryptOwnOutbound(
        event:
            [String: Any]
    ) -> [String: Any]? {
        return
            MatrixE2EEManager
                .shared
                .magnistraDecryptOwnOutboundEvent(
                    event
                )
    }

    func sendText(
        roomId:
            String,
        text:
            String,
        completion:
            @escaping (
                [String: Any]?,
                Error?
            ) -> Void
    ) {
        prepare()

        attemptTextSend(
            roomId:
                roomId,
            text:
                text,
            attempt:
                0,
            completion:
                completion
        )
    }

    private func attemptTextSend(
        roomId:
            String,
        text:
            String,
        attempt:
            Int,
        completion:
            @escaping (
                [String: Any]?,
                Error?
            ) -> Void
    ) {
        guard
            let client =
                client
        else {
            completion(
                nil,
                makeError(
                    "Matrix account is not signed in."
                )
            )
            return
        }

        guard
            MatrixE2EEManager
                .shared
                .magnistraOutboundReady
        else {
            if attempt >= 10 {
                completion(
                    nil,
                    makeError(
                        "Matrix encryption is still preparing this device."
                    )
                )
                return
            }

            retryQueue.addOperation {
                Thread.sleep(
                    forTimeInterval:
                        0.6
                )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?
                            .attemptTextSend(
                                roomId:
                                    roomId,
                                text:
                                    text,
                                attempt:
                                    attempt + 1,
                                completion:
                                    completion
                            )
                    }
            }

            return
        }

        let content:
            [String: Any] = [
                "msgtype":
                    "m.text",
                "body":
                    text
            ]

        MatrixE2EEManager
            .shared
            .prepareOutboundRoomEvent(
                roomId:
                    roomId,
                type:
                    "m.room.message",
                content:
                    content
            ) {
                [weak self]
                eventType,
                eventContent,
                error in

                guard
                    let self =
                        self
                else {
                    return
                }

                if let error = error {
                    if let matrix = error as? MatrixAPIClient.MatrixError {
                        completion(nil, NSError(domain: "Matrix",
                            code: 9403,
                            userInfo: [NSLocalizedDescriptionKey:
                                matrix.errcode + ": " + matrix.error]))
                    } else {
                        completion(nil, error)
                    }
                    return
                }

                guard
                    let eventType =
                        eventType,
                    let eventContent =
                        eventContent
                else {
                    completion(
                        nil,
                        self.makeError(
                            "Matrix did not prepare the message."
                        )
                    )
                    return
                }

                self.sendCounter +=
                    1

                let txn =
                    "magnistra-" +
                    String(
                        Int64(
                            Date()
                                .timeIntervalSince1970 *
                            1000.0
                        )
                    ) +
                    "-" +
                    String(
                        self.sendCounter
                    )

                let path =
                    "/_matrix/client/v3/rooms/" +
                    self.pathEncode(
                        roomId
                    ) +
                    "/send/" +
                    self.pathEncode(
                        eventType
                    ) +
                    "/" +
                    self.pathEncode(
                        txn
                    )

                client.put(
                    path,
                    body:
                        eventContent,
                    completion:
                        completion
                )
            }
    }

    private func pathEncode(
        _ raw:
            String
    ) -> String {
        var out =
            ""

        for byte in raw.utf8 {
            let allowed =
                (byte >= 48 && byte <= 57) ||
                (byte >= 65 && byte <= 90) ||
                (byte >= 97 && byte <= 122) ||
                byte == 45 ||
                byte == 46 ||
                byte == 95 ||
                byte == 126

            if allowed {
                out.append(
                    Character(
                        UnicodeScalar(
                            Int(
                                byte
                            )
                        )!
                    )
                )
            } else {
                out +=
                    String(
                        format:
                            "%%%02X",
                        byte
                    )
            }
        }

        return out
    }

    private func makeError(
        _ message:
            String
    ) -> NSError {
        return
            NSError(
                domain:
                    "MagnistraMatrix",
                code:
                    9401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        message
                ]
            )
    }
}

extension MagnistraMatrixDirectBackend {
    func sendMedia(
        roomId: String,
        filePath: String,
        fileName: String,
        mimeType: String,
        mediaInfo: [String: Any],
        eventType: String = "m.room.message",
        thumbnailPath: String? = nil,
        completion: @escaping ([String: Any]?, Error?) -> Void
    ) {
        prepare()
        guard client != nil,
              MagnistraMatrixE2EEManager.shared.magnistraOutboundReady,
              let base = MagnistraMatrixBackendSession.homeserverURL,
              let token = MagnistraMatrixBackendSession.accessToken,
              !token.isEmpty else {
            completion(nil, makeError("Matrix media encryption/session is not ready."))
            return
        }
        let allowedMIMEs: Set<String> = [
            "image/jpeg", "image/png", "image/gif", "image/webp",
            "video/mp4", "video/quicktime", "audio/wav", "audio/mp4"
        ]
        guard allowedMIMEs.contains(mimeType),
              eventType == "m.room.message" || eventType == "m.sticker",
              FileManager.default.fileExists(atPath: filePath) else {
            completion(nil, makeError("Unsupported or missing Matrix media file."))
            return
        }

        MagnistraMatrixE2EEManager.shared.prepareOutboundMedia(
            roomId: roomId, inputPath: filePath
        ) { [weak self] prepared, error in
            guard let self = self else { return }
            if let error = error { completion(nil, error); return }
            guard let prepared = prepared else {
                completion(nil, self.makeError("Could not prepare Matrix media."))
                return
            }
            let endpoint = base.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/_matrix/media/v3/upload?filename=" + self.pathEncode(fileName)
            let headers: [String: String] = [
                "Authorization": "Bearer " + token,
                "Content-Type": prepared.encrypted == nil ? mimeType : "application/octet-stream"
            ]
            MagnistraMatrixCurlFetcher.postFile(
                url: endpoint,
                headers: headers,
                filePath: prepared.path,
                progress: nil
            ) { [weak self] reply in
                if prepared.removeWhenDone {
                    try? FileManager.default.removeItem(atPath: prepared.path)
                }
                guard let self = self else { return }
                guard let reply = reply,
                      let parsed = try? JSONSerialization.jsonObject(with: reply, options: []),
                      let json = parsed as? [String: Any],
                      let mxc = json["content_uri"] as? String,
                      mxc.hasPrefix("mxc://") else {
                    completion(nil, self.makeError("Matrix media upload failed or returned no MXC URI."))
                    return
                }
                var content: [String: Any] = [
                    "body": eventType == "m.sticker" ? "Sticker" : fileName,
                    "info": mediaInfo
                ]
                if eventType != "m.sticker" {
                    let type: String
                    if mimeType.hasPrefix("video/") {
                        type = "m.video"
                    } else if mimeType.hasPrefix("audio/") {
                        type = "m.audio"
                        content["body"] = "Voice message"
                        content["org.matrix.msc3245.voice"] = [String: Any]()
                    } else {
                        type = "m.image"
                    }
                    content["msgtype"] = type
                }
                if let encrypted = prepared.encrypted {
                    content["file"] = encrypted.descriptor(url: mxc)
                } else {
                    content["url"] = mxc
                }
                let sendEvent: ([String: Any]) -> Void = { outboundContent in
                MagnistraMatrixE2EEManager.shared.prepareOutboundRoomEvent(
                    roomId: roomId,
                    type: eventType,
                    content: outboundContent
                ) { [weak self] eventType, eventContent, eventError in
                    guard let self = self else { return }
                    if let eventError = eventError { completion(nil, eventError); return }
                    guard let eventType = eventType,
                          let eventContent = eventContent,
                          let client = self.client else {
                        completion(nil, self.makeError("Matrix could not encrypt the media event."))
                        return
                    }
                    self.sendCounter += 1
                    let txn = "magnistra-media-" + String(Int64(Date().timeIntervalSince1970 * 1000.0))
                        + "-" + String(self.sendCounter)
                    let path = "/_matrix/client/v3/rooms/" + self.pathEncode(roomId)
                        + "/send/" + self.pathEncode(eventType)
                        + "/" + self.pathEncode(txn)
                    client.put(path, body: eventContent, completion: completion)
                }
                }
                if mimeType.hasPrefix("video/"),
                   let thumbnailPath = thumbnailPath,
                   FileManager.default.fileExists(atPath: thumbnailPath) {

                    MagnistraMatrixE2EEManager.shared.prepareOutboundMedia(
                        roomId: roomId, inputPath: thumbnailPath
                    ) { [weak self] thumb, error in
                        guard let self = self else { return }

                        if error != nil { sendEvent(content); return }
                        guard let thumb = thumb else {
                            sendEvent(content)
                            return
                        }
                        let thumbnailHeaders: [String: String] = [
                            "Authorization": "Bearer " + token,
                            "Content-Type": thumb.encrypted == nil ? "image/jpeg" : "application/octet-stream"
                        ]
                        let thumbnailEndpoint = base.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            + "/_matrix/media/v3/upload?filename=thumbnail.jpg"
                        MagnistraMatrixCurlFetcher.postFile(
                            url: thumbnailEndpoint,
                            headers: thumbnailHeaders,
                            filePath: thumb.path,
                            progress: nil
                        ) { response in
                            if thumb.removeWhenDone {
                                try? FileManager.default.removeItem(atPath: thumb.path)
                            }
                            guard let response = response,
                                  let obj = try? JSONSerialization.jsonObject(with: response, options: []),
                                  let json = obj as? [String: Any],
                                  let thumbMXC = json["content_uri"] as? String,
                                  thumbMXC.hasPrefix("mxc://") else {
                                sendEvent(content)
                                return
                            }
                            var withThumbnail = content
                            var videoInfo = mediaInfo
                            if let image = UIImage(contentsOfFile: thumbnailPath) {
                                videoInfo["thumbnail_info"] = [
                                    "mimetype": "image/jpeg",
                                    "w": Int(image.size.width), "h": Int(image.size.height)
                                ]
                            }
                            if let encryptedThumb = thumb.encrypted {
                                videoInfo["thumbnail_file"] = encryptedThumb.descriptor(url: thumbMXC)
                            } else {
                                videoInfo["thumbnail_url"] = thumbMXC
                            }
                            withThumbnail["info"] = videoInfo
                            sendEvent(withThumbnail)
                        }
                    }
                } else {
                    sendEvent(content)
                }
            }
        }
    }
}

extension MagnistraMatrixDirectBackend {
    func loadRoomParticipants(
        roomId: String,
        completion: @escaping ([[String: String]]?, Error?) -> Void
    ) {
        prepare()
        guard let api = client, !roomId.isEmpty else {
            let error = NSError(domain: "MagnistraMatrixRoomParticipants", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Matrix account or room unavailable."])
            completion(nil, error)
            return
        }
        api.get("/_matrix/client/v3/rooms/\(roomId)/joined_members", timeout: 30) {
            json, error in
            if let error = error { completion(nil, error); return }
            guard let joined = json?["joined"] as? [String: Any] else {
                let problem = NSError(domain: "MagnistraMatrixRoomParticipants", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Room member list unavailable."])
                completion(nil, problem)
                return
            }
            var people: [[String: String]] = []
            for (userId, record) in joined {
                let details = record as? [String: Any] ?? [:]
                let name = (details["display_name"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var person = ["id": userId, "name": name.isEmpty ? userId : name]
                if let avatar = details["avatar_url"] as? String,
                   avatar.hasPrefix("mxc://") { person["avatar_url"] = avatar }
                people.append(person)
            }
            completion(people, nil)
        }
    }
}

final class MagnistraMatrixMediaStore {
    static let shared =
        MagnistraMatrixMediaStore()

    private let root:
        String

    private init() {
        let roots =
            NSSearchPathForDirectoriesInDomains(
                .cachesDirectory,
                .userDomainMask,
                true
            )

        let base =
            roots.first ??
            NSTemporaryDirectory()

        root =
            (base as NSString)
                .appendingPathComponent(
                    "MagnistraMatrixMedia"
                )

        try?
            FileManager.default
                .createDirectory(
                    atPath:
                        root,
                    withIntermediateDirectories:
                        true,
                    attributes:
                        nil
                )
    }

    func loadImage(
        mxc:
            String,
        completion:
            @escaping (UIImage?) -> Void
    ) {
        materialize(
            mxc:
                mxc,
            filename:
                "image.jpg",
            mimeType:
                "image/jpeg"
        ) {
            path in

            let image = path.flatMap {
                MagnistraDirectMessageCell.decodedPreviewImage(atPath: $0)
            }

            OperationQueue.main
                .addOperation {
                    completion(
                        image
                    )
                }
        }
    }

    func materializeAudio(
        mxc:
            String,
        completion:
            @escaping (String?) -> Void
    ) {
        materialize(
            mxc:
                mxc,
            filename:
                "voice.m4a",
            mimeType:
                "audio/mp4",
            completion:
                completion
        )
    }

    func materializeVideo(
        mxc:
            String,
        completion:
            @escaping (String?) -> Void
    ) {
        materialize(
            mxc:
                mxc,
            filename:
                "video.mp4",
            mimeType:
                "video/mp4",
            completion:
                completion
        )
    }

    func materialize(
        mxc:
            String,
        filename:
            String,
        mimeType:
            String,
        completion:
            @escaping (String?) -> Void
    ) {
        guard
            let parsed =
                parseMXC(
                    mxc
                ),
            let base =
                MatrixSession
                    .homeserverURL,
            let token =
                MatrixSession
                    .accessToken
        else {
            completion(
                nil
            )
            return
        }

        let suffix =
            fileSuffix(
                filename:
                    filename,
                mimeType:
                    mimeType
            )

        let stable =
            safe(
                parsed.server +
                "_" +
                parsed.mediaId
            )

        let destination =
            (root as NSString)
                .appendingPathComponent(
                    stable +
                    suffix
                )

        if
            FileManager.default
                .fileExists(
                    atPath:
                        destination
                )
        {
            completion(
                destination
            )
            return
        }

        let part =
            destination +
            ".part"

        let url =
            base +
            "/_matrix/client/v1/media/download/" +
            pathEncode(
                parsed.server
            ) +
            "/" +
            pathEncode(
                parsed.mediaId
            )

        MagnistraMatrixCurlFetcher
            .downloadToFile(
                url:
                    url,
                headers: [
                    "Authorization":
                        "Bearer " +
                        token
                ],
                outputPath:
                    part,
                progress:
                    nil
            ) {
                ok in

                guard ok else {
                    try?
                        FileManager.default
                            .removeItem(
                                atPath:
                                    part
                            )

                    completion(
                        nil
                    )
                    return
                }

                let record =
                    MatrixE2EEManager
                        .encryptedMediaRecord(
                            for:
                                mxc
                        )

                if
                    let record =
                        record
                {
                    var success =
                        false

                    record.key
                        .withUnsafeBufferPointer {
                            key in

                            record.iv
                                .withUnsafeBufferPointer {
                                    iv in

                                    record.sha256
                                        .withUnsafeBufferPointer {
                                            hash in

                                            success =
                                                part.withCString {
                                                    src in

                                                    destination.withCString {
                                                        dst in

                                                        magnistra_matrix_crypto_aes256_ctr_decrypt_file(
                                                            src,
                                                            dst,
                                                            key.baseAddress,
                                                            iv.baseAddress,
                                                            hash.baseAddress
                                                        ) ==
                                                        1
                                                    }
                                                }
                                        }
                                }
                        }

                    try?
                        FileManager.default
                            .removeItem(
                                atPath:
                                    part
                            )

                    if !success {
                        try?
                            FileManager.default
                                .removeItem(
                                    atPath:
                                        destination
                                )
                    }

                    completion(
                        success
                            ? destination
                            : nil
                    )
                    return
                }

                try?
                    FileManager.default
                        .removeItem(
                            atPath:
                                destination
                        )

                do {
                    try
                        FileManager.default
                            .moveItem(
                                atPath:
                                    part,
                                toPath:
                                    destination
                            )

                    completion(
                        destination
                    )
                } catch {
                    try?
                        FileManager.default
                            .removeItem(
                                atPath:
                                    part
                            )

                    completion(
                        nil
                    )
                }
            }
    }

    private func parseMXC(
        _ raw:
            String
    ) -> (
        server:
            String,
        mediaId:
            String
    )? {
        guard
            raw.hasPrefix(
                "mxc://"
            )
        else {
            return nil
        }

        let value =
            String(
                raw.dropFirst(
                    6
                )
            )

        guard
            let slash =
                value.firstIndex(
                    of:
                        "/"
                )
        else {
            return nil
        }

        let server =
            String(
                value[
                    value.startIndex..<slash
                ]
            )

        let next =
            value.index(
                after:
                    slash
            )

        let mediaId =
            String(
                value[
                    next..<value.endIndex
                ]
            )

        guard
            !server.isEmpty,
            !mediaId.isEmpty
        else {
            return nil
        }

        return (
            server,
            mediaId
        )
    }

    private func safe(
        _ raw:
            String
    ) -> String {
        var out =
            ""

        for ch in raw {
            if
                ch.isLetter ||
                ch.isNumber ||
                ch == "-" ||
                ch == "_"
            {
                out.append(
                    ch
                )
            } else {
                out.append(
                    "_"
                )
            }
        }

        return out
    }

    private func fileSuffix(
        filename:
            String,
        mimeType:
            String
    ) -> String {
        let lower =
            filename.lowercased()

        if lower.hasSuffix(".png") {
            return ".png"
        }

        if lower.hasSuffix(".gif") {
            return ".gif"
        }

        if lower.hasSuffix(".mov") {
            return ".mov"
        }

        if lower.hasSuffix(".mp4") {
            return ".mp4"
        }

        if lower.hasSuffix(".m4a") {
            return ".m4a"
        }

        if lower.hasSuffix(".aac") {
            return ".aac"
        }

        if mimeType.lowercased().contains("video") {
            return ".mp4"
        }

        if mimeType.lowercased().contains("audio") {
            return ".m4a"
        }

        return ".jpg"
    }

    private func pathEncode(
        _ raw:
            String
    ) -> String {
        var out =
            ""

        for byte in raw.utf8 {
            let allowed =
                (byte >= 48 && byte <= 57) ||
                (byte >= 65 && byte <= 90) ||
                (byte >= 97 && byte <= 122) ||
                byte == 45 ||
                byte == 46 ||
                byte == 95 ||
                byte == 126

            if allowed {
                out.append(
                    Character(
                        UnicodeScalar(
                            Int(
                                byte
                            )
                        )!
                    )
                )
            } else {
                out +=
                    String(
                        format:
                            "%%%02X",
                        byte
                    )
            }
        }

        return out
    }
}
