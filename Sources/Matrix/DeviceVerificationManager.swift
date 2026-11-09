// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix device verification: identity bootstrap and verification flow handling.
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



final class DeviceVerificationManager: NSObject, UIAlertViewDelegate {
    static let shared = DeviceVerificationManager()

    var api: MatrixAPIClient?
    private var userId: String?
    private var deviceId: String?
    private var identity: MagnistraDeviceIdentity?
    private var active: MagnistraVerificationTransaction?
    private var pendingEvents: [[String: Any]] = []
    private var bootstrapping = false

    private var bootstrapRetryCount = 0
    private var bootstrapRetryScheduled = false
    private var bootstrapRetryExhausted = false
    private let bootstrapRetryMax = 3
    private let bootstrapRetryDelay: TimeInterval = 5
    private var sendCounter = 0
    private var sasAlert: UIAlertView?

    private var sessionGeneration = 0

    private var verificationReady = false
    private var lastTraceMessage = ""

    private override init() {
        super.init()
    }

    private func trace(_ message: String, alert: Bool = false) {
        lastTraceMessage = message
        print("[MagnistraVerify] verification state updated")
        MagnistraPrivateState.shared.set(message, forKey: "magnistra.verify.lastStatus")
        MagnistraPrivateState.shared.synchronize()
        guard alert else { return }
        DispatchQueue.main.async {
            let a = UIAlertView()
            a.title = "Magnistra verification"
            a.message = message
            a.addButton(withTitle: "OK")
            a.show()
        }
    }

    func resetForLogout() {

        sessionGeneration += 1
        api = nil
        userId = nil
        deviceId = nil
        identity = nil
        active = nil
        pendingEvents.removeAll()
        bootstrapping = false
        bootstrapRetryCount = 0
        bootstrapRetryScheduled = false
        bootstrapRetryExhausted = false
        sendCounter = 0
        sasAlert = nil
        MatrixE2EEManager.shared.resetForLogout()
        print("[MagnistraVerify] verification session state reset for logout")
    }

    func attach(api: MatrixAPIClient) {
        self.api = api
        guard !bootstrapping, !bootstrapRetryScheduled, !bootstrapRetryExhausted, deviceId == nil else { return }
        bootstrap()
    }

    var magnistraCryptoIdentityReady: Bool {
        return api != nil && identity != nil && userId != nil && deviceId != nil
    }

    func handleSync(_ json: [String: Any]) {
        MatrixE2EEManager.shared.handleSync(json)
        guard let toDevice = json["to_device"] as? [String: Any],
              let events = toDevice["events"] as? [[String: Any]], !events.isEmpty else { return }
        if deviceId == nil || identity == nil {
            pendingEvents.append(contentsOf: events)
            if !bootstrapping && !bootstrapRetryScheduled && !bootstrapRetryExhausted { bootstrap() }
            return
        }
        for event in events {
            if let type = event["type"] as? String {
                trace("incoming to-device event: \(type)")
            }
            handleEvent(event)
        }
    }

    private func bootstrap() {
        guard let api = api,
              !bootstrapping,
              !bootstrapRetryScheduled,
              !bootstrapRetryExhausted,
              deviceId == nil else { return }

        let generation = sessionGeneration
        bootstrapping = true
        api.get("/_matrix/client/v3/account/whoami", timeout: 30) { [weak self] json, error in
            guard let self = self, self.sessionGeneration == generation else { return }
            self.bootstrapping = false

            guard error == nil,
                  let json = json,
                  let uid = json["user_id"] as? String,
                  let did = json["device_id"] as? String,
                  !uid.isEmpty, !did.isEmpty else {
                if self.bootstrapRetryCount < self.bootstrapRetryMax {
                    self.bootstrapRetryCount += 1
                    let retryNumber = self.bootstrapRetryCount
                    self.bootstrapRetryScheduled = true
                    self.trace("whoami failed; retry \(retryNumber)/\(self.bootstrapRetryMax) scheduled. error=\(String(describing: error))",
                               alert: false)

                    DispatchQueue.main.asyncAfter(deadline: .now() + self.bootstrapRetryDelay) { [weak self] in
                        guard let self = self, self.sessionGeneration == generation else { return }
                        self.bootstrapRetryScheduled = false
                        guard self.deviceId == nil,
                              !self.bootstrapping,
                              !self.bootstrapRetryExhausted else { return }
                        self.bootstrap()
                    }
                } else {
                    self.bootstrapRetryScheduled = false
                    self.bootstrapRetryExhausted = true
                    self.trace("whoami failed after \(self.bootstrapRetryMax) retries. error=\(String(describing: error)) json=\(String(describing: json))",
                               alert: true)
                }
                return
            }

            self.bootstrapRetryCount = 0
            self.bootstrapRetryScheduled = false
            self.bootstrapRetryExhausted = false

            api.post("/_matrix/client/v3/keys/query",
                     body: ["device_keys": [uid: [did]]]) { [weak self] answer, queryError in
                guard let self = self, self.sessionGeneration == generation else { return }
                guard queryError == nil, let users = answer?["device_keys"] as? [String: Any] else {
                    self.trace("R66: device-key preflight failed; crypto is disabled", alert: true)
                    return
                }
                let own = users[uid] as? [String: Any]
                let published = own?[did] as? [String: Any]
                let already = published != nil
                let stored = MatrixCryptoEngine.shared.hasSnapshot(user: uid, device: did)
                if already && !stored {
                    self.trace("R66: server device has a previous identity. A NEW Matrix device ID is required; no keys overwritten.", alert: true)
                    return
                }
                guard let ident = self.loadOrCreateIdentity(userId: uid, deviceId: did,
                                                             allowNew: !already) else {
                    self.trace("R66: native identity/Keychain unavailable; no device keys uploaded", alert: true)
                    return
                }
                if let published = published,
                   let keys = published["keys"] as? [String: Any],
                   ((keys["ed25519:\(did)"] as? String) != self.base64Encode(ident.edPublic) ||
                    (keys["curve25519:\(did)"] as? String) != self.base64Encode(ident.curvePublic)) {
                    self.trace("R66: published identity differs from native account. Refusing key reset.", alert: true)
                    return
                }
                self.userId = uid
                self.deviceId = did
                self.identity = ident
                MatrixE2EEManager.shared.attach(api: api, userId: uid, deviceId: did, identity: ident)
                self.trace("R66 native identity ready for device \(did)")
                self.uploadDeviceKeys()
                let queued = self.pendingEvents
                self.pendingEvents.removeAll()
                for event in queued { self.handleEvent(event) }
            }
        }
    }

    private func loadOrCreateIdentity(userId: String, deviceId: String,
                                      allowNew: Bool) -> MagnistraDeviceIdentity? {
        guard let keys = MatrixCryptoEngine.shared.open(user: userId, device: deviceId,
                                                               allowNew: allowNew),
              let ed = base64Decode(keys.0), ed.count == 32,
              let curve = base64Decode(keys.1), curve.count == 32 else { return nil }

        return MagnistraDeviceIdentity(edPrivate: [], edPublic: ed,
                                       curvePrivate: [], curvePublic: curve)
    }

    private func uploadDeviceKeys() {
        guard let api = api, let uid = userId, let did = deviceId, let ident = identity else { return }
        let edId = "ed25519:\(did)"
        let curveId = "curve25519:\(did)"
        var device: [String: Any] = [
            "algorithms": ["m.olm.v1.curve25519-aes-sha2", "m.megolm.v1.aes-sha2"],
            "device_id": did,
            "keys": [curveId: base64Encode(ident.curvePublic), edId: base64Encode(ident.edPublic)],
            "user_id": uid
        ]
        guard let canonical = canonicalJSON(device),
              let signature = MatrixCryptoEngine.shared.signBase64(Array(canonical.utf8)) else {
            print("[MagnistraVerify:R66] native device-key signing failed")
            return
        }
        device["signatures"] = [uid: [edId: signature]]
        api.post("/_matrix/client/v3/keys/upload", body: ["device_keys": device]) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error {
                self.trace("/keys/upload failed: \(error) json=\(String(describing: json))", alert: true)
                return
            }
            if let json = json, let errcode = json["errcode"] as? String {
                self.trace("/keys/upload rejected: \(errcode) \(String(describing: json["error"]))", alert: true)
                return
            }
            self.trace("/keys/upload accepted for \(did)")
            let counts = json?["one_time_key_counts"] as? [String: Any]
            let count = (counts?["signed_curve25519"] as? NSNumber)?.intValue ?? 0
            MatrixE2EEManager.shared.ensureOneTimeKeys(serverCount: count)
            self.verifyOwnDeviceKeys()
        }
    }

    func verifyUsingRecoveredSelfSigningKey(
        _ seed: [UInt8],
        completion: @escaping (Bool, String) -> Void
    ) {
        guard seed.count == 32,
              let api = api, let uid = userId, let did = deviceId,
              let ident = identity,
              uid == MagnistraMatrixAccountStore.userId,
              did == MagnistraMatrixAccountStore.deviceId else {
            completion(false, "Device encryption has not initialized. Open a Matrix chat and try again.")
            return
        }
        api.post("/_matrix/client/v3/keys/query",
                 body: ["device_keys": [uid: [did]]]) { [weak self] json, error in
            guard let self = self else { return }
            guard error == nil, let json = json, json["errcode"] == nil,
                  let masters = json["master_keys"] as? [String: Any],
                  let master = masters[uid] as? [String: Any],
                  let masterKeys = master["keys"] as? [String: Any],
                  let masterEntry = masterKeys.first,
                  let masterPubText = masterEntry.value as? String,
                  masterEntry.key == "ed25519:" + masterPubText,
                  let masterPub = self.base64Decode(masterPubText), masterPub.count == 32,
                  let signers = json["self_signing_keys"] as? [String: Any],
                  let signer = signers[uid] as? [String: Any],
                  let signerKeys = signer["keys"] as? [String: Any],
                  let signerEntry = signerKeys.first,
                  let signerPubText = signerEntry.value as? String,
                  signerEntry.key == "ed25519:" + signerPubText,
                  let signerPub = self.base64Decode(signerPubText), signerPub.count == 32,
                  let signerSigs = signer["signatures"] as? [String: Any],
                  let ownerSigs = signerSigs[uid] as? [String: Any],
                  let masterSigText = ownerSigs["ed25519:" + masterPubText] as? String,
                  let masterSig = self.base64Decode(masterSigText), masterSig.count == 64,
                  let allDevices = json["device_keys"] as? [String: Any],
                  let ownDevices = allDevices[uid] as? [String: Any],
                  let device = ownDevices[did] as? [String: Any],
                  let keys = device["keys"] as? [String: Any],
                  let deviceEd = keys["ed25519:" + did] as? String,
                  let deviceCurve = keys["curve25519:" + did] as? String,
                  deviceEd == self.base64Encode(ident.edPublic),
                  deviceCurve == self.base64Encode(ident.curvePublic) else {
                completion(false, "Could not establish the existing device and cross-signing identity.")
                return
            }
            var signerBody = signer
            signerBody.removeValue(forKey: "signatures")
            signerBody.removeValue(forKey: "unsigned")
            guard let signerCanonical = self.canonicalJSON(signerBody),
                  RecoveryCrypto.ed25519Verify(publicKey: masterPub,
                                     message: Array(signerCanonical.utf8),
                                     signature: masterSig) else {
                completion(false, "Self-signing key is not signed by the account master key.")
                return
            }
            var deviceBody = device
            deviceBody.removeValue(forKey: "signatures")
            deviceBody.removeValue(forKey: "unsigned")
            guard let canonical = self.canonicalJSON(deviceBody),
                  let signature = self.ed25519Sign(privateKey: seed,
                                                    message: Array(canonical.utf8)),
                  RecoveryCrypto.ed25519Verify(publicKey: signerPub,
                                     message: Array(canonical.utf8),
                                     signature: signature) else {
                completion(false, "Recovered self-signing key does not match the published Beeper identity.")
                return
            }
            var signedDevice = deviceBody
            var signatures = device["signatures"] as? [String: Any] ?? [:]
            var ownSignatures = signatures[uid] as? [String: Any] ?? [:]
            ownSignatures["ed25519:" + signerPubText] = self.base64Encode(signature)
            signatures[uid] = ownSignatures
            signedDevice["signatures"] = signatures
            let payload: [String: Any] = [uid: [did: signedDevice]]
            api.post("/_matrix/client/v3/keys/signatures/upload", body: payload) {
                [weak self] response, uploadError in
                guard let self = self else { return }
                guard uploadError == nil,
                      let response = response,
                      response["errcode"] == nil,
                      (response["failures"] as? [String: Any] ?? [:]).isEmpty else {
                    completion(false, "Beeper rejected the device signature upload.")
                    return
                }

                api.post("/_matrix/client/v3/keys/query",
                         body: ["device_keys": [uid: [did]]]) { [weak self] check, checkError in
                    guard let self = self else { return }
                    guard checkError == nil, let check = check,
                          let checkUsers = check["device_keys"] as? [String: Any],
                          let checkDevices = checkUsers[uid] as? [String: Any],
                          let checkDevice = checkDevices[did] as? [String: Any],
                          let checkSigs = checkDevice["signatures"] as? [String: Any],
                          let checkUserSigs = checkSigs[uid] as? [String: Any],
                          let stored = checkUserSigs["ed25519:" + signerPubText] as? String,
                          let storedBytes = self.base64Decode(stored), storedBytes.count == 64,
                          RecoveryCrypto.ed25519Verify(publicKey: signerPub,
                                             message: Array(canonical.utf8),
                                             signature: storedBytes) else {
                        completion(false, "Signature submitted, but its device trust status could not be verified.")
                        return
                    }
                    completion(true, "Device signed with the existing Beeper cross-signing identity.")
                }
            }
        }
    }

    private func verifyOwnDeviceKeys() {
        guard let api = api, let uid = userId, let did = deviceId, let ident = identity else { return }
        let body: [String: Any] = ["device_keys": [uid: [did]]]
        api.post("/_matrix/client/v3/keys/query", body: body) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error {
                self.trace("/keys/query self failed: \(error) json=\(String(describing: json))", alert: true)
                return
            }
            if let json = json, let errcode = json["errcode"] as? String {
                self.trace("/keys/query self rejected: \(errcode) \(String(describing: json["error"]))", alert: true)
                return
            }
            guard let json = json,
                  let users = json["device_keys"] as? [String: Any],
                  let devices = users[uid] as? [String: Any],
                  let device = devices[did] as? [String: Any],
                  let keys = device["keys"] as? [String: Any],
                  let ed = keys["ed25519:\(did)"] as? String,
                  let curve = keys["curve25519:\(did)"] as? String else {
                self.trace("homeserver returned no verification keys for device \(did): \(String(describing: json))", alert: true)
                return
            }
            let localEd = self.base64Encode(ident.edPublic)
            let localCurve = self.base64Encode(ident.curvePublic)
            guard ed == localEd, curve == localCurve else {
                self.trace("homeserver key mismatch for device \(did)", alert: true)
                return
            }
            self.verificationReady = true
            self.trace("READY: device \(did) keys are registered on the homeserver. Now press Verify on the modern Element device.", alert: false)
        }
    }

    private func handleEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String,
              let sender = event["sender"] as? String,
              let content = event["content"] as? [String: Any],
              userId != nil, !sender.isEmpty else { return }

        switch type {
        case "m.key.verification.request": handleRequest(sender: sender, content: content)
        case "m.key.verification.start": handleStart(sender: sender, content: content)
        case "m.key.verification.key": handleKey(sender: sender, content: content)
        case "m.key.verification.mac": handleMac(sender: sender, content: content)
        case "m.key.verification.cancel":
            if let tx = active, transactionId(content) == tx.id { finishAndClear(message: "Verification cancelled") }
        case "m.key.verification.done":
            if let tx = active, transactionId(content) == tx.id { finishAndClear(message: "Verification complete") }
        default: break
        }
    }

    private func transactionId(_ content: [String: Any]) -> String? {
        return content["transaction_id"] as? String
    }

    private func handleRequest(sender: String, content: [String: Any]) {
        guard let txid = transactionId(content),
              let remoteDevice = content["from_device"] as? String,
              stringArray(content["methods"]).contains("m.sas.v1") else { return }
        if let old = active, old.id != txid {
            sendCancel(old, code: "m.user", reason: "Another verification is active")
        }
        let tx = MagnistraVerificationTransaction(id: txid, remoteUser: sender, remoteDevice: remoteDevice)
        active = tx
        trace("verification request received from device \(remoteDevice), tx=\(txid)", alert: true)
        queryRemoteDeviceKey(tx)
        guard let did = deviceId else { return }
        send(type: "m.key.verification.ready", toUser: sender, toDevice: remoteDevice,
             content: ["from_device": did, "methods": ["m.sas.v1"], "transaction_id": txid])
        print("[MagnistraVerify] verification ready sent")
    }

    private func handleStart(sender: String, content: [String: Any]) {
        guard let txid = transactionId(content),
              let remoteDevice = content["from_device"] as? String,
              (content["method"] as? String) == "m.sas.v1" else { return }
        let tx: MagnistraVerificationTransaction
        if let current = active, current.id == txid &&
           current.remoteUser == sender && current.remoteDevice == remoteDevice {
            tx = current
        } else {
            tx = MagnistraVerificationTransaction(id: txid, remoteUser: sender, remoteDevice: remoteDevice)
            active = tx
            queryRemoteDeviceKey(tx)
        }

        guard stringArray(content["key_agreement_protocols"]).contains("curve25519-hkdf-sha256"),
              stringArray(content["hashes"]).contains("sha256"),
              stringArray(content["message_authentication_codes"]).contains("hkdf-hmac-sha256.v2"),
              stringArray(content["short_authentication_string"]).contains("decimal") else {
            sendCancel(tx, code: "m.unknown_method", reason: "No compatible SAS method")
            active = nil
            return
        }
        guard let eph = x25519Keygen() else {
            sendCancel(tx, code: "m.unexpected_message", reason: "Unable to create verification key")
            active = nil
            return
        }
        tx.startContent = content
        tx.ephemeralPrivate = eph.0
        tx.ephemeralPublic = eph.1
        tx.ephemeralPublicB64 = base64Encode(eph.1)
        guard let canonical = canonicalJSON(content),
              let digest = sha256(Array((tx.ephemeralPublicB64 + canonical).utf8)) else {
            sendCancel(tx, code: "m.unexpected_message", reason: "Unable to create commitment")
            active = nil
            return
        }
        send(type: "m.key.verification.accept", toUser: sender, toDevice: tx.remoteDevice,
             content: [
                "commitment": base64Encode(digest),
                "hash": "sha256",
                "key_agreement_protocol": "curve25519-hkdf-sha256",
                "message_authentication_code": "hkdf-hmac-sha256.v2",
                "short_authentication_string": ["decimal"],
                "transaction_id": tx.id
             ])
        print("[MagnistraVerify] SAS start accepted")
    }

    private func handleKey(sender: String, content: [String: Any]) {
        guard let tx = active, tx.remoteUser == sender,
              transactionId(content) == tx.id,
              let remoteKey = content["key"] as? String,
              let remoteBytes = base64Decode(remoteKey), remoteBytes.count == 32,
              !tx.ephemeralPrivate.isEmpty,
              let shared = x25519Shared(privateKey: tx.ephemeralPrivate, peerPublic: remoteBytes) else { return }
        tx.remoteEphemeralB64 = remoteKey
        tx.sharedSecret = shared
        send(type: "m.key.verification.key", toUser: tx.remoteUser, toDevice: tx.remoteDevice,
             content: ["key": tx.ephemeralPublicB64, "transaction_id": tx.id])
        showSAS(tx)
    }

    private func showSAS(_ tx: MagnistraVerificationTransaction) {
        guard sasAlert == nil,
              let uid = userId, let did = deviceId,
              let remotePub = tx.remoteEphemeralB64,
              let shared = tx.sharedSecret else { return }
        let info = "MATRIX_KEY_VERIFICATION_SAS|\(tx.remoteUser)|\(tx.remoteDevice)|\(remotePub)|\(uid)|\(did)|\(tx.ephemeralPublicB64)|\(tx.id)"
        guard let bytes = hkdfSHA256(ikm: shared, info: Array(info.utf8), count: 5), bytes.count == 5 else { return }
        let a = (Int(bytes[0]) << 5 | Int(bytes[1]) >> 3) + 1000
        let b = ((Int(bytes[1]) & 0x07) << 10 | Int(bytes[2]) << 2 | Int(bytes[3]) >> 6) + 1000
        let c = ((Int(bytes[3]) & 0x3F) << 7 | Int(bytes[4]) >> 1) + 1000
        let alert = UIAlertView()
        alert.title = "Verify session"
        alert.message = "Compare these numbers on both devices:\n\n\(a)   \(b)   \(c)"
        alert.delegate = self
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "They match")
        alert.cancelButtonIndex = 0
        sasAlert = alert
        alert.show()
    }

    func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        guard alertView === sasAlert, let tx = active else { return }
        sasAlert = nil
        if buttonIndex == 1 {
            tx.localConfirmed = true
            sendLocalMac(tx)
            maybeComplete(tx)
        } else {
            sendCancel(tx, code: "m.user", reason: "User cancelled")
            active = nil
        }
    }

    private func sendLocalMac(_ tx: MagnistraVerificationTransaction) {
        guard !tx.localMacSent,
              let uid = userId, let did = deviceId,
              let ident = identity, let shared = tx.sharedSecret else { return }
        let keyId = "ed25519:\(did)"
        let pub = base64Encode(ident.edPublic)
        guard let mac = verificationMac(shared: shared,
                                        senderUser: uid, senderDevice: did,
                                        recipientUser: tx.remoteUser, recipientDevice: tx.remoteDevice,
                                        transaction: tx.id, keyId: keyId, value: pub),
              let keysMac = verificationMac(shared: shared,
                                            senderUser: uid, senderDevice: did,
                                            recipientUser: tx.remoteUser, recipientDevice: tx.remoteDevice,
                                            transaction: tx.id, keyId: "KEY_IDS", value: keyId) else { return }
        tx.localMacSent = true
        send(type: "m.key.verification.mac", toUser: tx.remoteUser, toDevice: tx.remoteDevice,
             content: ["keys": keysMac, "mac": [keyId: mac], "transaction_id": tx.id])
    }

    private func handleMac(sender: String, content: [String: Any]) {
        guard let tx = active, tx.remoteUser == sender, transactionId(content) == tx.id else { return }
        tx.pendingRemoteMac = content
        verifyPendingRemoteMac(tx)
    }

    private func verifyPendingRemoteMac(_ tx: MagnistraVerificationTransaction) {
        guard let content = tx.pendingRemoteMac,
              let remoteEd = tx.remoteEd25519,
              let uid = userId, let did = deviceId,
              let shared = tx.sharedSecret,
              let macAny = content["mac"] as? [String: Any],
              let keysMac = content["keys"] as? String else { return }
        let ids = macAny.keys.sorted()
        let joined = ids.joined(separator: ",")
        guard let expectedKeys = verificationMac(shared: shared,
                                                  senderUser: tx.remoteUser, senderDevice: tx.remoteDevice,
                                                  recipientUser: uid, recipientDevice: did,
                                                  transaction: tx.id, keyId: "KEY_IDS", value: joined),
              secureEqual(expectedKeys, keysMac) else {
            sendCancel(tx, code: "m.key_mismatch", reason: "Verification key list mismatch")
            active = nil
            return
        }
        let remoteKeyId = "ed25519:\(tx.remoteDevice)"
        guard let actual = macAny[remoteKeyId] as? String,
              let expected = verificationMac(shared: shared,
                                             senderUser: tx.remoteUser, senderDevice: tx.remoteDevice,
                                             recipientUser: uid, recipientDevice: did,
                                             transaction: tx.id, keyId: remoteKeyId, value: remoteEd),
              secureEqual(expected, actual) else {
            sendCancel(tx, code: "m.key_mismatch", reason: "Device fingerprint mismatch")
            active = nil
            return
        }
        tx.pendingRemoteMac = nil
        tx.remoteMacVerified = true
        maybeComplete(tx)
    }

    private func maybeComplete(_ tx: MagnistraVerificationTransaction) {
        guard active === tx, tx.localConfirmed, tx.localMacSent, tx.remoteMacVerified, !tx.doneSent else { return }
        tx.doneSent = true
        send(type: "m.key.verification.done", toUser: tx.remoteUser, toDevice: tx.remoteDevice,
             content: ["transaction_id": tx.id])
        finishAndClear(message: "Session verified")
    }

    private func finishAndClear(message: String) {
        print("[MagnistraVerify] verification completed")
        active = nil
        sasAlert = nil
    }

    private func sendCancel(_ tx: MagnistraVerificationTransaction, code: String, reason: String) {
        send(type: "m.key.verification.cancel", toUser: tx.remoteUser, toDevice: tx.remoteDevice,
             content: ["code": code, "reason": reason, "transaction_id": tx.id])
    }

    private func r66VerifyDeviceSignature(pub: [UInt8], signature: [UInt8],
                                           message: [UInt8]) -> Bool {
        guard pub.count == 32 && signature.count == 64 else { return false }
        return pub.withUnsafeBufferPointer { p in message.withUnsafeBufferPointer { m in
            signature.withUnsafeBufferPointer { sig in
                magnistra_crypto_ed25519_verify(p.baseAddress, m.baseAddress,
                                                m.count, sig.baseAddress)
            }
        }} == 1
    }

    private func queryRemoteDeviceKey(_ tx: MagnistraVerificationTransaction) {
        guard let api = api else { return }
        let body: [String: Any] = ["device_keys": [tx.remoteUser: [tx.remoteDevice]]]
        api.post("/_matrix/client/v3/keys/query", body: body) { [weak self, weak tx] json, _ in
            guard let self = self, let tx = tx,
                  let json = json,
                  let users = json["device_keys"] as? [String: Any],
                  let devices = users[tx.remoteUser] as? [String: Any],
                  let device = devices[tx.remoteDevice] as? [String: Any],
                  let keys = device["keys"] as? [String: Any],
                  let ed = keys["ed25519:\(tx.remoteDevice)"] as? String,
                  let sigs = device["signatures"] as? [String: Any],
                  let byUser = sigs[tx.remoteUser] as? [String: Any],
                  let sigText = byUser["ed25519:\(tx.remoteDevice)"] as? String,
                  let pub = self.base64Decode(ed), pub.count == 32,
                  let signature = self.base64Decode(sigText), signature.count == 64 else { return }
            var signed = device
            signed.removeValue(forKey: "signatures")
            signed.removeValue(forKey: "unsigned")
            guard let canonical = self.canonicalJSON(signed),
                  self.r66VerifyDeviceSignature(pub: pub, signature: signature,
                                                message: Array(canonical.utf8)) else { return }
            tx.remoteEd25519 = ed
            self.verifyPendingRemoteMac(tx)
        }
    }

    private func send(type: String, toUser: String, toDevice: String, content: [String: Any]) {
        guard let api = api else { return }
        sendCounter += 1
        let txn = "magnistra-\(Int(Date().timeIntervalSince1970 * 1000))-\(sendCounter)"
        let body: [String: Any] = ["messages": [toUser: [toDevice: content]]]
        api.put("/_matrix/client/v3/sendToDevice/\(type)/\(txn)", body: body) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error {
                self.trace("sendToDevice \(type) failed: \(error) json=\(String(describing: json))", alert: true)
            } else if let json = json, let errcode = json["errcode"] as? String {
                self.trace("sendToDevice \(type) rejected: \(errcode) \(String(describing: json["error"]))", alert: true)
            } else {
                self.trace("sendToDevice \(type) accepted")
            }
        }
    }

    private func verificationMac(shared: [UInt8], senderUser: String, senderDevice: String,
                                 recipientUser: String, recipientDevice: String,
                                 transaction: String, keyId: String, value: String) -> String? {
        let info = "MATRIX_KEY_VERIFICATION_MAC\(senderUser)\(senderDevice)\(recipientUser)\(recipientDevice)\(transaction)\(keyId)"
        guard let key = hkdfSHA256(ikm: shared, info: Array(info.utf8), count: 32),
              let mac = hmacSHA256(key: key, data: Array(value.utf8)) else { return nil }
        return base64Encode(mac)
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let a = value as? [String] { return a }
        if let a = value as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private func secureEqual(_ a: String, _ b: String) -> Bool {
        let aa = Array(a.utf8), bb = Array(b.utf8)
        guard aa.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aa.count { diff |= aa[i] ^ bb[i] }
        return diff == 0
    }

    private func canonicalJSON(_ value: Any) -> String? {
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

    private func jsonEscape(_ s: String) -> String {
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

    private let b64Table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    private func base64Encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let b0 = Int(bytes[i]); i += 1
            let have1 = i < bytes.count
            let b1 = have1 ? Int(bytes[i]) : 0
            if have1 { i += 1 }
            let have2 = i < bytes.count
            let b2 = have2 ? Int(bytes[i]) : 0
            if have2 { i += 1 }
            out.append(b64Table[(b0 >> 2) & 63])
            out.append(b64Table[((b0 & 3) << 4) | ((b1 >> 4) & 15)])
            if have1 { out.append(b64Table[((b1 & 15) << 2) | ((b2 >> 6) & 3)]) }
            if have2 { out.append(b64Table[b2 & 63]) }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private func base64Decode(_ string: String) -> [UInt8]? {
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
        var out: [UInt8] = []
        var i = 0
        while i < vals.count {
            let a = vals[i]; i += 1
            guard i < vals.count else { return nil }
            let b = vals[i]; i += 1
            out.append((a << 2) | (b >> 4))
            if i < vals.count {
                let c = vals[i]; i += 1
                out.append((b << 4) | (c >> 2))
                if i < vals.count {
                    let d = vals[i]; i += 1
                    out.append((c << 6) | d)
                }
            }
        }
        return out
    }

    private func ed25519Keygen() -> ([UInt8], [UInt8])? {
        var priv = [UInt8](repeating: 0, count: 32)
        var pub = [UInt8](repeating: 0, count: 32)
        let rc = priv.withUnsafeMutableBufferPointer { p in
            pub.withUnsafeMutableBufferPointer { q in
                magnistra_crypto_ed25519_keygen(p.baseAddress, q.baseAddress)
            }
        }
        return rc == 1 ? (priv, pub) : nil
    }

    private func x25519Keygen() -> ([UInt8], [UInt8])? {
        var priv = [UInt8](repeating: 0, count: 32)
        var pub = [UInt8](repeating: 0, count: 32)
        let rc = priv.withUnsafeMutableBufferPointer { p in
            pub.withUnsafeMutableBufferPointer { q in
                magnistra_crypto_x25519_keygen(p.baseAddress, q.baseAddress)
            }
        }
        return rc == 1 ? (priv, pub) : nil
    }

    private func ed25519Sign(privateKey: [UInt8], message: [UInt8]) -> [UInt8]? {
        var sig = [UInt8](repeating: 0, count: 64)
        let rc = privateKey.withUnsafeBufferPointer { p in
            message.withUnsafeBufferPointer { m in
                sig.withUnsafeMutableBufferPointer { s in
                    magnistra_crypto_ed25519_sign(p.baseAddress, m.baseAddress, m.count, s.baseAddress)
                }
            }
        }
        return rc == 1 ? sig : nil
    }

    private func x25519Shared(privateKey: [UInt8], peerPublic: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = privateKey.withUnsafeBufferPointer { p in
            peerPublic.withUnsafeBufferPointer { q in
                out.withUnsafeMutableBufferPointer { o in
                    magnistra_crypto_x25519_shared(p.baseAddress, q.baseAddress, o.baseAddress)
                }
            }
        }
        return rc == 1 ? out : nil
    }

    private func sha256(_ data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = data.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                magnistra_crypto_sha256(p.baseAddress, p.count, o.baseAddress)
            }
        }
        return rc == 1 ? out : nil
    }

    private func hkdfSHA256(ikm: [UInt8], info: [UInt8], count: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: count)
        let rc = ikm.withUnsafeBufferPointer { p in
            info.withUnsafeBufferPointer { i in
                out.withUnsafeMutableBufferPointer { o in
                    magnistra_crypto_hkdf_sha256(p.baseAddress, p.count, i.baseAddress, i.count, o.baseAddress, o.count)
                }
            }
        }
        return rc == 1 ? out : nil
    }

    private func hmacSHA256(key: [UInt8], data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = key.withUnsafeBufferPointer { k in
            data.withUnsafeBufferPointer { d in
                out.withUnsafeMutableBufferPointer { o in
                    magnistra_crypto_hmac_sha256(k.baseAddress, k.count, d.baseAddress, d.count, o.baseAddress)
                }
            }
        }
        return rc == 1 ? out : nil
    }
}