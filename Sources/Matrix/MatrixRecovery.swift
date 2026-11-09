// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Key recovery: Megolm session store and recovery key encoding (Base58/Base64).
import Foundation
import UIKit

struct MagnistraMegolmSession {
    let sessionId: String
    let roomId: String
    let senderKey: String
    let firstKnownIndex: Int
    let ratchet: [UInt8]
    let signingKey: [UInt8]
}

final class MagnistraMegolmKeyStore {

    static let shared = MagnistraMegolmKeyStore()

    private static let version = 1

    private let path: String
    private let queue = DispatchQueue(label: "com.magnistra.megolmkeys")
    private var sessions: [String: MagnistraMegolmSession] = [:]

    private init() {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        path = (documents as NSString).appendingPathComponent("magnistra-megolm-keys.json")
        load()
    }

    var count: Int { return sessions.count }

    static var onKeysRestored: (() -> Void)?

    func session(id: String) -> MagnistraMegolmSession? { return sessions[id] }

    @discardableResult
    func merge(_ incoming: [MagnistraMegolmSession]) -> Int {
        var added = 0
        var changed = false
        for session in incoming {
            if let existing = sessions[session.sessionId],
               existing.firstKnownIndex <= session.firstKnownIndex { continue }
            if sessions[session.sessionId] == nil { added += 1 }
            sessions[session.sessionId] = session

            changed = true
        }
        if changed {
            write()
            MagnistraMegolmKeyStore.onKeysRestored?()
        }
        return added
    }

    func discard() {
        sessions = [:]
        let path = self.path
        queue.async { MagnistraPrivateState.shared.deleteMegolm(legacyPath: path) }
    }

    private func load() {

        guard let data = MagnistraPrivateState.shared.megolmContents(legacyPath: path),
              let json = (try? MagnistraJSONKit.jsonObject(with: data, options: [])) as? [String: Any],
              (json["version"] as? NSNumber)?.intValue == MagnistraMegolmKeyStore.version,
              json["userId"] as? String == MagnistraMatrixAccountStore.userId,
              let raw = json["sessions"] as? [[String: Any]] else { return }
        for entry in raw {
            guard let session = MagnistraMegolmKeyStore.decode(entry) else { continue }
            sessions[session.sessionId] = session
        }
    }

    private func write() {
        guard let userId = MagnistraMatrixAccountStore.userId else { return }
        let json: [String: Any] = ["version": MagnistraMegolmKeyStore.version,
                                   "userId": userId,
                                   "sessions": sessions.values.map { MagnistraMegolmKeyStore.encode($0) }]
        guard let data = try? MagnistraJSONKit.data(withJSONObject: json, options: []) else { return }
        let path = self.path
        queue.async {

            _ = MagnistraPrivateState.shared.saveMegolm(data, legacyPath: path)
        }
    }

    private static func encode(_ session: MagnistraMegolmSession) -> [String: Any] {
        return ["id": session.sessionId,
                "room": session.roomId,
                "sender": session.senderKey,
                "index": session.firstKnownIndex,
                "ratchet": MagnistraRecoveryBase64.encode(session.ratchet),
                "signing": MagnistraRecoveryBase64.encode(session.signingKey)]
    }

    private static func decode(_ d: [String: Any]) -> MagnistraMegolmSession? {
        guard let id = d["id"] as? String, !id.isEmpty,
              let ratchetText = d["ratchet"] as? String,
              let ratchet = MagnistraRecoveryBase64.decode(ratchetText), ratchet.count == 128,
              let signingText = d["signing"] as? String,
              let signing = MagnistraRecoveryBase64.decode(signingText), signing.count == 32 else { return nil }
        return MagnistraMegolmSession(sessionId: id,
                             roomId: d["room"] as? String ?? "",
                             senderKey: d["sender"] as? String ?? "",
                             firstKnownIndex: (d["index"] as? NSNumber)?.intValue ?? 0,
                             ratchet: ratchet,
                             signingKey: signing)
    }
}

enum MagnistraRecoveryBase64 {

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    private static let reverse: [Int8] = {
        var table = [Int8](repeating: -2, count: 256)
        for (index, byte) in alphabet.enumerated() { table[Int(byte)] = Int8(index) }
        for byte in Array("=\r\n\t ".utf8) { table[Int(byte)] = -1 }
        return table
    }()

    static func decode(_ text: String) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count * 3 / 4)
        var accumulator = 0
        var bits = 0
        for byte in text.utf8 {
            let value = reverse[Int(byte)]
            if value == -1 { continue }
            if value < 0 { return nil }
            accumulator = (accumulator << 6) | Int(value)
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((accumulator >> bits) & 0xFF))
            }
        }

        if bits >= 8 { return nil }
        if bits > 0 && (accumulator & ((1 << bits) - 1)) != 0 { return nil }
        return out
    }

    static func encode(_ bytes: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity((bytes.count + 2) / 3 * 4)
        var index = 0
        while index < bytes.count {
            let remaining = bytes.count - index
            let b0 = Int(bytes[index])
            let b1 = remaining > 1 ? Int(bytes[index + 1]) : 0
            let b2 = remaining > 2 ? Int(bytes[index + 2]) : 0
            out.unicodeScalars.append(UnicodeScalar(alphabet[b0 >> 2]))
            out.unicodeScalars.append(UnicodeScalar(alphabet[((b0 & 0x03) << 4) | (b1 >> 4)]))
            if remaining > 1 {
                out.unicodeScalars.append(UnicodeScalar(alphabet[((b1 & 0x0F) << 2) | (b2 >> 6)]))
            }
            if remaining > 2 {
                out.unicodeScalars.append(UnicodeScalar(alphabet[b2 & 0x3F]))
            }
            index += 3
        }
        return out
    }
}

enum MagnistraRecoveryBase58 {

    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    private static let reverse: [Int8] = {
        var table = [Int8](repeating: -1, count: 256)
        for (index, byte) in alphabet.enumerated() { table[Int(byte)] = Int8(index) }
        return table
    }()

    static func decode(_ text: String) -> [UInt8]? {
        var digits: [UInt8] = [0]
        var leadingZeroes = 0
        var seenNonZero = false
        for byte in text.utf8 {
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { continue }
            let value = reverse[Int(byte)]
            if value < 0 { return nil }
            if value == 0 && !seenNonZero {
                leadingZeroes += 1
                continue
            }
            seenNonZero = true

            var carry = Int(value)
            var index = digits.count - 1
            while index >= 0 {
                carry += Int(digits[index]) * 58
                digits[index] = UInt8(carry & 0xFF)
                carry >>= 8
                index -= 1
            }
            while carry > 0 {
                digits.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }
        if !seenNonZero && leadingZeroes == 0 { return nil }

        while digits.count > 1 && digits[0] == 0 { digits.removeFirst() }
        if !seenNonZero { digits = [] }
        return [UInt8](repeating: 0, count: leadingZeroes) + digits
    }
}

enum RecoveryCrypto {

    static func sha256(_ data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = data.withUnsafeBufferPointer { input in
            magnistra_recovery_crypto_sha256(input.baseAddress, data.count, &out)
        }
        return rc == 0 ? out : nil
    }

    static func hmacSHA256(key: [UInt8], data: [UInt8]) -> [UInt8]? {
        guard !key.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let rc = key.withUnsafeBufferPointer { k in
            data.withUnsafeBufferPointer { d in
                magnistra_recovery_crypto_hmac_sha256(k.baseAddress, key.count, d.baseAddress, data.count, &out)
            }
        }
        return rc == 0 ? out : nil
    }

    static func hkdfSHA256(ikm: [UInt8], salt: [UInt8], info: [UInt8], length: Int) -> [UInt8]? {
        guard !ikm.isEmpty, length > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: length)
        let rc = ikm.withUnsafeBufferPointer { i in
            salt.withUnsafeBufferPointer { s in
                info.withUnsafeBufferPointer { n in
                    magnistra_recovery_crypto_hkdf_sha256(i.baseAddress, ikm.count,
                                       s.baseAddress, salt.count,
                                       n.baseAddress, info.count,
                                       &out, length)
                }
            }
        }
        return rc == 0 ? out : nil
    }

    static func aes256CTR(key: [UInt8], iv: [UInt8], data: [UInt8]) -> [UInt8]? {
        guard key.count == 32, iv.count == 16, !data.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: data.count)
        let rc = key.withUnsafeBufferPointer { k in
            iv.withUnsafeBufferPointer { v in
                data.withUnsafeBufferPointer { d in
                    magnistra_recovery_crypto_aes256_ctr(k.baseAddress, v.baseAddress, d.baseAddress, data.count, &out)
                }
            }
        }
        return rc == 0 ? out : nil
    }

    static func aes256CBCDecrypt(key: [UInt8], iv: [UInt8], data: [UInt8]) -> [UInt8]? {
        guard key.count == 32, iv.count == 16, !data.isEmpty, data.count % 16 == 0 else { return nil }
        var out = [UInt8](repeating: 0, count: data.count)
        var written = 0
        let rc = key.withUnsafeBufferPointer { k in
            iv.withUnsafeBufferPointer { v in
                data.withUnsafeBufferPointer { d in
                    magnistra_recovery_crypto_aes256_cbc_decrypt(k.baseAddress, v.baseAddress,
                                              d.baseAddress, data.count,
                                              &out, &written)
                }
            }
        }
        guard rc == 0, written <= out.count else { return nil }
        return Array(out[0..<written])
    }

    static func x25519(privateKey: [UInt8], peerPublicKey: [UInt8]) -> [UInt8]? {
        guard privateKey.count == 32, peerPublicKey.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let rc = privateKey.withUnsafeBufferPointer { p in
            peerPublicKey.withUnsafeBufferPointer { q in
                magnistra_recovery_crypto_x25519(p.baseAddress, q.baseAddress, &out)
            }
        }
        return rc == 0 ? out : nil
    }

    static func x25519PublicKey(privateKey: [UInt8]) -> [UInt8]? {
        guard privateKey.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let rc = privateKey.withUnsafeBufferPointer { p in
            magnistra_recovery_crypto_x25519_public(p.baseAddress, &out)
        }
        return rc == 0 ? out : nil
    }

    static func ed25519Verify(publicKey: [UInt8], message: [UInt8], signature: [UInt8]) -> Bool {
        guard publicKey.count == 32, signature.count == 64 else { return false }
        let rc = publicKey.withUnsafeBufferPointer { p in
            message.withUnsafeBufferPointer { m in
                signature.withUnsafeBufferPointer { s in
                    magnistra_recovery_crypto_ed25519_verify(p.baseAddress, m.baseAddress, message.count, s.baseAddress)
                }
            }
        }
        return rc == 0
    }
}

enum MagnistraRecoveryKey {

    private static let prefix: [UInt8] = [0x8B, 0x01]

    static func decode(_ text: String) -> [UInt8]? {
        guard let bytes = MagnistraRecoveryBase58.decode(text), bytes.count == 35 else { return nil }
        guard bytes[0] == prefix[0], bytes[1] == prefix[1] else { return nil }
        var parity: UInt8 = 0
        for byte in bytes { parity ^= byte }
        guard parity == 0 else { return nil }
        return Array(bytes[2..<34])
    }
}

enum MagnistraMegolmRatchet {

    private static func rehash(_ parts: inout [UInt8], from: Int, to: Int) -> Bool {

        let key = Array(parts[(from * 32)..<(from * 32 + 32)])
        guard let out = RecoveryCrypto.hmacSHA256(key: key, data: [UInt8(to)]) else { return false }
        for i in 0..<32 { parts[to * 32 + i] = out[i] }
        return true
    }

    static func advance(_ ratchet: [UInt8], from: Int, to: Int) -> [UInt8]? {
        guard ratchet.count == 128, from >= 0, to >= from else { return nil }
        if to == from { return ratchet }
        var parts = ratchet
        var counter = UInt32(truncatingIfNeeded: from)
        let target = UInt32(truncatingIfNeeded: to)
        for j in 0..<4 {
            let shift = UInt32((3 - j) * 8)
            var steps = ((target >> shift) &- (counter >> shift)) & 0xFF
            if steps == 0 { continue }

            while steps > 1 {
                guard rehash(&parts, from: j, to: j) else { return nil }
                steps -= 1
            }

            var k = 3
            while k >= j {
                guard rehash(&parts, from: j, to: k) else { return nil }
                k -= 1
            }
            counter = target & (~UInt32(0) << shift)
        }
        return parts
    }
}

final class MagnistraMatrixDecryptor {

    static let shared = MagnistraMatrixDecryptor()

    enum Outcome {
        case decrypted([String: Any])
        case locked
        case noKey
        case failed(String)
    }

    private static let maxCachedPlaintexts = 600
    private static let maxCachedRatchets = 200

    private var plaintexts: [String: [String: Any]] = [:]
    private var ratchets: [String: [UInt8]] = [:]

    private init() {}

    func reset() {
        plaintexts.removeAll()
        ratchets.removeAll()
    }

    func decrypt(eventId: String, content: [String: Any]) -> Outcome {
        if let cached = plaintexts[eventId] { return .decrypted(cached) }

        guard content["algorithm"] as? String == "m.megolm.v1.aes-sha2",
              let sessionId = content["session_id"] as? String,
              let cipherText = content["ciphertext"] as? String else {
            return .failed("unsupported encryption")
        }

        guard let session = MagnistraMegolmKeyStore.shared.session(id: sessionId) else {
            return MagnistraMegolmKeyStore.shared.count == 0 ? .locked : .noKey
        }
        guard let raw = MagnistraRecoveryBase64.decode(cipherText),
              let message = MagnistraMatrixDecryptor.parseMessage(raw) else {
            return .failed("malformed message")
        }

        guard message.index >= session.firstKnownIndex else { return .noKey }

        guard let ratchet = self.ratchet(for: session, at: message.index),
              let derived = RecoveryCrypto.hkdfSHA256(ikm: ratchet,
                                              salt: [UInt8](repeating: 0, count: 32),
                                              info: Array("MEGOLM_KEYS".utf8),
                                              length: 80) else {
            return .failed("key derivation failed")
        }

        guard let mac = RecoveryCrypto.hmacSHA256(key: Array(derived[32..<64]), data: message.macBody),
              Array(mac[0..<8]) == message.mac else {
            return .failed("MAC mismatch")
        }
        guard let plain = RecoveryCrypto.aes256CBCDecrypt(key: Array(derived[0..<32]),
                                                  iv: Array(derived[64..<80]),
                                                  data: message.ciphertext) else {
            return .failed("could not decrypt")
        }
        guard let json = (try? MagnistraJSONKit.jsonObject(with: Data(plain),
                                                            options: [])) as? [String: Any],
              let type = json["type"] as? String, !type.isEmpty else {
            return .failed("decrypted data is not an event")
        }

        guard RecoveryCrypto.ed25519Verify(publicKey: session.signingKey,
                                   message: message.signedBody,
                                   signature: message.signature) else {
            return .failed("bad signature")
        }

        let payload: [String: Any] = ["type": type,
                                      "content": json["content"] as? [String: Any] ?? [:]]
        if plaintexts.count >= MagnistraMatrixDecryptor.maxCachedPlaintexts { plaintexts.removeAll() }
        plaintexts[eventId] = payload
        return .decrypted(payload)
    }

    func placeholder(for outcome: Outcome) -> String {
        switch outcome {
        case .decrypted:
            return ""
        case .locked:
            return "\u{1F512} Encrypted — enter your recovery key in Settings"
        case .noKey:
            return "\u{1F512} Encrypted — no key for this message"
        case .failed(let reason):
            return "\u{1F512} Encrypted — \(reason)"
        }
    }

    private func ratchet(for session: MagnistraMegolmSession, at index: Int) -> [UInt8]? {
        let key = session.sessionId + "|" + String(index)
        if let cached = ratchets[key] { return cached }
        guard let advanced = MagnistraMegolmRatchet.advance(session.ratchet,
                                                   from: session.firstKnownIndex,
                                                   to: index) else { return nil }
        if ratchets.count >= MagnistraMatrixDecryptor.maxCachedRatchets { ratchets.removeAll() }
        ratchets[key] = advanced
        return advanced
    }

    private struct MegolmMessage {
        let index: Int
        let ciphertext: [UInt8]
        let macBody: [UInt8]
        let mac: [UInt8]
        let signedBody: [UInt8]
        let signature: [UInt8]
    }

    private static func parseMessage(_ bytes: [UInt8]) -> MegolmMessage? {
        let trailer = 8 + 64
        guard bytes.count > 1 + trailer, bytes[0] == 0x03 else { return nil }
        let bodyEnd = bytes.count - trailer

        var i = 1
        var index: Int? = nil
        var ciphertext: [UInt8]? = nil
        while i < bodyEnd {
            let tag = bytes[i]
            i += 1
            switch tag {
            case 0x08:
                guard let value = readVarint(bytes, &i, bodyEnd) else { return nil }
                index = value
            case 0x12:
                guard let length = readVarint(bytes, &i, bodyEnd),
                      i + length <= bodyEnd else { return nil }
                ciphertext = Array(bytes[i..<(i + length)])
                i += length
            default:

                switch tag & 0x07 {
                case 0:
                    guard readVarint(bytes, &i, bodyEnd) != nil else { return nil }
                case 2:
                    guard let length = readVarint(bytes, &i, bodyEnd),
                          i + length <= bodyEnd else { return nil }
                    i += length
                default:
                    return nil
                }
            }
        }
        guard i == bodyEnd, let messageIndex = index, let cipher = ciphertext,
              !cipher.isEmpty else { return nil }

        return MegolmMessage(index: messageIndex,
                             ciphertext: cipher,
                             macBody: Array(bytes[0..<bodyEnd]),
                             mac: Array(bytes[bodyEnd..<(bodyEnd + 8)]),
                             signedBody: Array(bytes[0..<(bytes.count - 64)]),
                             signature: Array(bytes[(bytes.count - 64)...]))
    }

    private static func readVarint(_ bytes: [UInt8], _ i: inout Int, _ end: Int) -> Int? {
        var value = 0
        var shift = 0
        while i < end {
            let byte = bytes[i]
            i += 1

            if shift > 21 { return nil }
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}

final class MagnistraMatrixRecoveryClient {
    private let homeserver: String
    private let accessToken: String

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    init(homeserver: String, accessToken: String) {
        self.homeserver = homeserver.hasSuffix("/")
            ? String(homeserver.dropLast())
            : homeserver
        self.accessToken = accessToken
    }

    private func makeError(_ message: String, code: Int) -> NSError {
        return NSError(
            domain: "MagnistraMatrixRecovery",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    func get(
        _ path: String,
        timeout: Int = 60,
        completion: @escaping ([String: Any]?, Error?) -> Void
    ) {
        let base = homeserver
        let token = accessToken

        queue.addOperation {
            guard let caPath = Bundle.main.path(
                forResource: "CACert",
                ofType: "pem"
            ) else {
                OperationQueue.main.addOperation {
                    completion(nil, self.makeError(
                        "Secure connection support is unavailable.",
                        code: 8601
                    ))
                }
                return
            }

            let url = base + path
            let userAgent = "Magnistra/1.0"

            let curlCode: Int32 = caPath.withCString { ca in
                url.withCString { requestURL in
                    token.withCString { authToken in
                        userAgent.withCString { ua in
                            Int32(magnistra_matrix_space_get_json(
                                ca, requestURL, authToken, ua
                            ))
                        }
                    }
                }
            }

            let status = magnistra_matrix_space_http_status()
            let tls = magnistra_matrix_space_tls_verify_result()

            if curlCode != 0 {
                OperationQueue.main.addOperation {
                    completion(nil, self.makeError(
                        "Could not contact the Matrix homeserver.",
                        code: 8602
                    ))
                }
                return
            }

            if tls != 0 {
                OperationQueue.main.addOperation {
                    completion(nil, self.makeError(
                        "The secure connection could not be verified.",
                        code: 8603
                    ))
                }
                return
            }

            let length = Int(magnistra_matrix_space_body_length())

            guard length > 0, let pointer = magnistra_matrix_space_body() else {
                OperationQueue.main.addOperation {
                    completion(nil, self.makeError(
                        "The homeserver returned an empty response.",
                        code: 8604
                    ))
                }
                return
            }

            let data = Data(bytes: pointer, count: length)

            do {
                let object = try MagnistraJSONKit.jsonObject(
                    with: data,
                    options: []
                )

                guard let json = object as? [String: Any] else {
                    throw self.makeError(
                        "The homeserver returned an unexpected response.",
                        code: 8605
                    )
                }

                guard status >= 200 && status < 300 else {
                    let message = (json["error"] as? String)
                        ?? "Matrix returned HTTP \(status)."
                    throw self.makeError(message, code: Int(status))
                }

                OperationQueue.main.addOperation {
                    completion(json, nil)
                }
            } catch {
                OperationQueue.main.addOperation {
                    completion(nil, error)
                }
            }
        }
    }
}

final class MagnistraMatrixRecoveryKeyViewController: UIViewController {

    private let client: MagnistraMatrixRecoveryClient

    var onRestored: (() -> Void)?

    private var promptLabel: UILabel!
    private var keyView: UITextView!
    private var statusLabel: UILabel!
    private var verifyItem: UIBarButtonItem!

    private var busy = false
    private var deviceTrustResult = "Device verification not completed."

    init(client: MagnistraMatrixRecoveryClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
        title = "Recovery Key"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.95, alpha: 1.0)

        verifyItem = UIBarButtonItem(title: "Verify", style: .done,
                                     target: self, action: #selector(verifyTapped))
        navigationItem.rightBarButtonItem = verifyItem

        promptLabel = UILabel(frame: .zero)

        promptLabel.backgroundColor = .clear
        promptLabel.textColor = UIColor(white: 0.3, alpha: 1.0)
        promptLabel.font = UIFont.systemFont(ofSize: 13)
        promptLabel.numberOfLines = 0
        promptLabel.text = "Enter the recovery key you saved when you set up encryption. "
                         + "Spaces don't matter, but capitalisation does."
        view.addSubview(promptLabel)

        keyView = UITextView(frame: .zero)
        keyView.backgroundColor = .white
        keyView.textColor = .black
        keyView.font = UIFont.systemFont(ofSize: 15)
        keyView.autocorrectionType = .no

        keyView.autocapitalizationType = .none
        keyView.spellCheckingType = .no
        view.addSubview(keyView)

        statusLabel = UILabel(frame: .zero)
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = UIColor(white: 0.3, alpha: 1.0)
        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = view.bounds.width
        promptLabel.frame = CGRect(x: 16, y: 76, width: width - 32, height: 52)
        keyView.frame = CGRect(x: 0, y: 136, width: width, height: 88)
        statusLabel.frame = CGRect(x: 16, y: 236, width: width - 32,
                                   height: max(60, view.bounds.height - 236 - 16))
    }

    @objc private func verifyTapped() {
        guard !busy else { return }

        guard let key = MagnistraRecoveryKey.decode(keyView.text ?? ""), key.count == 32 else {
            statusLabel.text = "That doesn't look like a recovery key."
            return
        }
        guard let userId = MagnistraMatrixAccountStore.userId, !userId.isEmpty else {
            statusLabel.text = "Not signed in."
            return
        }

        setBusy(true, status: "Checking…")
        keyView.resignFirstResponder()

        let base = "/_matrix/client/v3/user/\(userId)/account_data/"
        let defaultKeyPath = base + "m.secret_storage.default_key"
        client.get(defaultKeyPath) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error { self.fail(error, path: defaultKeyPath); return }
            guard let keyId = json?["key"] as? String, !keyId.isEmpty else {
                self.setBusy(false, status: "This account has no recovery key set up.")
                return
            }

            let keyPath = base + "m.secret_storage.key." + MagnistraMatrixRecoveryKeyViewController.pathEncode(keyId)
            self.client.get(keyPath) { [weak self] json, error in
                guard let self = self else { return }
                if let error = error { self.fail(error, path: keyPath); return }
                guard let keyInfo = json else {
                    self.setBusy(false, status: "The server didn't return the key description.")
                    return
                }
                if let failure = self.check(key: key, keyInfo: keyInfo) {
                    self.setBusy(false, status: failure)
                    return
                }

                self.keyView.text = ""
                self.verifyDeviceAndRestore(key: key, keyId: keyId, base: base)
            }
        }
    }

    private func verifyDeviceAndRestore(key: [UInt8], keyId: String, base: String) {
        setBusy(true, status: "Checking device identity…")
        let name = "m.cross_signing.self_signing"
        let path = base + name
        client.get(path) { [weak self] json, error in
            guard let self = self else { return }
            guard error == nil,
                  let encrypted = json?["encrypted"] as? [String: Any],
                  let entry = encrypted[keyId] as? [String: Any],
                  let text = MagnistraMatrixRecoveryKeyViewController.decryptSecret(
                      name: name, key: key, entry: entry),
                  let seed = MagnistraRecoveryBase64.decode(text), seed.count == 32 else {
                self.deviceTrustResult = "Device not verified: existing self-signing secret unavailable."
                self.restore(key: key, keyId: keyId, base: base)
                return
            }
            MagnistraMatrixDirectBackend.shared.prepare()
            self.waitForCryptoDevice(seed: seed, key: key,
                                          keyId: keyId, base: base, remaining: 8)
        }
    }

    private func waitForCryptoDevice(seed: [UInt8], key: [UInt8],
                                          keyId: String, base: String, remaining: Int) {
        if MagnistraMatrixDeviceVerificationManager.shared.magnistraCryptoIdentityReady {
            MagnistraMatrixDeviceVerificationManager.shared
                .verifyUsingRecoveredSelfSigningKey(seed) { [weak self] verified, result in
                    guard let self = self else { return }
                    self.deviceTrustResult = verified ? "Device verified." : result
                    self.restore(key: key, keyId: keyId, base: base)
                }
            return
        }
        if remaining <= 0 {
            deviceTrustResult = "Device not verified: encryption is not initialized."
            restore(key: key, keyId: keyId, base: base)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.waitForCryptoDevice(seed: seed, key: key, keyId: keyId,
                                           base: base, remaining: remaining - 1)
        }
    }

    private func check(key: [UInt8], keyInfo: [String: Any]) -> String? {
        let algorithm = keyInfo["algorithm"] as? String ?? ""
        guard algorithm == "m.secret_storage.v1.aes-hmac-sha2" else {
            return "Unsupported key algorithm (\(algorithm.isEmpty ? "none" : algorithm))."
        }
        guard let ivText = keyInfo["iv"] as? String,
              let macText = keyInfo["mac"] as? String,
              let iv = MagnistraRecoveryBase64.decode(ivText), iv.count == 16,
              let expectedMAC = MagnistraRecoveryBase64.decode(macText), !expectedMAC.isEmpty else {
            return "The stored key description is malformed."
        }

        let zeroes = [UInt8](repeating: 0, count: 32)
        guard let derived = RecoveryCrypto.hkdfSHA256(ikm: key, salt: zeroes, info: [], length: 64),
              let ciphertext = RecoveryCrypto.aes256CTR(key: Array(derived[0..<32]), iv: iv, data: zeroes),
              let mac = RecoveryCrypto.hmacSHA256(key: Array(derived[32..<64]), data: ciphertext) else {
            return "Couldn't derive the keys."
        }
        guard mac == expectedMAC else { return "That recovery key is not valid." }
        return nil
    }

    private func restore(key: [UInt8], keyId: String, base: String) {
        setBusy(true, status: "Unlocking message keys…")
        let secretPath = base + "m.megolm_backup.v1"
        client.get(secretPath) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error { self.fail(error, path: secretPath); return }
            guard let encrypted = json?["encrypted"] as? [String: Any],
                  let entry = encrypted[keyId] as? [String: Any] else {
                self.setBusy(false, status: "No message key backup is stored on this account.")
                return
            }

            guard let text = MagnistraMatrixRecoveryKeyViewController.decryptSecret(name: "m.megolm_backup.v1", key: key, entry: entry),
                  let privateKey = MagnistraRecoveryBase64.decode(text), privateKey.count == 32 else {
                self.setBusy(false, status: "Couldn't unlock the backup key.")
                return
            }
            self.fetchBackupVersion(privateKey: privateKey)
        }
    }

    private func fetchBackupVersion(privateKey: [UInt8]) {
        let path = "/_matrix/client/v3/room_keys/version"
        client.get(path) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error { self.fail(error, path: path); return }
            let algorithm = json?["algorithm"] as? String ?? ""
            guard algorithm == "m.megolm_backup.v1.curve25519-aes-sha2" else {
                self.setBusy(false, status: "Unsupported backup algorithm "
                    + "(\(algorithm.isEmpty ? "none" : algorithm)).")
                return
            }
            guard let version = json?["version"] as? String, !version.isEmpty else {
                self.setBusy(false, status: "The backup has no version.")
                return
            }

            guard let auth = json?["auth_data"] as? [String: Any],
                  let publicText = auth["public_key"] as? String,
                  let expected = MagnistraRecoveryBase64.decode(publicText),
                  let ours = RecoveryCrypto.x25519PublicKey(privateKey: privateKey),
                  ours == expected else {
                self.setBusy(false, status: "The unlocked key doesn't match this backup.")
                return
            }
            self.fetchKeys(privateKey: privateKey, version: version)
        }
    }

    private func fetchKeys(privateKey: [UInt8], version: String) {
        setBusy(true, status: "Downloading message keys…")
        let path = "/_matrix/client/v3/room_keys/keys?version=" + MagnistraMatrixRecoveryKeyViewController.pathEncode(version)
        client.get(path) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error { self.fail(error, path: path); return }
            guard let rooms = json?["rooms"] as? [String: Any], !rooms.isEmpty else {
                self.setBusy(false, status: "The backup is empty.")
                return
            }

            var recovered: [MagnistraMegolmSession] = []
            var unreadable = 0

            var firstReason: String? = nil
            for (roomId, rawRoom) in rooms {
                guard let sessions = (rawRoom as? [String: Any])?["sessions"] as? [String: Any] else { continue }
                for (sessionId, rawSession) in sessions {
                    guard let data = (rawSession as? [String: Any])?["session_data"] as? [String: Any] else {
                        unreadable += 1
                        if firstReason == nil { firstReason = "no session data" }
                        continue
                    }
                    let outcome = MagnistraMatrixRecoveryKeyViewController.decodeSession(roomId: roomId, sessionId: sessionId,
                                                             data: data, privateKey: privateKey)
                    if let session = outcome.session {
                        recovered.append(session)
                    } else {
                        unreadable += 1
                        if firstReason == nil { firstReason = outcome.reason }
                    }
                }
            }
            MagnistraMegolmKeyStore.shared.merge(recovered)
            let total = MagnistraMegolmKeyStore.shared.count
            self.setBusy(false, status: unreadable > 0
                ? "\(unreadable) key\(unreadable == 1 ? "" : "s") in the backup could not be read"
                  + (firstReason.map { ": \($0)." } ?? ".")
                : "")
            self.onRestored?()
            self.alert(title: "Message keys restored",
                       message: self.deviceTrustResult + "\n\n" + "\(total) message key\(total == 1 ? "" : "s") "
                              + "\(total == 1 ? "is" : "are") available on this device.")
        }
    }

    private static func decryptSecret(name: String, key: [UInt8], entry: [String: Any]) -> String? {
        guard let ivText = entry["iv"] as? String,
              let cipherText = entry["ciphertext"] as? String,
              let macText = entry["mac"] as? String,
              let iv = MagnistraRecoveryBase64.decode(ivText), iv.count == 16,
              let ciphertext = MagnistraRecoveryBase64.decode(cipherText), !ciphertext.isEmpty,
              let expectedMAC = MagnistraRecoveryBase64.decode(macText), !expectedMAC.isEmpty else { return nil }
        let zeroes = [UInt8](repeating: 0, count: 32)
        guard let derived = RecoveryCrypto.hkdfSHA256(ikm: key, salt: zeroes,
                                              info: Array(name.utf8), length: 64),
              let mac = RecoveryCrypto.hmacSHA256(key: Array(derived[32..<64]), data: ciphertext),
              mac == expectedMAC,
              let plain = RecoveryCrypto.aes256CTR(key: Array(derived[0..<32]), iv: iv, data: ciphertext) else {
            return nil
        }
        return String(bytes: plain, encoding: .utf8)
    }

    private static func decodeSession(roomId: String, sessionId: String,
                                      data: [String: Any], privateKey: [UInt8])
        -> (session: MagnistraMegolmSession?, reason: String?) {
        guard let ephemeralText = data["ephemeral"] as? String,
              let cipherText = data["ciphertext"] as? String,
              let macText = data["mac"] as? String,
              let ephemeral = MagnistraRecoveryBase64.decode(ephemeralText), ephemeral.count == 32,
              let ciphertext = MagnistraRecoveryBase64.decode(cipherText),
              !ciphertext.isEmpty, ciphertext.count % 16 == 0,

              let expectedMAC = MagnistraRecoveryBase64.decode(macText), expectedMAC.count >= 8 else {
            return (nil, "malformed session data")
        }
        guard let shared = RecoveryCrypto.x25519(privateKey: privateKey, peerPublicKey: ephemeral),
              let derived = RecoveryCrypto.hkdfSHA256(ikm: shared,
                                              salt: [UInt8](repeating: 0, count: 32),
                                              info: [], length: 80) else {
            return (nil, "key agreement failed")
        }

        let macKey = Array(derived[32..<64])
        let expected = Array(expectedMAC[0..<8])
        let matches: ([UInt8]) -> Bool = { message in
            guard let mac = RecoveryCrypto.hmacSHA256(key: macKey, data: message) else { return false }
            return Array(mac[0..<8]) == expected
        }
        guard matches([]) || matches(ciphertext) else { return (nil, "MAC mismatch") }
        guard let plain = RecoveryCrypto.aes256CBCDecrypt(key: Array(derived[0..<32]),
                                                  iv: Array(derived[64..<80]),
                                                  data: ciphertext) else {
            return (nil, "could not decrypt")
        }
        guard let json = (try? MagnistraJSONKit.jsonObject(with: Data(plain),
                                                            options: [])) as? [String: Any] else {
            return (nil, "decrypted data is not JSON")
        }
        let algorithm = json["algorithm"] as? String ?? ""
        guard algorithm == "m.megolm.v1.aes-sha2" else {
            return (nil, "unsupported algorithm (\(algorithm.isEmpty ? "none" : algorithm))")
        }

        guard let sessionKey = json["session_key"] as? String,
              let exported = MagnistraRecoveryBase64.decode(sessionKey), exported.count >= 165,
              exported[0] == 0x01 else {
            return (nil, "unexpected session key format")
        }
        let index = (Int(exported[1]) << 24) | (Int(exported[2]) << 16)
                  | (Int(exported[3]) << 8) | Int(exported[4])
        return (MagnistraMegolmSession(sessionId: sessionId,
                              roomId: roomId,
                              senderKey: json["sender_key"] as? String ?? "",
                              firstKnownIndex: index,
                              ratchet: Array(exported[5..<133]),
                              signingKey: Array(exported[133..<165])), nil)
    }

    private static let unreservedBytes: Set<UInt8> =
        Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    private static let hexDigits = Array("0123456789ABCDEF")

    private static func pathEncode(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if unreservedBytes.contains(byte) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result.append("%")
                result.append(hexDigits[Int(byte >> 4)])
                result.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return result
    }

    private func fail(_ error: Error, path: String) {
        setBusy(false, status: "Request failed.\n\(path)\n\(error)")
    }

    private func setBusy(_ value: Bool, status: String) {
        busy = value
        verifyItem.isEnabled = !value
        keyView.isEditable = !value
        statusLabel.text = status
    }

    private func alert(
        title: String,
        message: String
    ) {
        let alert =
            UIAlertView(
                title:
                    title,
                message:
                    message,
                delegate:
                    nil,
                cancelButtonTitle:
                    "OK"
            )

        alert.show()
    }
}
