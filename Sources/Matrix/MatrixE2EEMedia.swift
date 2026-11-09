// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix encrypted media: preparing, registering and decrypting attachments.
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



extension MatrixE2EEManager {
    static func encryptedMediaRecord(for mxc: String) -> MagnistraEncryptedMediaRecord? {
        magnistraEncryptedMediaLock.lock()
        let r = magnistraEncryptedMediaByMXC[mxc]
        magnistraEncryptedMediaLock.unlock()
        return r
    }

    static func registerEncryptedMedia(_ record: MagnistraEncryptedMediaRecord, mxc: String) {
        magnistraEncryptedMediaLock.lock()
        magnistraEncryptedMediaByMXC[mxc] = record
        magnistraEncryptedMediaLock.unlock()
    }

    static func registerEncryptedMedia(in content: inout [String: Any]) {
        if let file = content["file"] as? [String: Any],
           let pair = encryptedMediaRecord(from: file) {
            registerEncryptedMedia(pair.record, mxc: pair.mxc)
            content["url"] = pair.mxc
        }
        if var info = content["info"] as? [String: Any],
           let thumb = info["thumbnail_file"] as? [String: Any],
           let pair = encryptedMediaRecord(from: thumb) {
            registerEncryptedMedia(pair.record, mxc: pair.mxc)
            info["thumbnail_url"] = pair.mxc
            content["info"] = info
        }
    }

    static func encryptedMediaRecord(from file: [String: Any])
        -> (mxc: String, record: MagnistraEncryptedMediaRecord)? {
        guard (file["v"] as? String) == "v2",
              let mxc = file["url"] as? String, mxc.hasPrefix("mxc://"),
              let keyObject = file["key"] as? [String: Any],
              (keyObject["kty"] as? String) == "oct",
              (keyObject["alg"] as? String) == "A256CTR",
              let keyText = keyObject["k"] as? String,
              let ivText = file["iv"] as? String,
              let hashes = file["hashes"] as? [String: Any],
              let hashText = hashes["sha256"] as? String,
              let key = magnistraMediaBase64Decode(keyText, expected: 32),
              let iv = magnistraMediaBase64Decode(ivText, expected: 16),
              let sha = magnistraMediaBase64Decode(hashText, expected: 32) else {
            return nil
        }
        return (mxc, MagnistraEncryptedMediaRecord(key: key, iv: iv, sha256: sha))
    }

    func prepareOutboundMedia(roomId: String, inputPath: String,
                              completion: @escaping (MagnistraPreparedMedia?, Error?) -> Void) {
        roomEncryptionEnabled(roomId: roomId) { [weak self] encrypted, error in
            guard let self = self else { return }
            if let error = error { completion(nil, error); return }
            guard encrypted else {
                completion(MagnistraPreparedMedia(path: inputPath, encrypted: nil, removeWhenDone: false), nil)
                return
            }
            guard FileManager.default.fileExists(atPath: inputPath),
                  let key = self.outboundRandomBytes(32),
                  let ivPrefix = self.outboundRandomBytes(8) else {
                completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                            error: "Could not create encrypted-media key material"))
                return
            }
            let iv = ivPrefix + [UInt8](repeating: 0, count: 8)
            let outPath = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("magnistra-e2ee-\(self.nextSendCounter()).bin")
            var sha = [UInt8](repeating: 0, count: 32)
            let rc = key.withUnsafeBufferPointer { k in
                iv.withUnsafeBufferPointer { v in
                    sha.withUnsafeMutableBufferPointer { s in
                        inputPath.withCString { src in
                            outPath.withCString { dst in
                                magnistra_crypto_aes256_ctr_encrypt_file(
                                    src, dst, k.baseAddress, v.baseAddress, s.baseAddress)
                            }
                        }
                    }
                }
            }
            guard rc == 1 else {
                try? FileManager.default.removeItem(atPath: outPath)
                completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                            error: "Encrypted-media AES-CTR preparation failed"))
                return
            }
            let record = MagnistraEncryptedMediaRecord(key: key, iv: iv, sha256: sha)
            completion(MagnistraPreparedMedia(path: outPath, encrypted: record, removeWhenDone: true), nil)
        }
    }

    func r66PrepareNativeOutbound(
        roomId: String, type: String, content: [String: Any],
        completion: @escaping (String?, [String: Any]?, Error?) -> Void) {
        let engine = MatrixCryptoEngine.shared
        guard let ident = identity, let uid = userId, let did = deviceId,
              let api = api, let group = engine.rotateGroupIfNeeded(room: roomId) else {
            completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                       error: "R66 native state cannot be persisted"))
            return
        }
        outboundDevices(roomId: roomId) { [weak self] devices, error in
            guard let self = self else { return }
            if let error = error { completion(nil, nil, error); return }
            guard let devices = devices else {
                completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                           error: "R66 device query failed")); return
            }
            let missing = devices.filter { !group.2.contains(self.outboundDeviceFingerprint($0)) }
            let finish: () -> Void = {
                guard let envelope = engine.encryptGroup(room: roomId, type: type,
                                                          content: content, device: did) else {
                    completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                               error: "R66 native Megolm encryption/state persistence failed"))
                    return
                }
                completion("m.room.encrypted", envelope, nil)
            }
            if missing.isEmpty { finish(); return }
            let needOTK = missing.filter {
                !engine.hasOlm(peer: $0.userId + "|" + $0.deviceId + "|" + $0.curve25519)
            }
            let distribute: ([String: Any]) -> Void = { claimed in
                var messages: [String: Any] = [:]
                var recipients: [String] = []
                var ownSkippedNoOTK = 0
                for d in missing {
                    let peer = d.userId + "|" + d.deviceId + "|" + d.curve25519
                    let readyOlm = engine.hasOlm(peer: peer)
                    var otkText: String? = nil
                    if !readyOlm,
                       let u = claimed[d.userId] as? [String: Any],
                       let response = u[d.deviceId] as? [String: Any],
                       let otk = self.verifiedClaimedOTK(response, device: d) {
                        otkText = self.base64Encode(otk)
                    }

                    if !readyOlm && otkText == nil {
                        if d.userId == uid {
                            ownSkippedNoOTK += 1
                            continue
                        }
                        completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                   error: "R66 recipient has no valid signed One-Time Key; no message sent"))
                        return
                    }
                    let payload: [String: Any] = [
                        "type": "m.room_key",
                        "content": ["algorithm": self.megolmAlgorithm, "room_id": roomId,
                                    "session_id": group.0, "session_key": group.1],
                        "sender": uid, "recipient": d.userId,
                        "recipient_keys": ["ed25519": d.ed25519],
                        "keys": ["ed25519": self.base64Encode(ident.edPublic)]
                    ]
                    guard let packet = engine.encryptOlm(peer: peer, peerCurve: d.curve25519,
                                                         oneTime: otkText, plain: payload) else {
                        completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                   error: readyOlm
                                     ? "R66 stored native Olm session encryption/persistence failed"
                                     : "R66 verified OTK provided but native Olm creation/encryption failed"))
                        return
                    }
                    var dest = (messages[d.userId] as? [String: Any]) ?? [:]
                    dest[d.deviceId] = ["algorithm": self.olmAlgorithm,
                                        "sender_key": self.base64Encode(ident.curvePublic),
                                        "ciphertext": [d.curve25519: packet]]
                    messages[d.userId] = dest
                    recipients.append(self.outboundDeviceFingerprint(d))
                }

                if recipients.isEmpty {

                    if !group.2.isEmpty {
                        finish()
                        return
                    }
                    completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                               error: "R66 no recipient with an established Olm session or valid signed One-Time Key"))
                    return
                }
                if ownSkippedNoOTK > 0 {
                    print("[Matrix E2EE] pending own devices without OTK: \(ownSkippedNoOTK); not marked delivered")
                }
                let txn = "magnistra-native-r66-\(self.nextSendCounter())"
                api.put("/_matrix/client/v3/sendToDevice/m.room.encrypted/\(txn)",
                        body: ["messages": messages]) { _, error in
                    if let error = error { completion(nil, nil, error); return }
                    guard engine.groupShareDone(room: roomId, fingerprints: recipients) else {
                        completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                   error: "R66 cannot persist acknowledged key distribution")); return
                    }
                    finish()
                }
            }
            if needOTK.isEmpty { distribute([:]); return }
            var request: [String: Any] = [:]
            for d in needOTK {
                var byDevice = (request[d.userId] as? [String: Any]) ?? [:]
                byDevice[d.deviceId] = "signed_curve25519"
                request[d.userId] = byDevice
            }
            api.post("/_matrix/client/v3/keys/claim",
                     body: ["one_time_keys": request, "timeout": 10000]) { json, error in
                if let error = error { completion(nil, nil, error); return }
                guard let all = json?["one_time_keys"] as? [String: Any] else {
                    completion(nil, nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                               error: "R66 no verifiable claimed one-time keys")); return
                }
                distribute(all)
            }
        }
    }

    func prepareOutboundRoomEvent(roomId: String, type: String, content: [String: Any],
                                  knownEncrypted: Bool? = nil,
                                  completion: @escaping (String?, [String: Any]?, Error?) -> Void) {
        let continueWithMode: (Bool) -> Void = { [weak self] encrypted in
            guard let self = self else { return }
            if !encrypted {
                completion(type, content, nil)
                return
            }
            if MatrixCryptoEngine.shared.active {
                self.r66PrepareNativeOutbound(roomId: roomId, type: type,
                                               content: content, completion: completion)
                return
            }
            self.ensureOutboundMegolmShared(roomId: roomId) { [weak self] session, error in
                guard let self = self else { return }
                if let error = error { completion(nil, nil, error); return }
                guard var session = session,
                      let encryptedContent = self.encryptOutboundMegolm(
                        roomId: roomId, type: type, content: content, session: &session) else {
                    completion(nil, nil, MatrixAPIClient.MatrixError(
                        errcode: "M_UNKNOWN", error: "Megolm outbound encryption failed"))
                    return
                }
                self.saveOutboundMegolm(session)
                completion("m.room.encrypted", encryptedContent, nil)
            }
        }

        if let knownEncrypted = knownEncrypted {
            continueWithMode(knownEncrypted)
        } else {
            roomEncryptionEnabled(roomId: roomId) { encrypted, error in
                if let error = error { completion(nil, nil, error); return }
                continueWithMode(encrypted)
            }
        }
    }

    func roomEncryptionEnabled(roomId: String,
                                       completion: @escaping (Bool, Error?) -> Void) {
        guard let api = api else {
            completion(false, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                          error: "E2EE manager is not attached"))
            return
        }
        api.get("/_matrix/client/v3/rooms/\(roomId)/state/m.room.encryption", timeout: 30) { json, error in
            if let json = json, (json["algorithm"] as? String) == self.megolmAlgorithm {
                completion(true, nil)
                return
            }
            if let matrixError = error as? MatrixAPIClient.MatrixError,
               matrixError.errcode == "M_NOT_FOUND" {
                completion(false, nil)
                return
            }
            if error == nil {
                completion(false, nil)
                return
            }
            completion(false, error)
        }
    }

    func ensureOutboundMegolmShared(
        roomId: String,
        completion: @escaping (MagnistraOutboundMegolm?, Error?) -> Void) {
        guard api != nil, userId != nil, deviceId != nil, identity != nil else {
            completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                        error: "E2EE manager is not attached"))
            return
        }

        var session = loadOutboundMegolm(roomId: roomId) ?? makeOutboundMegolm(roomId: roomId)
        guard var current = session else {
            completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                        error: "Could not create Megolm outbound session"))
            return
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if current.messageCount >= 100 || now - current.createdMs >= 604800000 {
            guard let rotated = makeOutboundMegolm(roomId: roomId) else {
                completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                            error: "Could not rotate Megolm outbound session"))
                return
            }
            current = rotated
        }

        ensureOwnInboundMirror(current)

        outboundDevices(roomId: roomId) { [weak self] devices, error in
            guard let self = self else { return }
            if let error = error { completion(nil, error); return }
            let devices = devices ?? []
            let missing = devices.filter {
                !current.sharedFingerprints.contains(self.outboundDeviceFingerprint($0))
            }

            let ownUser = self.userId ?? ""
            let ownUnconfirmed = devices.filter { d in
                return d.userId == ownUser &&
                    !self.r64DeliveredToOwnDevice(session: current, device: d) &&
                    current.sharedFingerprints.contains(self.outboundDeviceFingerprint(d))
            }
            let targets = missing + ownUnconfirmed
            if targets.isEmpty {
                self.saveOutboundMegolm(current)
                completion(current, nil)
                return
            }

            self.claimAndShareMegolm(session: current, devices: targets) { [weak self] shared, error in
                guard let self = self else { return }

                if error != nil && missing.isEmpty && !current.sharedFingerprints.isEmpty {
                    print("[MagnistraE2EE] own key delivery deferred; bridge send remains available")
                    self.saveOutboundMegolm(current)
                    completion(current, nil)
                    return
                }

                if let matrixError = error as? MatrixAPIClient.MatrixError,
                   matrixError.errcode == "M_UNKNOWN",
                   matrixError.error == "No recipient device supplied a verifiable signed_curve25519 key",
                   !current.sharedFingerprints.isEmpty {
                    print("[MagnistraE2EE] established Megolm kept; deferred unclaimable new device(s)")
                    self.saveOutboundMegolm(current)
                    completion(current, nil)
                    return
                }
                if let error = error { completion(nil, error); return }

                var updated = current
                for device in shared {
                    updated.sharedFingerprints.insert(self.outboundDeviceFingerprint(device))
                }
                self.saveOutboundMegolm(updated)
                completion(updated, nil)
            }
        }
    }

    func ensureOwnInboundMirror(_ session: MagnistraOutboundMegolm) {

        guard loadMegolmSession(session.sessionId) == nil,
              let ident = identity else { return }
        let mirror = RoomMegolmSession(
            roomId: session.roomId,
            initialIndex: session.index,
            r0: session.r0, r1: session.r1, r2: session.r2, r3: session.r3,
            signingKey: session.signingPublic,
            senderKey: magnistraMediaBase64(ident.curvePublic))
        saveMegolmSession(session.sessionId, mirror)
        print("[MagnistraE2EE] own outbound Megolm registered for local echo")
    }

    func outboundDevices(roomId: String,
                                 completion: @escaping ([MagnistraOutboundDevice]?, Error?) -> Void) {
        guard let api = api, let ownUser = userId, let ownDevice = deviceId else {
            completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                        error: "E2EE manager is not attached"))
            return
        }
        api.get("/_matrix/client/v3/rooms/\(roomId)/joined_members", timeout: 30) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error { completion(nil, error); return }
            guard let joined = json?["joined"] as? [String: Any] else {
                completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                            error: "joined_members returned no joined map"))
                return
            }

            var query: [String: Any] = [:]
            for uid in joined.keys { query[uid] = [String]() }
            api.post("/_matrix/client/v3/keys/query", body: ["device_keys": query]) { json, error in
                if let error = error { completion(nil, error); return }
                guard let users = json?["device_keys"] as? [String: Any] else {
                    completion(nil, MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                                error: "keys/query returned no device_keys"))
                    return
                }
                var out: [MagnistraOutboundDevice] = []
                for (uid, rawDevices) in users {
                    guard let devices = rawDevices as? [String: Any] else { continue }
                    for (did, rawDevice) in devices {
                        if uid == ownUser && did == ownDevice { continue }
                        guard var device = rawDevice as? [String: Any],
                              (device["user_id"] as? String) == uid,
                              (device["device_id"] as? String) == did,
                              let keys = device["keys"] as? [String: Any],
                              let curve = keys["curve25519:\(did)"] as? String,
                              let ed = keys["ed25519:\(did)"] as? String,
                              let sigs = device["signatures"] as? [String: Any],
                              let byUser = sigs[uid] as? [String: Any],
                              let sigText = byUser["ed25519:\(did)"] as? String,
                              let edBytes = magnistraMediaBase64Decode(ed, expected: 32),
                              let sigBytes = magnistraMediaBase64Decode(sigText, expected: 64) else {
                            continue
                        }
                        device.removeValue(forKey: "signatures")
                        device.removeValue(forKey: "unsigned")
                        guard let canonical = self.canonicalJSON(device),
                              self.ed25519Verify(publicKey: edBytes,
                                                 message: Array(canonical.utf8),
                                                 signature: sigBytes) else {
                            continue
                        }
                        out.append(MagnistraOutboundDevice(userId: uid, deviceId: did,
                                                            curve25519: curve, ed25519: ed))
                    }
                }
                completion(out, nil)
            }
        }
    }

    struct MagnistraOutboundOlmSender {
        var sessionId: String
        var oneTimePublic: [UInt8]
        var basePublic: [UInt8]
        var rootKey: [UInt8]
        var sendingChain: [UInt8]
        var ratchetPrivate: [UInt8]
        var ratchetPublic: [UInt8]
        var nextIndex: UInt64
        var acknowledgedRatchet: [UInt8]?
    }

    func r64OlmSenderKey(_ device: MagnistraOutboundDevice) -> String {
        return outboundDeviceFingerprint(device)
    }

    func r64LoadOlmSender(_ device: MagnistraOutboundDevice) -> MagnistraOutboundOlmSender? {
        guard let prefix = storagePrefix(),
              let dictionary = MagnistraPrivateState.shared.dictionary(forKey: prefix + "olmSender") as? [String: [String: String]],
              let item = dictionary[r64OlmSenderKey(device)] else { return nil }
        func field(_ name: String) -> [UInt8]? {
            guard let value = item[name],
                  let b = base64Decode(value), b.count == 32 else { return nil }
            return b
        }
        guard let sid = item["sid"], !sid.isEmpty,
              let otk = field("otk"), let base = field("base"),
              let root = field("root"), let chain = field("chain"),
              let rp = field("rp"), let rpub = field("rpub"),
              let rawIndex = item["index"], let index = UInt64(rawIndex),
              index < 4096 else { return nil }
        return MagnistraOutboundOlmSender(
            sessionId: sid, oneTimePublic: otk, basePublic: base,
            rootKey: root, sendingChain: chain,
            ratchetPrivate: rp, ratchetPublic: rpub,
            nextIndex: index, acknowledgedRatchet: field("ack"))
    }

    func r64SaveOlmSender(_ state: MagnistraOutboundOlmSender,
                                  recipient: MagnistraOutboundDevice) {
        guard let prefix = storagePrefix() else { return }
        var dictionary = (MagnistraPrivateState.shared.dictionary(forKey: prefix + "olmSender")
                          as? [String: [String: String]]) ?? [:]
        dictionary[r64OlmSenderKey(recipient)] = [
            "sid": state.sessionId,
            "otk": base64Encode(state.oneTimePublic),
            "base": base64Encode(state.basePublic),
            "root": base64Encode(state.rootKey),
            "chain": base64Encode(state.sendingChain),
            "rp": base64Encode(state.ratchetPrivate),
            "rpub": base64Encode(state.ratchetPublic),
            "index": String(state.nextIndex),
            "ack": state.acknowledgedRatchet.map { base64Encode($0) } ?? "-"
        ]
        MagnistraPrivateState.shared.set(dictionary, forKey: prefix + "olmSender")
        MagnistraPrivateState.shared.synchronize()
    }

    func r64CreateOlmSender(_ recipient: MagnistraOutboundDevice,
                                    otk: [UInt8]) -> MagnistraOutboundOlmSender? {
        guard let ident = identity,
              let remote = base64Decode(recipient.curve25519), remote.count == 32,
              let base = x25519Keygen(), let ratchet = x25519Keygen(),
              let s1 = x25519Shared(privateKey: ident.curvePrivate, peerPublic: otk),
              let s2 = x25519Shared(privateKey: base.0, peerPublic: remote),
              let s3 = x25519Shared(privateKey: base.0, peerPublic: otk),
              let rootAndChain = hkdfSHA256(ikm: s1 + s2 + s3,
                                           info: Array("OLM_ROOT".utf8), count: 64),
              let sidBytes = sha256(ident.curvePublic + base.1) else { return nil }
        let state = MagnistraOutboundOlmSender(
            sessionId: base64Encode(sidBytes), oneTimePublic: otk,
            basePublic: base.1, rootKey: Array(rootAndChain[0..<32]),
            sendingChain: Array(rootAndChain[32..<64]),
            ratchetPrivate: ratchet.0, ratchetPublic: ratchet.1,
            nextIndex: 0, acknowledgedRatchet: nil)

        saveOlmInboundSession(state.sessionId, state: MagnistraOlmSessionState(
            rootKey: state.rootKey, receiverChain: nil, receiverRatchet: nil,
            localRatchetPrivate: ratchet.0, localRatchetPublic: ratchet.1,
            oneTimePublic: nil))
        return state
    }

    func r64Envelope(recipient: MagnistraOutboundDevice,
                             otk: [UInt8]?, payload: [String: Any]) -> [String: Any]? {
        guard let uid = userId, let ident = identity else { return nil }
        var state: MagnistraOutboundOlmSender
        if let saved = r64LoadOlmSender(recipient) {
            state = saved
        } else {
            guard let claimed = otk, let created = r64CreateOlmSender(recipient, otk: claimed) else { return nil }
            state = created
        }

        if let receive = loadOlmInboundSession(state.sessionId),
           let peerRatchet = receive.receiverRatchet,
           let receiveRoot = receive.rootKey,
           (state.acknowledgedRatchet == nil ||
            !constantEqual(state.acknowledgedRatchet!, peerRatchet)) {
            guard let next = x25519Keygen(),
                  let dh = x25519Shared(privateKey: next.0, peerPublic: peerRatchet),
                  let derived = hkdfSHA256(salt: receiveRoot, ikm: dh,
                                           info: Array("OLM_RATCHET".utf8), count: 64) else { return nil }
            state.rootKey = Array(derived[0..<32])
            state.sendingChain = Array(derived[32..<64])
            state.ratchetPrivate = next.0
            state.ratchetPublic = next.1
            state.nextIndex = 0
            state.acknowledgedRatchet = peerRatchet
            var updatedReceive = receive
            updatedReceive.rootKey = state.rootKey
            updatedReceive.localRatchetPrivate = next.0
            updatedReceive.localRatchetPublic = next.1
            saveOlmInboundSession(state.sessionId, state: updatedReceive)
        }
        let clear: [String: Any] = [
            "type": "m.room_key", "content": payload,
            "sender": uid, "recipient": recipient.userId,
            "recipient_keys": ["ed25519": recipient.ed25519],
            "keys": ["ed25519": base64Encode(ident.edPublic)]
        ]
        guard state.nextIndex < 4096,
              MagnistraJSONKit.isValidJSONObject(clear),
              let encoded = try? MagnistraJSONKit.data(withJSONObject: clear, options: []),
              let messageKey = hmacSHA256(key: state.sendingChain, data: [0x01]),
              let followingChain = hmacSHA256(key: state.sendingChain, data: [0x02]),
              let keys = hkdfSHA256(ikm: messageKey,
                                    info: Array("OLM_KEYS".utf8), count: 80),
              let cipher = aes256CBCEncrypt(key: Array(keys[0..<32]),
                                            iv: Array(keys[64..<80]),
                                            plaintext: [UInt8](encoded)) else { return nil }
        var normal: [UInt8] = [3]
        normal += outboundWireString(field: 1, value: state.ratchetPublic)
        normal += outboundWireInt(field: 2, value: state.nextIndex)
        normal += outboundWireString(field: 4, value: cipher)
        guard let mac = hmacSHA256(key: Array(keys[32..<64]), data: normal) else { return nil }
        normal += Array(mac[0..<8])
        let frame: [UInt8]
        let messageType: Int
        if state.acknowledgedRatchet == nil {
            var prekey: [UInt8] = [3]
            prekey += outboundWireString(field: 1, value: state.oneTimePublic)
            prekey += outboundWireString(field: 2, value: state.basePublic)
            prekey += outboundWireString(field: 3, value: ident.curvePublic)
            prekey += outboundWireString(field: 4, value: normal)
            frame = prekey
            messageType = 0
        } else {
            frame = normal
            messageType = 1
        }
        state.sendingChain = followingChain
        state.nextIndex += 1

        r64SaveOlmSender(state, recipient: recipient)
        return ["algorithm": olmAlgorithm,
                "sender_key": base64Encode(ident.curvePublic),
                "ciphertext": [recipient.curve25519: [
                    "type": messageType, "body": base64Encode(frame)]]]
    }

    func r64DeliveredToOwnDevice(session: MagnistraOutboundMegolm,
                                        device: MagnistraOutboundDevice) -> Bool {
        guard let prefix = storagePrefix() else { return false }
        let record = session.sessionId + "|" + outboundDeviceFingerprint(device)
        return (MagnistraPrivateState.shared.stringArray(forKey: prefix + "olmRoomDelivery") ?? []).contains(record)
    }

    func r64RecordOwnDelivery(session: MagnistraOutboundMegolm,
                                      devices: [MagnistraOutboundDevice]) {
        guard let prefix = storagePrefix() else { return }
        let own = userId ?? ""
        var acknowledged = Set(MagnistraPrivateState.shared.stringArray(forKey: prefix + "olmRoomDelivery") ?? [])
        for d in devices where d.userId == own {
            acknowledged.insert(session.sessionId + "|" + outboundDeviceFingerprint(d))
        }
        MagnistraPrivateState.shared.set(Array(acknowledged).sorted().suffix(512).map { $0 },
                                  forKey: prefix + "olmRoomDelivery")
        MagnistraPrivateState.shared.synchronize()
    }

    func claimAndShareMegolm(
        session: MagnistraOutboundMegolm,
        devices: [MagnistraOutboundDevice],
        completion: @escaping ([MagnistraOutboundDevice], Error?) -> Void) {
        guard let api = api else {
            completion([], MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                        error: "E2EE manager is not attached"))
            return
        }
        let fresh = devices.filter { self.r64LoadOlmSender($0) == nil }
        let distribute: ([String: Any]) -> Void = { [weak self] claimed in
            guard let self = self else { return }
            guard let roomKey = self.outboundRoomKeyContent(session) else {
                completion([], MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                            error: "Cannot construct outbound room key"))
                return
            }
            var messages: [String: Any] = [:]
            var prepared: [MagnistraOutboundDevice] = []
            var omitted = 0
            for device in devices {
                var otk: [UInt8]? = nil
                if self.r64LoadOlmSender(device) == nil,
                   let byUser = claimed[device.userId] as? [String: Any],
                   let byDevice = byUser[device.deviceId] as? [String: Any] {

                    otk = self.verifiedClaimedOTK(byDevice, device: device)
                }
                guard let encrypted = self.r64Envelope(
                    recipient: device, otk: otk, payload: roomKey) else {
                    omitted += 1
                    continue
                }
                var dest = (messages[device.userId] as? [String: Any]) ?? [:]
                dest[device.deviceId] = encrypted
                messages[device.userId] = dest
                prepared.append(device)
            }
            guard !prepared.isEmpty else {
                completion([], MatrixAPIClient.MatrixError(
                    errcode: "M_UNKNOWN",
                    error: "No recipient device supplied a verifiable signed_curve25519 key"))
                return
            }
            let txn = "magnistra-roomkey-\(self.nextSendCounter())"
            api.put("/_matrix/client/v3/sendToDevice/m.room.encrypted/\(txn)",
                    body: ["messages": messages]) { _, error in
                if let error = error { completion([], error); return }

                self.r64RecordOwnDelivery(session: session, devices: prepared)
                print("[MagnistraE2EE] room key server accepted " +
                      String(prepared.count) + " device(s); missing=" + String(omitted))
                completion(prepared, nil)
            }
        }
        if fresh.isEmpty { distribute([:]); return }
        var request: [String: Any] = [:]
        for d in fresh {
            var byDevice = (request[d.userId] as? [String: Any]) ?? [:]
            byDevice[d.deviceId] = "signed_curve25519"
            request[d.userId] = byDevice
        }
        api.post("/_matrix/client/v3/keys/claim",
                 body: ["one_time_keys": request, "timeout": 10000]) { json, error in
            if let error = error { completion([], error); return }
            distribute((json?["one_time_keys"] as? [String: Any]) ?? [:])
        }
    }

    func repairOlmSession(senderCurve: String) {
        guard !senderCurve.isEmpty,
              !olmReplacementInFlight.contains(senderCurve),
              let api = api, let uid = userId, let ownDevice = deviceId,
              let prefix = storagePrefix() else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let defaults = MagnistraPrivateState.shared
        let lastMap = defaults.dictionary(forKey: prefix + "olmReplacementLastMs") ?? [:]
        if let last = lastMap[senderCurve] as? NSNumber,
           now - last.int64Value < olmReplacementMinIntervalMs {
            return
        }

        olmReplacementInFlight.insert(senderCurve)
        let finish: () -> Void = { [weak self] in
            self?.olmReplacementInFlight.remove(senderCurve)
        }

        api.post("/_matrix/client/v3/keys/query",
                 body: ["device_keys": [uid: [String]()]]) { [weak self] json, error in
            guard let self = self else { return }
            guard error == nil,
                  let users = json?["device_keys"] as? [String: Any],
                  let devices = users[uid] as? [String: Any] else {
                finish(); return
            }

            var target: MagnistraOutboundDevice?
            for (did, raw) in devices where did != ownDevice {
                guard var object = raw as? [String: Any],
                      let keys = object["keys"] as? [String: Any],
                      let curve = keys["curve25519:\(did)"] as? String,
                      let ed = keys["ed25519:\(did)"] as? String,
                      curve == senderCurve,
                      let sigs = object["signatures"] as? [String: Any],
                      let byUser = sigs[uid] as? [String: Any],
                      let sigText = byUser["ed25519:\(did)"] as? String,
                      let pub = self.base64Decode(ed), pub.count == 32,
                      let sig = self.base64Decode(sigText), sig.count == 64 else { continue }

                object.removeValue(forKey: "signatures")
                object.removeValue(forKey: "unsigned")
                guard let canonical = self.canonicalJSON(object),
                      self.ed25519Verify(publicKey: pub,
                                         message: Array(canonical.utf8),
                                         signature: sig) else { continue }

                target = MagnistraOutboundDevice(userId: uid, deviceId: did,
                                                  curve25519: curve, ed25519: ed)
                break
            }

            guard let device = target else { finish(); return }

            let claim: [String: Any] = [
                "one_time_keys": [uid: [device.deviceId: "signed_curve25519"]],
                "timeout": 10000
            ]
            api.post("/_matrix/client/v3/keys/claim", body: claim) { [weak self] json, error in
                guard let self = self else { return }
                guard error == nil,
                      let users = json?["one_time_keys"] as? [String: Any],
                      let userMap = users[uid] as? [String: Any],
                      let deviceMap = userMap[device.deviceId] as? [String: Any],
                      let otk = self.verifiedClaimedOTK(deviceMap, device: device),
                      let encrypted = self.makeOlmPreKeyEnvelope(
                        recipient: device, oneTimeKey: otk,
                        payloadType: "m.dummy", payloadContent: [:]) else {
                    finish(); return
                }

                let txn = "magnistra-olm-repair-\(self.nextSendCounter())"
                let body: [String: Any] = [
                    "messages": [uid: [device.deviceId: encrypted]]
                ]
                api.put("/_matrix/client/v3/sendToDevice/m.room.encrypted/\(txn)",
                        body: body) { _, error in
                    if error == nil {
                        var updated = defaults.dictionary(forKey: prefix + "olmReplacementLastMs") ?? [:]
                        updated[senderCurve] = NSNumber(value: now)
                        defaults.set(updated, forKey: prefix + "olmReplacementLastMs")
                        defaults.synchronize()
                        self.runtimeStage = "OLM_REPLACEMENT_DUMMY_SENT"
                        print("[MagnistraE2EE] sent verified replacement Olm m.dummy")
                    }
                    finish()
                }
            }
        }
    }

    func verifiedClaimedOTK(_ map: [String: Any],
                                    device: MagnistraOutboundDevice) -> [UInt8]? {
        for (keyId, raw) in map where keyId.hasPrefix("signed_curve25519:") {
            guard var object = raw as? [String: Any],
                  let keyText = object["key"] as? String,
                  let sigs = object["signatures"] as? [String: Any],
                  let byUser = sigs[device.userId] as? [String: Any],
                  let sigText = byUser["ed25519:\(device.deviceId)"] as? String,
                  let pub = magnistraMediaBase64Decode(device.ed25519, expected: 32),
                  let sig = magnistraMediaBase64Decode(sigText, expected: 64),
                  let key = magnistraMediaBase64Decode(keyText, expected: 32) else {
                continue
            }
            object.removeValue(forKey: "signatures")
            object.removeValue(forKey: "unsigned")
            guard let canonical = canonicalJSON(object),
                  ed25519Verify(publicKey: pub, message: Array(canonical.utf8), signature: sig) else {
                continue
            }
            return key
        }
        return nil
    }

    func makeOlmPreKeyEnvelope(
        recipient: MagnistraOutboundDevice,
        oneTimeKey: [UInt8],
        payloadType: String,
        payloadContent: [String: Any]) -> [String: Any]? {
        guard let uid = userId, let ident = identity,
              let recipientCurve = magnistraMediaBase64Decode(recipient.curve25519, expected: 32),
              let ea = x25519Keygen(),
              let ratchet = x25519Keygen(),
              let s1 = x25519Shared(privateKey: ident.curvePrivate, peerPublic: oneTimeKey),
              let s2 = x25519Shared(privateKey: ea.0, peerPublic: recipientCurve),
              let s3 = x25519Shared(privateKey: ea.0, peerPublic: oneTimeKey),
              let rootAndChain = hkdfSHA256(ikm: s1 + s2 + s3,
                                            info: Array("OLM_ROOT".utf8), count: 64) else {
            return nil
        }
        let root = Array(rootAndChain[0..<32])
        let chain = Array(rootAndChain[32..<64])
        guard let messageKey = hmacSHA256(key: chain, data: [0x01]),
              let keys = hkdfSHA256(ikm: messageKey,
                                    info: Array("OLM_KEYS".utf8), count: 80) else {
            return nil
        }

        let plain: [String: Any] = [
            "type": payloadType,
            "content": payloadContent,
            "sender": uid,
            "recipient": recipient.userId,
            "recipient_keys": ["ed25519": recipient.ed25519],
            "keys": ["ed25519": magnistraMediaBase64(ident.edPublic)]
        ]
        guard MagnistraJSONKit.isValidJSONObject(plain),
              let plainData = try? MagnistraJSONKit.data(withJSONObject: plain, options: []),
              let cipher = aes256CBCEncrypt(key: Array(keys[0..<32]),
                                            iv: Array(keys[64..<80]),
                                            plaintext: [UInt8](plainData)),
              let sidBytes = sha256(ident.curvePublic + ea.1) else {
            return nil
        }

        var normal: [UInt8] = [3]
        normal += outboundWireString(field: 1, value: ratchet.1)
        normal += outboundWireInt(field: 2, value: 0)
        normal += outboundWireString(field: 4, value: cipher)
        guard let mac = hmacSHA256(key: Array(keys[32..<64]), data: normal) else { return nil }
        normal += Array(mac[0..<8])

        var prekey: [UInt8] = [3]
        prekey += outboundWireString(field: 1, value: oneTimeKey)
        prekey += outboundWireString(field: 2, value: ea.1)
        prekey += outboundWireString(field: 3, value: ident.curvePublic)
        prekey += outboundWireString(field: 4, value: normal)

        let state = MagnistraOlmSessionState(
            rootKey: root,
            receiverChain: nil,
            receiverRatchet: nil,
            localRatchetPrivate: ratchet.0,
            localRatchetPublic: ratchet.1,
            oneTimePublic: nil)
        saveOlmInboundSession(magnistraMediaBase64(sidBytes), state: state)

        return [
            "algorithm": olmAlgorithm,
            "sender_key": magnistraMediaBase64(ident.curvePublic),
            "ciphertext": [
                recipient.curve25519: [
                    "type": 0,
                    "body": magnistraMediaBase64(prekey)
                ]
            ]
        ]
    }

    func makeOutboundMegolm(roomId: String) -> MagnistraOutboundMegolm? {
        guard let r = outboundRandomBytes(128),
              let signing = outboundEd25519Keygen() else { return nil }
        return MagnistraOutboundMegolm(
            roomId: roomId,
            index: 0,
            r0: Array(r[0..<32]),
            r1: Array(r[32..<64]),
            r2: Array(r[64..<96]),
            r3: Array(r[96..<128]),
            signingPrivate: signing.0,
            signingPublic: signing.1,
            createdMs: Int64(Date().timeIntervalSince1970 * 1000),
            messageCount: 0,
            sharedFingerprints: Set<String>())
    }

    func outboundRoomKeyContent(_ session: MagnistraOutboundMegolm) -> [String: Any]? {
        var bytes: [UInt8] = [2,
            UInt8((session.index >> 24) & 0xff),
            UInt8((session.index >> 16) & 0xff),
            UInt8((session.index >> 8) & 0xff),
            UInt8(session.index & 0xff)]
        bytes += session.r0 + session.r1 + session.r2 + session.r3 + session.signingPublic
        guard let signature = ed25519Sign(privateKey: session.signingPrivate, message: bytes) else {
            return nil
        }
        bytes += signature
        return [
            "algorithm": megolmAlgorithm,
            "room_id": session.roomId,
            "session_id": session.sessionId,
            "session_key": magnistraMediaBase64(bytes)
        ]
    }

    func encryptOutboundMegolm(
        roomId: String, type: String, content: [String: Any],
        session: inout MagnistraOutboundMegolm) -> [String: Any]? {
        guard let ident = identity, let did = deviceId else { return nil }
        let plain: [String: Any] = ["type": type, "content": content, "room_id": roomId]
        guard MagnistraJSONKit.isValidJSONObject(plain),
              let data = try? MagnistraJSONKit.data(withJSONObject: plain, options: []) else {
            return nil
        }

        let ratchetBytes = session.r0 + session.r1 + session.r2 + session.r3
        guard let keys = hkdfSHA256(ikm: ratchetBytes,
                                    info: Array("MEGOLM_KEYS".utf8), count: 80),
              let cipher = aes256CBCEncrypt(key: Array(keys[0..<32]),
                                            iv: Array(keys[64..<80]),
                                            plaintext: [UInt8](data)) else {
            return nil
        }

        var message: [UInt8] = [3]
        message += outboundWireInt(field: 1, value: UInt64(session.index))
        message += outboundWireString(field: 2, value: cipher)
        guard let mac = hmacSHA256(key: Array(keys[32..<64]), data: message) else { return nil }
        message += Array(mac[0..<8])
        guard let signature = ed25519Sign(privateKey: session.signingPrivate, message: message) else {
            return nil
        }
        message += signature

        let encrypted: [String: Any] = [
            "algorithm": megolmAlgorithm,
            "sender_key": magnistraMediaBase64(ident.curvePublic),
            "device_id": did,
            "session_id": session.sessionId,
            "ciphertext": magnistraMediaBase64(message)
        ]

        guard let next = advanceMegolm((session.r0, session.r1, session.r2, session.r3),
                                       from: session.index) else {
            return nil
        }
        session.index &+= 1
        session.r0 = next.0
        session.r1 = next.1
        session.r2 = next.2
        session.r3 = next.3
        session.messageCount += 1
        return encrypted
    }

    func outboundDeviceFingerprint(_ d: MagnistraOutboundDevice) -> String {
        let bytes = Array((d.userId + "|" + d.deviceId + "|" + d.curve25519).utf8)
        return sha256(bytes).map { magnistraMediaBase64($0) } ?? d.curve25519
    }

    func loadOutboundMegolm(roomId: String) -> MagnistraOutboundMegolm? {
        guard let prefix = storagePrefix(),
              let all = MagnistraPrivateState.shared.object(forKey: prefix + "outboundMegolm") as? [String: String],
              let text = all[roomId] else { return nil }
        let p = text.components(separatedBy: ",")
        guard p.count == 10,
              let index = UInt32(p[0]),
              let r0 = magnistraMediaBase64Decode(p[1], expected: 32),
              let r1 = magnistraMediaBase64Decode(p[2], expected: 32),
              let r2 = magnistraMediaBase64Decode(p[3], expected: 32),
              let r3 = magnistraMediaBase64Decode(p[4], expected: 32),
              let priv = magnistraMediaBase64Decode(p[5], expected: 32),
              let pub = magnistraMediaBase64Decode(p[6], expected: 32),
              let created = Int64(p[7]),
              let count = Int(p[8]) else { return nil }
        let shared = Set(p[9].isEmpty ? [] : p[9].components(separatedBy: ";"))
        return MagnistraOutboundMegolm(roomId: roomId, index: index,
                                        r0: r0, r1: r1, r2: r2, r3: r3,
                                        signingPrivate: priv, signingPublic: pub,
                                        createdMs: created, messageCount: count,
                                        sharedFingerprints: shared)
    }

    func saveOutboundMegolm(_ session: MagnistraOutboundMegolm) {
        guard let prefix = storagePrefix() else { return }
        var all = (MagnistraPrivateState.shared.object(forKey: prefix + "outboundMegolm") as? [String: String]) ?? [:]
        all[session.roomId] = [
            String(session.index),
            magnistraMediaBase64(session.r0),
            magnistraMediaBase64(session.r1),
            magnistraMediaBase64(session.r2),
            magnistraMediaBase64(session.r3),
            magnistraMediaBase64(session.signingPrivate),
            magnistraMediaBase64(session.signingPublic),
            String(session.createdMs),
            String(session.messageCount),
            session.sharedFingerprints.sorted().joined(separator: ";")
        ].joined(separator: ",")
        MagnistraPrivateState.shared.set(all, forKey: prefix + "outboundMegolm")
        MagnistraPrivateState.shared.synchronize()
    }

    func outboundWireVarint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    func outboundWireInt(field: Int, value: UInt64) -> [UInt8] {
        return outboundWireVarint(UInt64(field << 3)) + outboundWireVarint(value)
    }

    func outboundWireString(field: Int, value: [UInt8]) -> [UInt8] {
        return outboundWireVarint(UInt64((field << 3) | 2)) +
               outboundWireVarint(UInt64(value.count)) + value
    }

    func outboundRandomBytes(_ count: Int) -> [UInt8]? {
        guard count > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: count)
        let rc = out.withUnsafeMutableBufferPointer {
            magnistra_crypto_random_bytes($0.baseAddress, $0.count)
        }
        return rc == 1 ? out : nil
    }

    func outboundEd25519Keygen() -> ([UInt8], [UInt8])? {
        var priv = [UInt8](repeating: 0, count: 32)
        var pub = [UInt8](repeating: 0, count: 32)
        let rc = priv.withUnsafeMutableBufferPointer { p in
            pub.withUnsafeMutableBufferPointer { q in
                magnistra_crypto_ed25519_keygen(p.baseAddress, q.baseAddress)
            }
        }
        return rc == 1 ? (priv, pub) : nil
    }

    func aes256CBCEncrypt(key: [UInt8], iv: [UInt8], plaintext: [UInt8]) -> [UInt8]? {
        guard key.count == 32, iv.count == 16 else { return nil }
        var out = [UInt8](repeating: 0, count: plaintext.count + 16)
        var outLen = out.count
        let rc = key.withUnsafeBufferPointer { k in
            iv.withUnsafeBufferPointer { v in
                plaintext.withUnsafeBufferPointer { p in
                    out.withUnsafeMutableBufferPointer { o in
                        magnistra_crypto_aes256_cbc_encrypt(
                            k.baseAddress, v.baseAddress, p.baseAddress, p.count,
                            o.baseAddress, &outLen)
                    }
                }
            }
        }
        guard rc == 1, outLen <= out.count else { return nil }
        return Array(out[0..<outLen])
    }
}