// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix end-to-end encryption manager: Olm/Megolm sessions, keys and sync handling.
import Foundation
import UIKit
import Security
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration



struct RoomMegolmSession {
    let roomId: String
    let initialIndex: UInt32
    let r0: [UInt8]
    let r1: [UInt8]
    let r2: [UInt8]
    let r3: [UInt8]
    let signingKey: [UInt8]
    let senderKey: String
}

final class MatrixE2EEManager {
    static let shared = MatrixE2EEManager()

    var api: MatrixAPIClient?
    var userId: String?
    var deviceId: String?
    var identity: MagnistraDeviceIdentity?
    var generation = 0
    var oneTimeUploadInFlight = false

    var transientRoomId: String?

    var runtimeStage = "INIT"
    var oneTimeKeysReady = false
    var pendingRoomKeyRequests: [(roomId: String, senderKey: String, sessionId: String)] = []
    var requestedSessionIds = Set<String>()

    var roomKeyRequestAttempts: [String: Int] = [:]
    let roomKeyRequestMaxAttempts = 6
    let roomKeyRequestRetryDelay: TimeInterval = 8

    var olmReplacementInFlight = Set<String>()
    let olmReplacementMinIntervalMs: Int64 = 3600000

    var trustedEd25519ByCurve25519: [String: String] = [:]
    var replayEventIds: [String: [UInt32: String]] = [:]

    struct LivePendingEncryptedEvent {
        let roomId: String
        let sessionId: String
        let raw: [String: Any]
    }
    static let liveDecryptedEventNotification =
        Notification.Name("MagnistraE2EELiveDecryptedEvent")
    let liveDecryptLock = NSLock()
    var livePendingEncryptedEvents: [String: LivePendingEncryptedEvent] = [:]
    var liveDecryptedEvents: [String: [String: Any]] = [:]
    let liveDecryptCacheLimit = 256

    let olmAlgorithm = "m.olm.v1.curve25519-aes-sha2"
    let megolmAlgorithm = "m.megolm.v1.aes-sha2"

    init() {

        print("[MagnistraMatrix:R65] Vodozemac " + MagnistraVodozemac.status)
    }

    func attach(api: MatrixAPIClient, userId: String, deviceId: String,
                            identity: MagnistraDeviceIdentity) {
        self.api = api
        self.userId = userId
        self.deviceId = deviceId
        self.identity = identity
        runtimeStage = "ATTACHED"
        print("[MagnistraE2EE] device attached")
    }

    func resetForLogout() {
        generation += 1
        api = nil
        userId = nil
        deviceId = nil
        identity = nil
        oneTimeUploadInFlight = false
        runtimeStage = "RESET"
        transientRoomId = nil
        oneTimeKeysReady = false
        pendingRoomKeyRequests.removeAll()
        requestedSessionIds.removeAll()
        roomKeyRequestAttempts.removeAll()
        olmReplacementInFlight.removeAll()
        trustedEd25519ByCurve25519.removeAll()
        replayEventIds.removeAll()
        liveDecryptLock.lock()
        livePendingEncryptedEvents.removeAll()
        liveDecryptedEvents.removeAll()
        liveDecryptLock.unlock()
        print("[MagnistraE2EE] session state reset")
    }

    func handleSync(_ json: [String: Any]) {
        guard api != nil, userId != nil, deviceId != nil, identity != nil else { return }

        if let counts = json["device_one_time_keys_count"] as? [String: Any],
           let count = intValue(counts["signed_curve25519"]) {
            ensureOneTimeKeys(serverCount: count)
        }

        if let rooms = json["rooms"] as? [String: Any],
           let joined = rooms["join"] as? [String: Any] {
            for (roomId, rawRoom) in joined {
                guard let room = rawRoom as? [String: Any],
                      let timeline = room["timeline"] as? [String: Any],
                      let events = timeline["events"] as? [[String: Any]] else { continue }
                for event in events { requestRoomKeyIfNeeded(event, roomId: roomId) }
            }
        }

        guard let toDevice = json["to_device"] as? [String: Any],
              let events = toDevice["events"] as? [[String: Any]] else { return }
        for event in events {
            guard let type = event["type"] as? String else { continue }
            if type == "m.room.encrypted" {
                handleEncryptedToDevice(event)
            } else if type == "m.room_key.withheld",
                      let content = event["content"] as? [String: Any] {
                let code = content["code"] as? String ?? "unknown"
                let reason = content["reason"] as? String ?? ""
                runtimeStage = "WITHHELD:" + code
                print("[MagnistraE2EE] room key withheld (details redacted)")
            }
        }
    }

    func ensureOneTimeKeys(serverCount: Int = 0) {
        if MatrixCryptoEngine.shared.active {
            guard !oneTimeUploadInFlight, let api = api, let uid = userId,
                  let did = deviceId else { return }
            let wanted = max(0, 10 - max(0, serverCount))
            if wanted == 0 {
                oneTimeKeysReady = true; runtimeStage = "R66_NATIVE_OTK_READY"
                drainPendingRoomKeyRequests(); return
            }
            guard let upload = MatrixCryptoEngine.shared.prepareOTK(
                count: wanted, user: uid, device: did,
                canonical: { [weak self] in self?.canonicalJSON($0) }), !upload.isEmpty else {
                runtimeStage = "R66_OTK_PREPARE_FAILED"; return
            }
            oneTimeUploadInFlight = true
            let g = generation
            api.post("/_matrix/client/v3/keys/upload", body: ["one_time_keys": upload]) { [weak self] json, error in
                guard let self = self, self.generation == g else { return }
                self.oneTimeUploadInFlight = false
                guard error == nil, json?["errcode"] == nil,
                      MatrixCryptoEngine.shared.markOTKUploaded() else {
                    self.runtimeStage = "R66_OTK_UPLOAD_FAILED"; return
                }
                self.oneTimeKeysReady = true
                self.runtimeStage = "R66_NATIVE_OTK_READY"
                self.drainPendingRoomKeyRequests()
            }
            return
        }

        guard !oneTimeUploadInFlight,
              let api = api, let uid = userId, let did = deviceId,
              let ident = identity else { return }

        let target = 10
        let wanted = max(0, target - max(0, serverCount))
        if wanted == 0 {
            oneTimeKeysReady = serverCount > 0
            runtimeStage = oneTimeKeysReady ? "OTK_READY_SERVER" : "OTK_NONE"
            if oneTimeKeysReady { drainPendingRoomKeyRequests() }
            return
        }

        var records = loadOTKs()
        var pending = records.filter { !$0.value.uploaded }
        var toCreate = max(0, wanted - pending.count)
        while toCreate > 0 {
            guard let pair = x25519Keygen() else { break }
            let keyId = nextOTKId()
            records[keyId] = (pair.0, pair.1, false)
            pending[keyId] = (pair.0, pair.1, false)
            toCreate -= 1
        }
        saveOTKs(records)
        if pending.isEmpty { return }

        let selected = Array(pending.keys.sorted().prefix(max(wanted, 1)))
        var upload: [String: Any] = [:]
        for keyId in selected {
            guard let rec = records[keyId] else { continue }
            let publicB64 = base64Encode(rec.pub)
            let bare: [String: Any] = ["key": publicB64]
            guard let canonical = canonicalJSON(bare),
                  let sig = ed25519Sign(privateKey: ident.edPrivate,
                                        message: Array(canonical.utf8)) else { continue }
            var signed = bare
            signed["signatures"] = [uid: ["ed25519:\(did)": base64Encode(sig)]]
            upload["signed_curve25519:\(keyId)"] = signed
        }
        if upload.isEmpty { return }

        oneTimeUploadInFlight = true
        runtimeStage = "OTK_UPLOAD"
        let g = generation
        api.post("/_matrix/client/v3/keys/upload", body: ["one_time_keys": upload]) { [weak self] json, error in
            guard let self = self, self.generation == g else { return }
            self.oneTimeUploadInFlight = false
            if let error = error {
                self.runtimeStage = "OTK_UPLOAD_FAIL"
                print("[MagnistraE2EE] OTK upload failed")
                return
            }
            if let json = json, let errcode = json["errcode"] as? String {
                self.runtimeStage = "OTK_REJECTED:" + errcode
                print("[MagnistraE2EE] OTK upload rejected")
                return
            }
            var current = self.loadOTKs()
            for keyId in selected {
                if let rec = current[keyId] { current[keyId] = (rec.priv, rec.pub, true) }
            }
            self.saveOTKs(current)
            self.oneTimeKeysReady = true
            self.runtimeStage = "OTK_READY"
            self.drainPendingRoomKeyRequests()
            print("[MagnistraE2EE] uploaded \(selected.count) one-time keys")
        }
    }

    func runtimeStatusText() -> String {
        return "\u{1F512} Encrypted message"
    }

    func beginRoomContext(_ roomId: String) {
        transientRoomId = roomId
        print("[MagnistraE2EE] room context active")
    }

    func endRoomContext(_ roomId: String) {
        if transientRoomId == roomId { transientRoomId = nil }
    }

    func decryptRoomEvent(_ event: [String: Any]) -> [String: Any]? {
        if MatrixCryptoEngine.shared.active {
            guard let content = event["content"] as? [String: Any],
                  (content["algorithm"] as? String) == megolmAlgorithm,
                  let sid = content["session_id"] as? String,
                  let sender = content["sender_key"] as? String,
                  let cipher = content["ciphertext"] as? String else { return nil }
            guard let plain = MatrixCryptoEngine.shared.decryptGroup(sender: sender,
                                                                            id: sid, text: cipher),
                  let type = plain["type"] as? String,
                  let body = plain["content"] as? [String: Any] else {
                if let room = transientRoomId {
                    rememberPendingEncryptedEvent(event, roomId: room, sessionId: sid)
                    requestRoomKeyIfNeeded(event, roomId: room)
                }
                return nil
            }
            if let actualRoom = plain["room_id"] as? String, let eventRoom = transientRoomId,
               !actualRoom.isEmpty && actualRoom != eventRoom { return nil }
            var merged = event
            merged["type"] = type
            var finalBody = body
            MatrixE2EEManager.registerEncryptedMedia(in: &finalBody)
            merged["content"] = finalBody
            runtimeStage = "R66_NATIVE_MEGOLM_DECRYPT_OK"
            return merged
        }

        if let content = event["content"] as? [String: Any],
           (content["algorithm"] as? String) == megolmAlgorithm,
           let sessionId = content["session_id"] as? String,
           loadMegolmSession(sessionId) == nil,
           let roomId = transientRoomId, !roomId.isEmpty {
            rememberPendingEncryptedEvent(event, roomId: roomId, sessionId: sessionId)
            requestRoomKeyIfNeeded(event, roomId: roomId)
            return nil
        }

        guard let content = event["content"] as? [String: Any],
              (content["algorithm"] as? String) == megolmAlgorithm,
              let sessionId = content["session_id"] as? String,
              let ciphertextB64 = content["ciphertext"] as? String,
              let raw = base64Decode(ciphertextB64),
              let session = loadMegolmSession(sessionId),
              let parsed = parseMegolmMessage(raw),
              parsed.index >= session.initialIndex else { return nil }

        runtimeStage = "MEGOLM_DECRYPT_ATTEMPT"
        var ratchet = (session.r0, session.r1, session.r2, session.r3)
        var idx = session.initialIndex
        if parsed.index - idx > 200_000 { return nil }
        while idx < parsed.index {
            guard let next = advanceMegolm(ratchet, from: idx) else { return nil }
            ratchet = next
            idx += 1
        }

        let ratchetBytes = ratchet.0 + ratchet.1 + ratchet.2 + ratchet.3
        guard let keys = hkdfSHA256(ikm: ratchetBytes,
                                    info: Array("MEGOLM_KEYS".utf8), count: 80) else { return nil }
        let aes = Array(keys[0..<32])
        let macKey = Array(keys[32..<64])
        let iv = Array(keys[64..<80])

        guard let mac = hmacSHA256(key: macKey, data: parsed.authenticatedBytes),
              constantEqual(Array(mac[0..<8]), parsed.mac),
              ed25519Verify(publicKey: session.signingKey,
                            message: parsed.signedBytes,
                            signature: parsed.signature),
              let plainBytes = aes256CBCDecrypt(key: aes, iv: iv,
                                                ciphertext: parsed.ciphertext),
              let plain = jsonDictionary(plainBytes),
              let roomId = plain["room_id"] as? String, roomId == session.roomId,
              plain["type"] is String, plain["content"] is [String: Any] else { return nil }

        if let eid = event["event_id"] as? String, !eid.isEmpty {
            var byIndex = replayEventIds[sessionId] ?? [:]
            if let old = byIndex[parsed.index], old != eid { return nil }
            byIndex[parsed.index] = eid
            replayEventIds[sessionId] = byIndex
        }

        var merged = event
        merged["type"] = plain["type"]
        if var decryptedContent = plain["content"] as? [String: Any] {
            MatrixE2EEManager.registerEncryptedMedia(in: &decryptedContent)
            merged["content"] = decryptedContent
        } else {
            merged["content"] = plain["content"]
        }
        runtimeStage = "DECRYPT_OK"
        print("[MagnistraE2EE] room event decrypted")
        return merged
    }

    func rememberPendingEncryptedEvent(_ event: [String: Any],
                                               roomId: String, sessionId: String) {
        guard let eventId = event["event_id"] as? String, !eventId.isEmpty else { return }
        liveDecryptLock.lock()
        livePendingEncryptedEvents[eventId] = LivePendingEncryptedEvent(
            roomId: roomId, sessionId: sessionId, raw: event)
        if livePendingEncryptedEvents.count > liveDecryptCacheLimit {
            let keep = livePendingEncryptedEvents[eventId]
            livePendingEncryptedEvents.removeAll(keepingCapacity: true)
            if let keep = keep { livePendingEncryptedEvents[eventId] = keep }
        }
        liveDecryptLock.unlock()
    }

    func cachedDecryptedRoomEvent(eventId: String) -> [String: Any]? {
        liveDecryptLock.lock()
        let event = liveDecryptedEvents[eventId]
        liveDecryptLock.unlock()
        return event
    }

    func retryPendingEncryptedEvents(roomId: String, sessionId: String) {
        let requestKey = roomId + "|" + sessionId
        requestedSessionIds.remove(requestKey)
        roomKeyRequestAttempts.removeValue(forKey: requestKey)

        liveDecryptLock.lock()
        let candidates = livePendingEncryptedEvents.values.filter {
            $0.roomId == roomId && $0.sessionId == sessionId
        }
        liveDecryptLock.unlock()
        guard !candidates.isEmpty else { return }

        for item in candidates {
            guard let decrypted = decryptRoomEvent(item.raw),
                  let eventId = decrypted["event_id"] as? String, !eventId.isEmpty else {
                continue
            }

            liveDecryptLock.lock()
            livePendingEncryptedEvents.removeValue(forKey: eventId)
            liveDecryptedEvents[eventId] = decrypted
            if liveDecryptedEvents.count > liveDecryptCacheLimit {
                let keep = liveDecryptedEvents[eventId]
                liveDecryptedEvents.removeAll(keepingCapacity: true)
                if let keep = keep { liveDecryptedEvents[eventId] = keep }
            }
            liveDecryptLock.unlock()

            NotificationCenter.default.post(
                name: MatrixE2EEManager.liveDecryptedEventNotification,
                object: self,
                userInfo: ["room_id": roomId, "event": decrypted])
            print("[MagnistraE2EE] encrypted event resolved")
        }
    }

    func requestRoomKeyIfNeeded(_ event: [String: Any], roomId: String) {
        guard let type = event["type"] as? String, type == "m.room.encrypted",
              let content = event["content"] as? [String: Any],
              (content["algorithm"] as? String) == megolmAlgorithm,
              let sessionId = content["session_id"] as? String, !sessionId.isEmpty,
              loadMegolmSession(sessionId) == nil,
              let senderKey = content["sender_key"] as? String, !senderKey.isEmpty else { return }
        let k = roomId + "|" + sessionId
        if requestedSessionIds.contains(k) { return }

        if !oneTimeKeysReady {
            let alreadyQueued = pendingRoomKeyRequests.contains {
                $0.roomId == roomId && $0.sessionId == sessionId
            }
            if !alreadyQueued {
                pendingRoomKeyRequests.append((roomId: roomId,
                                               senderKey: senderKey,
                                               sessionId: sessionId))
                runtimeStage = "WAITING_OTK"
                print("[MagnistraE2EE] room-key request queued until OTK ready")
            }
            return
        }

        requestedSessionIds.insert(k)
        runtimeStage = "KEY_REQUEST_SENDING"
        sendRoomKeyRequest(roomId: roomId, senderKey: senderKey,
                           sessionId: sessionId, cancellation: false)
    }

    func drainPendingRoomKeyRequests() {
        guard oneTimeKeysReady, !pendingRoomKeyRequests.isEmpty else { return }
        let queued = pendingRoomKeyRequests
        pendingRoomKeyRequests.removeAll()
        for item in queued {
            let k = item.roomId + "|" + item.sessionId
            if requestedSessionIds.contains(k) { continue }
            requestedSessionIds.insert(k)
            sendRoomKeyRequest(roomId: item.roomId,
                               senderKey: item.senderKey,
                               sessionId: item.sessionId,
                               cancellation: false)
        }
    }

    func sendRoomKeyRequest(roomId: String, senderKey: String,
                                    sessionId: String, cancellation: Bool) {
        guard let api = api, let uid = userId, let did = deviceId else { return }
        let requestKey = roomId + "|" + sessionId

        if !cancellation {
            let attempt = (roomKeyRequestAttempts[requestKey] ?? 0) + 1
            roomKeyRequestAttempts[requestKey] = attempt
            runtimeStage = attempt > 1 ? "KEY_REQUEST_RETRY_\(attempt)" : "KEY_REQUEST_SENDING"
            print("[MagnistraE2EE] room-key request attempt \(attempt)/\(roomKeyRequestMaxAttempts)")
        }

        let requestId = roomKeyRequestId(roomId: roomId, sessionId: sessionId)
        var content: [String: Any] = [
            "action": cancellation ? "request_cancellation" : "request",
            "request_id": requestId,
            "requesting_device_id": did
        ]
        if !cancellation {
            content["body"] = [
                "algorithm": megolmAlgorithm,
                "room_id": roomId,
                "sender_key": senderKey,
                "session_id": sessionId
            ]
        }
        let body: [String: Any] = ["messages": [uid: ["*": content]]]
        let txn = "magnistra-keyreq-\(nextSendCounter())"
        api.put("/_matrix/client/v3/sendToDevice/m.room_key_request/\(txn)", body: body) { [weak self] _, error in
            if let error = error {
                self?.runtimeStage = "KEY_REQUEST_SEND_FAIL"
                print("[MagnistraE2EE] room-key request failed")
            } else {
                let action = cancellation ? "cancelled" : "sent"
                if !cancellation { self?.runtimeStage = "KEY_REQUEST_SENT" }
                print("[MagnistraE2EE] \(action) key request")
            }
        }

        if !cancellation {
            scheduleRoomKeyRequestRetry(roomId: roomId, senderKey: senderKey, sessionId: sessionId)
        }
    }

    func scheduleRoomKeyRequestRetry(roomId: String, senderKey: String,
                                             sessionId: String) {
        let requestKey = roomId + "|" + sessionId
        let authGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + roomKeyRequestRetryDelay) { [weak self] in
            guard let self = self, self.generation == authGeneration,
                  self.loadMegolmSession(sessionId) == nil,
                  self.requestedSessionIds.contains(requestKey) else { return }

            let attempts = self.roomKeyRequestAttempts[requestKey] ?? 0
            if attempts >= self.roomKeyRequestMaxAttempts {

                self.requestedSessionIds.remove(requestKey)
                self.roomKeyRequestAttempts.removeValue(forKey: requestKey)
                self.runtimeStage = "KEY_REQUEST_RETRY_WINDOW_EXHAUSTED"
                print("[MagnistraE2EE] room-key retry window exhausted")
                return
            }

            self.sendRoomKeyRequest(roomId: roomId, senderKey: senderKey,
                                    sessionId: sessionId, cancellation: false)
        }
    }

    func roomKeyRequestId(roomId: String, sessionId: String) -> String {
        let bytes = Array((roomId + "|" + sessionId).utf8)
        if let digest = sha256(bytes) { return "eold-" + base64Encode(Array(digest[0..<12])) }
        return "eold-\(sessionId)"
    }

    func handleEncryptedToDevice(_ event: [String: Any]) {
        if MatrixCryptoEngine.shared.active {
            guard let ident = identity, let uid = userId,
                  let content = event["content"] as? [String: Any],
                  (content["algorithm"] as? String) == olmAlgorithm,
                  let senderCurve = content["sender_key"] as? String,
                  let ciphertext = content["ciphertext"] as? [String: Any],
                  let entry = ciphertext[base64Encode(ident.curvePublic)] as? [String: Any],
                  let body = entry["body"] as? String,
                  let kind = intValue(entry["type"]), (kind == 0 || kind == 1),
                  let plain = MatrixCryptoEngine.shared.decryptOlm(senderCurve: senderCurve,
                                                                          type: kind, body: body),
                  let sender = plain["sender"] as? String, sender == (event["sender"] as? String),
                  let recipient = plain["recipient"] as? String, recipient == uid,
                  let keys = plain["recipient_keys"] as? [String: Any],
                  (keys["ed25519"] as? String) == base64Encode(ident.edPublic),
                  let senderKeys = plain["keys"] as? [String: Any],
                  let claimedEd = senderKeys["ed25519"] as? String,
                  let payloadType = plain["type"] as? String,
                  let payload = plain["content"] as? [String: Any] else {
                runtimeStage = "R66_NATIVE_OLM_REJECTED"; return
            }
            validateOwnSender(curve25519: senderCurve, claimedEd25519: claimedEd) { [weak self] valid in
                guard let self = self, valid else { return }
                if payloadType == "m.room_key" || payloadType == "m.forwarded_room_key" {
                    self.acceptMegolmKey(payload, secureSenderCurve: senderCurve,
                                         forwarded: payloadType == "m.forwarded_room_key")
                }
            }
            return
        }

        runtimeStage = "OLM_TO_DEVICE_RX"
        guard let uid = userId, let ident = identity,
              (event["sender"] as? String) == uid,
              let content = event["content"] as? [String: Any],
              (content["algorithm"] as? String) == olmAlgorithm,
              let senderCurve = content["sender_key"] as? String,
              let ciphertext = content["ciphertext"] as? [String: Any] else { return }

        let ownCurve = base64Encode(ident.curvePublic)
        guard let entry = ciphertext[ownCurve] as? [String: Any],
              let envelopeType = intValue(entry["type"]),
              (envelopeType == 0 || envelopeType == 1),
              let body = entry["body"] as? String,
              let raw = base64Decode(body) else {
            runtimeStage = "OLM_ENVELOPE_REJECT"
            return
        }

        let plain: [String: Any]
        if envelopeType == 0 {
            guard let result = decryptOlmPreKey(raw, expectedSenderCurve: senderCurve) else {
                runtimeStage = "OLM_PREKEY_DECRYPT_FAIL"
                return
            }
            runtimeStage = "OLM_PREKEY_DECRYPT_OK"
            plain = result.plain
        } else {
            guard let result = decryptOlmNormalFromStoredSessions(raw) else {
                runtimeStage = "OLM_NORMAL_DECRYPT_FAIL"
                repairOlmSession(senderCurve: senderCurve)
                return
            }
            runtimeStage = "OLM_NORMAL_DECRYPT_OK"
            plain = result
        }

        guard let sender = plain["sender"] as? String, sender == uid,
              let recipient = plain["recipient"] as? String, recipient == uid,
              let recipientKeys = plain["recipient_keys"] as? [String: Any],
              (recipientKeys["ed25519"] as? String) == base64Encode(ident.edPublic),
              let senderKeys = plain["keys"] as? [String: Any],
              let claimedEd = senderKeys["ed25519"] as? String,
              let payloadType = plain["type"] as? String,
              let payloadContent = plain["content"] as? [String: Any] else {
            runtimeStage = "OLM_PLAINTEXT_REJECT"
            return
        }

        validateOwnSender(curve25519: senderCurve, claimedEd25519: claimedEd) { [weak self] valid in
            guard let self = self, valid else {
                self?.runtimeStage = "SENDER_VALIDATION_FAIL"
                print("[MagnistraE2EE] rejected to-device sender identity")
                return
            }
            self.runtimeStage = "SENDER_VALIDATED"
            if payloadType == "m.room_key" || payloadType == "m.forwarded_room_key" {
                self.runtimeStage = payloadType == "m.forwarded_room_key" ? "FORWARDED_KEY_RX" : "ROOM_KEY_RX"
                self.acceptMegolmKey(payloadContent, secureSenderCurve: senderCurve,
                                     forwarded: payloadType == "m.forwarded_room_key")
            }
        }
    }

    struct OlmPreKeyResult { let plain: [String: Any] }

    func decryptOlmPreKey(_ raw: [UInt8],
                                  expectedSenderCurve: String) -> OlmPreKeyResult? {
        guard raw.count > 2, raw[0] == 3,
              let outer = parseWireFields(raw, start: 1, end: raw.count),
              let eb = outer.strings[1], eb.count == 32,
              let ea = outer.strings[2], ea.count == 32,
              let ia = outer.strings[3], ia.count == 32,
              let embedded = outer.strings[4], embedded.count > 9,
              base64Encode(ia) == expectedSenderCurve,
              let normal = parseOlmNormal(embedded),
              let sidBytes = sha256(ia + ea) else { return nil }
        let sid = base64Encode(sidBytes)

        var state: MagnistraOlmSessionState
        var newlyCreated = false

        if let stored = loadOlmInboundSession(sid) {
            if let storedOTK = stored.oneTimePublic,
               !constantEqual(storedOTK, eb) { return nil }
            guard let recv = stored.receiverChain else { return nil }
            if let ratchet = stored.receiverRatchet,
               !constantEqual(ratchet, normal.ratchetKey) { return nil }
            state = stored
            state.receiverChain = recv
        } else {
            guard let ident = identity,
                  let otk = findOTK(publicKey: eb),
                  let s1 = x25519Shared(privateKey: otk.priv, peerPublic: ia),
                  let s2 = x25519Shared(privateKey: ident.curvePrivate, peerPublic: ea),
                  let s3 = x25519Shared(privateKey: otk.priv, peerPublic: ea),
                  let rootAndChain = hkdfSHA256(ikm: s1 + s2 + s3,
                                                info: Array("OLM_ROOT".utf8), count: 64) else { return nil }
            state = MagnistraOlmSessionState(
                rootKey: Array(rootAndChain[0..<32]),
                receiverChain: Array(rootAndChain[32..<64]),
                receiverRatchet: normal.ratchetKey,
                localRatchetPrivate: nil,
                localRatchetPublic: nil,
                oneTimePublic: otk.pub)
            newlyCreated = true
        }

        guard let baseChain = state.receiverChain,
              let plain = decryptOlmNormalPayload(normal, baseChain: baseChain) else { return nil }

        if state.receiverRatchet == nil {
            state.receiverRatchet = normal.ratchetKey
        }
        if state.oneTimePublic == nil {
            state.oneTimePublic = eb
        }
        saveOlmInboundSession(sid, state: state)

        if newlyCreated, let otk = state.oneTimePublic {
            consumeOTK(publicKey: otk)
        }
        return OlmPreKeyResult(plain: plain)
    }

    func decryptOlmNormalPayload(_ normal: OlmNormal,
                                         baseChain: [UInt8]) -> [String: Any]? {
        guard baseChain.count == 32, normal.chainIndex <= 4096 else { return nil }
        var chain = baseChain
        var j: UInt64 = 0
        while j < normal.chainIndex {
            guard let next = hmacSHA256(key: chain, data: [0x02]) else { return nil }
            chain = next
            j += 1
        }
        guard let messageKey = hmacSHA256(key: chain, data: [0x01]),
              let keys = hkdfSHA256(ikm: messageKey,
                                    info: Array("OLM_KEYS".utf8), count: 80) else { return nil }
        let aes = Array(keys[0..<32])
        let macKey = Array(keys[32..<64])
        let iv = Array(keys[64..<80])
        guard let mac = hmacSHA256(key: macKey, data: normal.authenticatedBytes),
              constantEqual(Array(mac[0..<8]), normal.mac),
              let plainBytes = aes256CBCDecrypt(key: aes, iv: iv,
                                                ciphertext: normal.ciphertext),
              let plain = jsonDictionary(plainBytes) else { return nil }
        return plain
    }

    func decryptOlmNormalFromStoredSessions(_ raw: [UInt8]) -> [String: Any]? {
        guard let normal = parseOlmNormal(raw), normal.chainIndex <= 4096 else { return nil }

        for (sessionId, original) in allOlmInboundSessions() {
            var state = original

            if let recv = state.receiverChain,
               let ratchet = state.receiverRatchet,
               constantEqual(ratchet, normal.ratchetKey),
               let plain = decryptOlmNormalPayload(normal, baseChain: recv) {
                return plain
            }

            if let recv = state.receiverChain,
               state.receiverRatchet == nil,
               let plain = decryptOlmNormalPayload(normal, baseChain: recv) {
                state.receiverRatchet = normal.ratchetKey
                saveOlmInboundSession(sessionId, state: state)
                print("[MagnistraE2EE] migrated authenticated legacy Olm receiver session")
                return plain
            }

            if let root = state.rootKey, root.count == 32,
               let localPrivate = state.localRatchetPrivate, localPrivate.count == 32,
               let shared = x25519Shared(privateKey: localPrivate,
                                         peerPublic: normal.ratchetKey),
               let ratcheted = hkdfSHA256(salt: root, ikm: shared,
                                          info: Array("OLM_RATCHET".utf8), count: 64) {
                let newRoot = Array(ratcheted[0..<32])
                let newChain = Array(ratcheted[32..<64])
                if let plain = decryptOlmNormalPayload(normal, baseChain: newChain) {
                    state.rootKey = newRoot
                    state.receiverChain = newChain
                    state.receiverRatchet = normal.ratchetKey

                    state.localRatchetPrivate = nil
                    state.localRatchetPublic = nil
                    saveOlmInboundSession(sessionId, state: state)
                    print("[MagnistraE2EE] advanced authenticated Olm receive root ratchet")
                    return plain
                }
            }
        }
        return nil
    }

    struct OlmNormal {
        let ratchetKey: [UInt8]
        let chainIndex: UInt64
        let ciphertext: [UInt8]
        let authenticatedBytes: [UInt8]
        let mac: [UInt8]
    }

    func parseOlmNormal(_ bytes: [UInt8]) -> OlmNormal? {
        guard bytes.count > 9, bytes[0] == 3 else { return nil }
        let macStart = bytes.count - 8
        guard let fields = parseWireFields(bytes, start: 1, end: macStart),
              let ratchet = fields.strings[1], ratchet.count == 32,
              let chain = fields.ints[2],
              let ciphertext = fields.strings[4] else { return nil }
        return OlmNormal(ratchetKey: ratchet, chainIndex: chain,
                         ciphertext: ciphertext,
                         authenticatedBytes: Array(bytes[0..<macStart]),
                         mac: Array(bytes[macStart..<bytes.count]))
    }

    func validateOwnSender(curve25519: String, claimedEd25519: String,
                                   completion: @escaping (Bool) -> Void) {
        if trustedEd25519ByCurve25519[curve25519] == claimedEd25519 {
            completion(true); return
        }
        guard let api = api, let uid = userId else { completion(false); return }
        let g = generation
        let body: [String: Any] = ["device_keys": [uid: [String]()]]
        api.post("/_matrix/client/v3/keys/query", body: body) { [weak self] json, error in
            guard let self = self, self.generation == g, error == nil,
                  let json = json,
                  let users = json["device_keys"] as? [String: Any],
                  let devices = users[uid] as? [String: Any] else { completion(false); return }
            for (did, raw) in devices {
                guard var device = raw as? [String: Any],
                      let keys = device["keys"] as? [String: Any],
                      let curve = keys["curve25519:\(did)"] as? String,
                      let ed = keys["ed25519:\(did)"] as? String,
                      curve == curve25519, ed == claimedEd25519,
                      let sigs = device["signatures"] as? [String: Any],
                      let byUser = sigs[uid] as? [String: Any],
                      let sigB64 = byUser["ed25519:\(did)"] as? String,
                      let pub = self.base64Decode(ed), pub.count == 32,
                      let sig = self.base64Decode(sigB64), sig.count == 64 else { continue }
                device.removeValue(forKey: "signatures")
                device.removeValue(forKey: "unsigned")
                guard let canonical = self.canonicalJSON(device),
                      self.ed25519Verify(publicKey: pub, message: Array(canonical.utf8), signature: sig) else { continue }
                self.trustedEd25519ByCurve25519[curve] = ed
                completion(true)
                return
            }
            completion(false)
        }
    }

    func acceptMegolmKey(_ content: [String: Any], secureSenderCurve: String,
                                 forwarded: Bool) {
        if MatrixCryptoEngine.shared.active {
            guard (content["algorithm"] as? String) == megolmAlgorithm,
                  let room = content["room_id"] as? String,
                  let sid = content["session_id"] as? String,
                  let key = content["session_key"] as? String else { return }
            let sender = (content["sender_key"] as? String) ?? secureSenderCurve
            guard MatrixCryptoEngine.shared.importGroup(room: room, sender: sender,
                                                               id: sid, key: key) else {
                runtimeStage = "R66_NATIVE_ROOM_KEY_REJECTED"; return
            }
            runtimeStage = "R66_NATIVE_ROOM_KEY_IMPORTED"
            retryPendingEncryptedEvents(roomId: room, sessionId: sid)
            requestedSessionIds.remove(room + "|" + sid)
            sendRoomKeyRequest(roomId: room, senderKey: sender, sessionId: sid, cancellation: true)
            return
        }

        guard (content["algorithm"] as? String) == megolmAlgorithm,
              let roomId = content["room_id"] as? String, !roomId.isEmpty,
              let sessionId = content["session_id"] as? String, !sessionId.isEmpty,
              let sessionKey = content["session_key"] as? String,
              let bytes = base64Decode(sessionKey) else { return }
        let senderKey = (content["sender_key"] as? String) ?? secureSenderCurve
        guard let session = decodeMegolmSession(bytes, roomId: roomId, sessionId: sessionId,
                                                senderKey: senderKey, forwarded: forwarded) else {
            runtimeStage = "MEGOLM_KEY_REJECT"
            print("[MagnistraE2EE] rejected malformed Megolm key")
            return
        }
        runtimeStage = "MEGOLM_KEY_DECODE_OK"
        if let old = loadMegolmSession(sessionId), old.initialIndex <= session.initialIndex {
            retryPendingEncryptedEvents(roomId: roomId, sessionId: sessionId)
            return
        }
        saveMegolmSession(sessionId, session)
        runtimeStage = "MEGOLM_KEY_STORED"
        retryPendingEncryptedEvents(roomId: roomId, sessionId: sessionId)
        requestedSessionIds.remove(roomId + "|" + sessionId)
        sendRoomKeyRequest(roomId: roomId, senderKey: senderKey,
                           sessionId: sessionId, cancellation: true)
        print("[MagnistraE2EE] Megolm key stored")
    }

    func decodeMegolmSession(_ bytes: [UInt8], roomId: String, sessionId: String,
                                     senderKey: String, forwarded: Bool) -> RoomMegolmSession? {
        let signed: Bool
        if bytes.count == 229 && bytes[0] == 2 { signed = true }
        else if bytes.count == 165 && bytes[0] == 1 { signed = false }
        else { return nil }
        let i = (UInt32(bytes[1]) << 24) | (UInt32(bytes[2]) << 16) |
                (UInt32(bytes[3]) << 8) | UInt32(bytes[4])
        let r0 = Array(bytes[5..<37]), r1 = Array(bytes[37..<69])
        let r2 = Array(bytes[69..<101]), r3 = Array(bytes[101..<133])
        let pub = Array(bytes[133..<165])
        guard base64Encode(pub) == sessionId else { return nil }
        if signed {
            let sig = Array(bytes[165..<229])
            guard ed25519Verify(publicKey: pub, message: Array(bytes[0..<165]), signature: sig) else { return nil }
        } else if !forwarded { return nil }
        return RoomMegolmSession(roomId: roomId, initialIndex: i,
                                       r0: r0, r1: r1, r2: r2, r3: r3,
                                       signingKey: pub, senderKey: senderKey)
    }

    struct MegolmMessage {
        let index: UInt32
        let ciphertext: [UInt8]
        let authenticatedBytes: [UInt8]
        let mac: [UInt8]
        let signedBytes: [UInt8]
        let signature: [UInt8]
    }

    func parseMegolmMessage(_ bytes: [UInt8]) -> MegolmMessage? {
        guard bytes.count > 73, bytes[0] == 3 else { return nil }
        let macStart = bytes.count - 72, sigStart = bytes.count - 64
        guard macStart > 1,
              let fields = parseWireFields(bytes, start: 1, end: macStart),
              let i64 = fields.ints[1], i64 <= UInt64(UInt32.max),
              let ciphertext = fields.strings[2] else { return nil }
        return MegolmMessage(index: UInt32(i64), ciphertext: ciphertext,
                             authenticatedBytes: Array(bytes[0..<macStart]),
                             mac: Array(bytes[macStart..<sigStart]),
                             signedBytes: Array(bytes[0..<sigStart]),
                             signature: Array(bytes[sigStart..<bytes.count]))
    }

    func advanceMegolm(_ r: ([UInt8], [UInt8], [UInt8], [UInt8]), from index: UInt32)
        -> ([UInt8], [UInt8], [UInt8], [UInt8])? {
        let next = index &+ 1
        var a = r.0, b = r.1, c = r.2, d = r.3
        if (next & 0x00FF_FFFF) == 0 {
            guard let na = hmacSHA256(key: a, data: [0]), let nb = hmacSHA256(key: a, data: [1]),
                  let nc = hmacSHA256(key: a, data: [2]), let nd = hmacSHA256(key: a, data: [3]) else { return nil }
            a = na; b = nb; c = nc; d = nd
        } else if (next & 0x0000_FFFF) == 0 {
            guard let nb = hmacSHA256(key: b, data: [1]), let nc = hmacSHA256(key: b, data: [2]),
                  let nd = hmacSHA256(key: b, data: [3]) else { return nil }
            b = nb; c = nc; d = nd
        } else if (next & 0x0000_00FF) == 0 {
            guard let nc = hmacSHA256(key: c, data: [2]), let nd = hmacSHA256(key: c, data: [3]) else { return nil }
            c = nc; d = nd
        } else {
            guard let nd = hmacSHA256(key: d, data: [3]) else { return nil }
            d = nd
        }
        return (a, b, c, d)
    }

    typealias OTKRecord = (priv: [UInt8], pub: [UInt8], uploaded: Bool)

    func storagePrefix() -> String? {
        guard let uid = userId, let did = deviceId else { return nil }
        return "magnistra.e2ee.\(uid).\(did)."
    }

    func loadOTKs() -> [String: OTKRecord] {
        guard let prefix = storagePrefix(),
              let raw = MagnistraPrivateState.shared.object(forKey: prefix + "otks") as? [String: String] else { return [:] }
        var out: [String: OTKRecord] = [:]
        for (keyId, text) in raw {
            let p = text.components(separatedBy: ",")
            guard p.count == 3, let priv = base64Decode(p[0]), priv.count == 32,
                  let pub = base64Decode(p[1]), pub.count == 32 else { continue }
            out[keyId] = (priv, pub, p[2] == "1")
        }
        return out
    }

    func saveOTKs(_ records: [String: OTKRecord]) {
        guard let prefix = storagePrefix() else { return }
        var raw: [String: String] = [:]
        for (keyId, rec) in records {
            raw[keyId] = base64Encode(rec.priv) + "," + base64Encode(rec.pub) + "," + (rec.uploaded ? "1" : "0")
        }
        MagnistraPrivateState.shared.set(raw, forKey: prefix + "otks")
        MagnistraPrivateState.shared.synchronize()
    }

    func nextOTKId() -> String {
        guard let prefix = storagePrefix() else { return "e0" }
        let key = prefix + "otkCounter"
        let next = MagnistraPrivateState.shared.integer(forKey: key) + 1
        MagnistraPrivateState.shared.set(next, forKey: key)
        return "e\(next)"
    }

    func findOTK(publicKey: [UInt8]) -> OTKRecord? {
        for (_, rec) in loadOTKs() where constantEqual(rec.pub, publicKey) { return rec }
        return nil
    }

    func consumeOTK(publicKey: [UInt8]) {
        var all = loadOTKs()
        var victim: String?
        for (keyId, rec) in all where constantEqual(rec.pub, publicKey) { victim = keyId; break }
        if let victim = victim { all.removeValue(forKey: victim); saveOTKs(all) }
    }

    struct MagnistraOlmSessionState {
        var rootKey: [UInt8]?
        var receiverChain: [UInt8]?
        var receiverRatchet: [UInt8]?
        var localRatchetPrivate: [UInt8]?
        var localRatchetPublic: [UInt8]?
        var oneTimePublic: [UInt8]?
    }

    func decodeOlmSessionState(_ text: String) -> MagnistraOlmSessionState? {
        let p = text.components(separatedBy: ",")
        if p.count == 2 {
            guard let chain = base64Decode(p[0]), chain.count == 32,
                  let eb = base64Decode(p[1]), eb.count == 32 else { return nil }
            return MagnistraOlmSessionState(rootKey: nil,
                                             receiverChain: chain,
                                             receiverRatchet: nil,
                                             localRatchetPrivate: nil,
                                             localRatchetPublic: nil,
                                             oneTimePublic: eb)
        }
        guard p.count == 7, p[0] == "v2" else { return nil }

        func field(_ index: Int) -> [UInt8]? {
            if p[index] == "-" { return nil }
            guard let b = base64Decode(p[index]), b.count == 32 else { return nil }
            return b
        }

        let root = field(1)
        let recvChain = field(2)
        let recvRatchet = field(3)
        let localPriv = field(4)
        let localPub = field(5)
        let otk = field(6)

        if recvChain == nil && (root == nil || localPriv == nil) { return nil }
        return MagnistraOlmSessionState(rootKey: root,
                                         receiverChain: recvChain,
                                         receiverRatchet: recvRatchet,
                                         localRatchetPrivate: localPriv,
                                         localRatchetPublic: localPub,
                                         oneTimePublic: otk)
    }

    func encodeOlmSessionState(_ state: MagnistraOlmSessionState) -> String {
        func field(_ value: [UInt8]?) -> String {
            guard let value = value, value.count == 32 else { return "-" }
            return base64Encode(value)
        }
        return ["v2",
                field(state.rootKey),
                field(state.receiverChain),
                field(state.receiverRatchet),
                field(state.localRatchetPrivate),
                field(state.localRatchetPublic),
                field(state.oneTimePublic)].joined(separator: ",")
    }

    func loadOlmInboundSession(_ id: String) -> MagnistraOlmSessionState? {
        guard let prefix = storagePrefix(),
              let raw = MagnistraPrivateState.shared.object(forKey: prefix + "olmSessions") as? [String: String],
              let stored = raw[id] else { return nil }
        return decodeOlmSessionState(stored)
    }

    func allOlmInboundSessions() -> [(String, MagnistraOlmSessionState)] {
        guard let prefix = storagePrefix(),
              let raw = MagnistraPrivateState.shared.object(forKey: prefix + "olmSessions") as? [String: String]
        else { return [] }
        var out: [(String, MagnistraOlmSessionState)] = []
        for id in raw.keys.sorted() {
            if let stored = raw[id], let state = decodeOlmSessionState(stored) {
                out.append((id, state))
            }
        }
        return out
    }

    func saveOlmInboundSession(_ id: String, state: MagnistraOlmSessionState) {
        guard let prefix = storagePrefix() else { return }
        var raw = (MagnistraPrivateState.shared.object(forKey: prefix + "olmSessions") as? [String: String]) ?? [:]
        raw[id] = encodeOlmSessionState(state)

        if raw.count > 32 {
            for key in raw.keys.sorted().prefix(raw.count - 32) {
                raw.removeValue(forKey: key)
            }
        }
        MagnistraPrivateState.shared.set(raw, forKey: prefix + "olmSessions")
        MagnistraPrivateState.shared.synchronize()
    }

    func loadMegolmSession(_ sessionId: String) -> RoomMegolmSession? {
        if let prefix = storagePrefix(),
           let all = MagnistraPrivateState.shared.object(forKey: prefix + "megolmSessions") as? [String: String],
           let text = all[sessionId] {
            let p = text.components(separatedBy: ",")
            if p.count == 8, let idx = UInt32(p[1]),
               let r0 = base64Decode(p[2]), r0.count == 32,
               let r1 = base64Decode(p[3]), r1.count == 32,
               let r2 = base64Decode(p[4]), r2.count == 32,
               let r3 = base64Decode(p[5]), r3.count == 32,
               let pub = base64Decode(p[6]), pub.count == 32 {
                return RoomMegolmSession(
                    roomId: p[0],
                    initialIndex: idx,
                    r0: r0,
                    r1: r1,
                    r2: r2,
                    r3: r3,
                    signingKey: pub,
                    senderKey: p[7]
                )
            }
        }

        guard let recovered = MagnistraMegolmKeyStore.shared.session(id: sessionId),
              recovered.firstKnownIndex >= 0,
              UInt64(recovered.firstKnownIndex) <= UInt64(UInt32.max),
              recovered.ratchet.count == 128,
              recovered.signingKey.count == 32 else {
            return nil
        }

        let ratchet = recovered.ratchet
        return RoomMegolmSession(
            roomId: recovered.roomId,
            initialIndex: UInt32(recovered.firstKnownIndex),
            r0: Array(ratchet[0..<32]),
            r1: Array(ratchet[32..<64]),
            r2: Array(ratchet[64..<96]),
            r3: Array(ratchet[96..<128]),
            signingKey: recovered.signingKey,
            senderKey: recovered.senderKey
        )
    }

    func saveMegolmSession(_ sessionId: String, _ session: RoomMegolmSession) {
        guard let prefix = storagePrefix() else { return }
        var all = (MagnistraPrivateState.shared.object(forKey: prefix + "megolmSessions") as? [String: String]) ?? [:]
        all[sessionId] = [session.roomId, String(session.initialIndex), base64Encode(session.r0),
                          base64Encode(session.r1), base64Encode(session.r2), base64Encode(session.r3),
                          base64Encode(session.signingKey), session.senderKey].joined(separator: ",")
        MagnistraPrivateState.shared.set(all, forKey: prefix + "megolmSessions")
        MagnistraPrivateState.shared.synchronize()
    }

    func nextSendCounter() -> Int {
        guard let prefix = storagePrefix() else { return Int(Date().timeIntervalSince1970) }
        let key = prefix + "sendCounter"
        let n = MagnistraPrivateState.shared.integer(forKey: key) + 1
        MagnistraPrivateState.shared.set(n, forKey: key)
        return n
    }

    struct WireFields { var strings: [Int: [UInt8]] = [:]; var ints: [Int: UInt64] = [:] }

    func parseWireFields(_ bytes: [UInt8], start: Int, end: Int) -> WireFields? {
        if start < 0 || end > bytes.count || start > end { return nil }
        var out = WireFields(), i = start
        while i < end {
            guard let tag = readVarint(bytes, index: &i, end: end) else { return nil }
            let field = Int(tag >> 3), wire = Int(tag & 7)
            if wire == 0 {
                guard let value = readVarint(bytes, index: &i, end: end) else { return nil }
                out.ints[field] = value
            } else if wire == 2 {
                guard let l = readVarint(bytes, index: &i, end: end), l <= UInt64(Int.max) else { return nil }
                let length = Int(l)
                guard i <= end - length else { return nil }
                out.strings[field] = Array(bytes[i..<(i + length)])
                i += length
            } else { return nil }
        }
        return out
    }

    func readVarint(_ bytes: [UInt8], index: inout Int, end: Int) -> UInt64? {
        var value: UInt64 = 0, shift: UInt64 = 0
        while index < end && shift <= 63 {
            let b = bytes[index]; index += 1
            value |= UInt64(b & 0x7F) << shift
            if (b & 0x80) == 0 { return value }
            shift += 7
        }
        return nil
    }

    func intValue(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        return nil
    }

    func jsonDictionary(_ bytes: [UInt8]) -> [String: Any]? {
        let data = Data(bytes)
        return (try? MagnistraJSONKit.jsonObject(with: data, options: [])) as? [String: Any]
    }

    func canonicalJSON(_ value: Any) -> String? {
        if let s = value as? String { return "\"" + jsonEscape(s) + "\"" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if value is NSNull { return "null" }
        if let n = value as? NSNumber { return n.stringValue }
        if let array = value as? [Any] {
            var parts: [String] = []
            for item in array {
                guard let encoded = canonicalJSON(item) else { return nil }
                parts.append(encoded)
            }
            return "[" + parts.joined(separator: ",") + "]"
        }
        if let dict = value as? [String: Any] {
            var parts: [String] = []
            for key in dict.keys.sorted() {
                guard let item = dict[key], let encoded = canonicalJSON(item) else { return nil }
                parts.append("\"" + jsonEscape(key) + "\":" + encoded)
            }
            return "{" + parts.joined(separator: ",") + "}"
        }
        return nil
    }

    func jsonEscape(_ s: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for scalar in s.unicodeScalars {
            let v = Int(scalar.value)
            switch v {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0..<0x20:
                out += "\\u00"
                out.append(hex[(v >> 4) & 0xF])
                out.append(hex[v & 0xF])
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    let b64Table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    func base64Encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = [], i = 0
        while i < bytes.count {
            let b0 = Int(bytes[i]); i += 1
            let h1 = i < bytes.count, b1 = h1 ? Int(bytes[i]) : 0; if h1 { i += 1 }
            let h2 = i < bytes.count, b2 = h2 ? Int(bytes[i]) : 0; if h2 { i += 1 }
            out.append(b64Table[(b0 >> 2) & 63]); out.append(b64Table[((b0 & 3) << 4) | ((b1 >> 4) & 15)])
            if h1 { out.append(b64Table[((b1 & 15) << 2) | ((b2 >> 6) & 3)]) }
            if h2 { out.append(b64Table[b2 & 63]) }
        }
        return String(decoding: out, as: UTF8.self)
    }

    func base64Decode(_ string: String) -> [UInt8]? {
        var vals: [UInt8] = []
        for c in string.utf8 {
            let v: UInt8
            switch c {
            case 65...90: v = c - 65
            case 97...122: v = c - 97 + 26
            case 48...57: v = c - 48 + 52
            case 43: v = 62
            case 47: v = 63
            case 61: continue
            default: return nil
            }
            vals.append(v)
        }
        if vals.count % 4 == 1 { return nil }
        var out: [UInt8] = [], i = 0
        while i < vals.count {
            let a = vals[i]; i += 1; guard i < vals.count else { return nil }
            let b = vals[i]; i += 1; out.append((a << 2) | (b >> 4))
            if i < vals.count { let c = vals[i]; i += 1; out.append((b << 4) | (c >> 2));
                if i < vals.count { let d = vals[i]; i += 1; out.append((c << 6) | d) } }
        }
        return out
    }

    func x25519Keygen() -> ([UInt8], [UInt8])? {
        var priv = [UInt8](repeating: 0, count: 32), pub = [UInt8](repeating: 0, count: 32)
        let rc = priv.withUnsafeMutableBufferPointer { p in pub.withUnsafeMutableBufferPointer { q in
            magnistra_crypto_x25519_keygen(p.baseAddress, q.baseAddress) } }
        return rc == 1 ? (priv, pub) : nil
    }

    func x25519Shared(privateKey: [UInt8], peerPublic: [UInt8]) -> [UInt8]? {
        guard privateKey.count == 32, peerPublic.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let rc = privateKey.withUnsafeBufferPointer { p in peerPublic.withUnsafeBufferPointer { q in
            out.withUnsafeMutableBufferPointer { o in magnistra_crypto_x25519_shared(p.baseAddress, q.baseAddress, o.baseAddress) } } }
        return rc == 1 ? out : nil
    }

    func ed25519Sign(privateKey: [UInt8], message: [UInt8]) -> [UInt8]? {
        guard privateKey.count == 32 else { return nil }
        var sig = [UInt8](repeating: 0, count: 64)
        let rc = privateKey.withUnsafeBufferPointer { p in message.withUnsafeBufferPointer { m in
            sig.withUnsafeMutableBufferPointer { s in magnistra_crypto_ed25519_sign(p.baseAddress, m.baseAddress, m.count, s.baseAddress) } } }
        return rc == 1 ? sig : nil
    }

    func ed25519Verify(publicKey: [UInt8], message: [UInt8], signature: [UInt8]) -> Bool {
        guard publicKey.count == 32, signature.count == 64 else { return false }
        let rc = publicKey.withUnsafeBufferPointer { p in message.withUnsafeBufferPointer { m in
            signature.withUnsafeBufferPointer { s in magnistra_crypto_ed25519_verify(p.baseAddress, m.baseAddress, m.count, s.baseAddress) } } }
        return rc == 1
    }

    func sha256(_ data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = data.withUnsafeBufferPointer { p in out.withUnsafeMutableBufferPointer { o in
            magnistra_crypto_sha256(p.baseAddress, p.count, o.baseAddress) } }
        return rc == 1 ? out : nil
    }

    func hmacSHA256(key: [UInt8], data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = key.withUnsafeBufferPointer { k in data.withUnsafeBufferPointer { d in out.withUnsafeMutableBufferPointer { o in
            magnistra_crypto_hmac_sha256(k.baseAddress, k.count, d.baseAddress, d.count, o.baseAddress) } } }
        return rc == 1 ? out : nil
    }

    func hkdfSHA256(ikm: [UInt8], info: [UInt8], count: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: count)
        let rc = ikm.withUnsafeBufferPointer { p in info.withUnsafeBufferPointer { i in out.withUnsafeMutableBufferPointer { o in
            magnistra_crypto_hkdf_sha256(p.baseAddress, p.count, i.baseAddress, i.count, o.baseAddress, o.count) } } }
        return rc == 1 ? out : nil
    }

    func hkdfSHA256(salt: [UInt8], ikm: [UInt8],
                            info: [UInt8], count: Int) -> [UInt8]? {
        guard !salt.isEmpty, count >= 0, count <= 255 * 32,
              let prk = hmacSHA256(key: salt, data: ikm) else { return nil }
        if count == 0 { return [] }

        var out: [UInt8] = []
        var previous: [UInt8] = []
        var counter: UInt8 = 1
        while out.count < count {
            var block = previous
            block += info
            block.append(counter)
            guard let next = hmacSHA256(key: prk, data: block) else { return nil }
            previous = next
            let remaining = count - out.count
            out += Array(next.prefix(min(32, remaining)))
            if out.count < count {
                if counter == 255 { return nil }
                counter = counter &+ 1
            }
        }
        return out
    }

    func aes256CBCDecrypt(key: [UInt8], iv: [UInt8], ciphertext: [UInt8]) -> [UInt8]? {
        guard key.count == 32, iv.count == 16, !ciphertext.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: ciphertext.count), outLen = ciphertext.count
        let rc = key.withUnsafeBufferPointer { k in iv.withUnsafeBufferPointer { v in ciphertext.withUnsafeBufferPointer { c in
            out.withUnsafeMutableBufferPointer { o in magnistra_crypto_aes256_cbc_decrypt(k.baseAddress, v.baseAddress, c.baseAddress, c.count, o.baseAddress, &outLen) } } } }
        guard rc == 1, outLen <= out.count else { return nil }
        return Array(out[0..<outLen])
    }

    func constantEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        let rc = a.withUnsafeBufferPointer { x in b.withUnsafeBufferPointer { y in
            magnistra_crypto_constant_equal(x.baseAddress, y.baseAddress, x.count) } }
        return rc == 1
    }
}