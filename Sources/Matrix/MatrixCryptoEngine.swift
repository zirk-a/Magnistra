// Overview: Swift wrapper around the vodozemac end-to-end encryption engine.
import Foundation
import Security
import CoreFoundation

@_silgen_name("vdz5_r3_account_new") private func r66_account_new() -> UnsafeMutableRawPointer?
@_silgen_name("vdz5_r3_release") private func r66_release(_ h: UnsafeMutableRawPointer?)
@_silgen_name("vdz5_r3_account_identity") private func r66_identity(_ h: UnsafeMutableRawPointer?, _ which: UInt32, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_account_sign") private func r66_sign(_ h: UnsafeMutableRawPointer?, _ data: UnsafePointer<UInt8>?, _ n: Int, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_account_generate_otk") private func r66_generate_otk(_ h: UnsafeMutableRawPointer?, _ n: UInt32) -> Int32
@_silgen_name("vdz5_r3_account_unpublished_otk_json") private func r66_otk_json(_ h: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_account_mark_published") private func r66_mark_published(_ h: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("vdz5_r3_olm_outbound") private func r66_olm_outbound(_ h: UnsafeMutableRawPointer?, _ peer: UnsafePointer<UInt8>?, _ plen: Int, _ otk: UnsafePointer<UInt8>?, _ olen: Int) -> UnsafeMutableRawPointer?
@_silgen_name("vdz5_r3_olm_inbound") private func r66_olm_inbound(_ h: UnsafeMutableRawPointer?, _ sender: UnsafePointer<UInt8>?, _ slen: Int, _ body: UnsafePointer<UInt8>?, _ blen: Int, _ plain: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> UnsafeMutableRawPointer?
@_silgen_name("vdz5_r3_olm_encrypt") private func r66_olm_encrypt(_ h: UnsafeMutableRawPointer?, _ plain: UnsafePointer<UInt8>?, _ n: Int, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_olm_decrypt") private func r66_olm_decrypt(_ h: UnsafeMutableRawPointer?, _ msg: UnsafePointer<UInt8>?, _ n: Int, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_megolm_outbound_new") private func r66_group_new() -> UnsafeMutableRawPointer?
@_silgen_name("vdz5_r3_megolm_session_key") private func r66_group_key(_ h: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_megolm_inbound_new") private func r66_group_inbound(_ text: UnsafePointer<UInt8>?, _ n: Int) -> UnsafeMutableRawPointer?
@_silgen_name("vdz5_r3_megolm_encrypt") private func r66_group_encrypt(_ h: UnsafeMutableRawPointer?, _ plain: UnsafePointer<UInt8>?, _ n: Int, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_megolm_decrypt") private func r66_group_decrypt(_ h: UnsafeMutableRawPointer?, _ text: UnsafePointer<UInt8>?, _ n: Int, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_session_id") private func r66_session_id(_ h: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_pickle_encrypted") private func r66_pickle(_ h: UnsafeMutableRawPointer?, _ key: UnsafePointer<UInt8>?, _ klen: Int, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int) -> Int
@_silgen_name("vdz5_r3_unpickle_encrypted") private func r66_unpickle(_ kind: UInt32, _ src: UnsafePointer<UInt8>?, _ n: Int, _ key: UnsafePointer<UInt8>?, _ klen: Int) -> UnsafeMutableRawPointer?

final class MatrixCryptoEngine {
    static let shared = MatrixCryptoEngine()
    private let mutex = NSRecursiveLock()
    private var account: UnsafeMutableRawPointer?
    private var pickleKey: [UInt8] = []
    private var document: [String: Any] = [:]
    private var stateURL: URL?
    private var currentUser = ""
    private var currentDevice = ""
    private var valid = false

    var active: Bool { mutex.lock(); defer { mutex.unlock() }; return valid && account != nil }
    private init() {}

    private func bytes(_ string: String) -> [UInt8] { return Array(string.utf8) }

    private func r66StateKey(user: String, device: String) -> String {
        let raw = MagnistraRecoveryBase64.encode(Array((user + "|" + device).utf8))
        let remainder = raw.utf8.count % 4
        if remainder == 1 { return "" }
        let padded = raw + (remainder == 2 ? "==" : (remainder == 3 ? "=" : ""))
        return padded.replacingOccurrences(of: "/", with: "_")
                     .replacingOccurrences(of: "+", with: "-")
    }
    private func text(_ bytes: [UInt8]) -> String? { return String(bytes: bytes, encoding: .utf8) }
    private func callText(_ invoke: (UnsafeMutablePointer<UInt8>?, Int) -> Int) -> String? {
        var out = [UInt8](repeating: 0, count: 1048576)
        let n = out.withUnsafeMutableBufferPointer { invoke($0.baseAddress, $0.count) }
        guard n > 0 && n <= out.count else { return nil }
        return text(Array(out[0..<n]))
    }
    private func pickle(_ h: UnsafeMutableRawPointer?) -> Data? {
        guard let h = h, pickleKey.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 1048576)
        let n = pickleKey.withUnsafeBufferPointer { k in
            out.withUnsafeMutableBufferPointer { dst in
                r66_pickle(h, k.baseAddress, k.count, dst.baseAddress, dst.count)
            }
        }
        guard n > 0 && n <= out.count else { return nil }
        return Data(out[0..<n])
    }
    private func unpickle(_ kind: UInt32, _ data: Data) -> UnsafeMutableRawPointer? {
        let b = [UInt8](data)
        return pickleKey.withUnsafeBufferPointer { key in
            b.withUnsafeBufferPointer { src in
                r66_unpickle(kind, src.baseAddress, src.count, key.baseAddress, key.count)
            }
        }
    }
    private func keyFromKeychain(_ service: String, create: Bool) -> [UInt8]? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "vodozemac-r66",
            kSecReturnData as String: kCFBooleanTrue as Any]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else { return nil }
            return [UInt8](data)
        }
        guard create && status == errSecItemNotFound else { return nil }
        var fresh = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, fresh.count, &fresh) == errSecSuccess else { return nil }
        var insert = q
        insert.removeValue(forKey: kSecReturnData as String)
        insert[kSecValueData as String] = Data(fresh)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { return nil }
        return fresh
    }
    private func save() -> Bool {
        guard let url = stateURL, let acct = pickle(account) else { return false }
        document["account"] = acct
        guard let data = try? PropertyListSerialization.data(fromPropertyList: document,
                                     format: .binary, options: 0) else { return false }

        return (try? data.write(to: url, options: .atomic)) != nil
    }
    func open(user: String, device: String, allowNew: Bool) -> (String, String)? {
        mutex.lock(); defer { mutex.unlock() }
        if valid && user == currentUser && device == currentDevice { return publicIdentity() }
        if let old = account { r66_release(old) }
        account = nil; valid = false; document = [:]; pickleKey = []
        let encoded = r66StateKey(user: user, device: device)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let root = dir, !encoded.isEmpty,
              (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)) != nil else { return nil }
        let file = URL(fileURLWithPath: (root.path as NSString).appendingPathComponent("matrix-vodozemac-r66-" + encoded + ".plist"))
        let exists = FileManager.default.fileExists(atPath: file.path)
        guard exists || allowNew,
              let key = keyFromKeychain("dev.k1tzya.magnistra.matrix.r66." + encoded, create: !exists) else { return nil }
        pickleKey = key; stateURL = file
        if exists {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let doc = obj as? [String: Any],
                  let payload = doc["account"] as? Data,
                  let restored = unpickle(1, payload) else { return nil }
            document = doc; account = restored
        } else {
            guard let created = r66_account_new() else { return nil }
            account = created
            document = ["olm": [String: Data](), "olmPeers": [String: String](),
                        "outboundGroups": [String: [String: Any]](), "inboundGroups": [String: Data]()]
            guard save() else { r66_release(created); account = nil; return nil }
        }
        currentUser = user; currentDevice = device; valid = true
        return publicIdentity()
    }
    func hasSnapshot(user: String, device: String) -> Bool {
        let encoded = r66StateKey(user: user, device: device)
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        return FileManager.default.fileExists(atPath: (root.path as NSString).appendingPathComponent("matrix-vodozemac-r66-" + encoded + ".plist"))
    }
    private func publicIdentity() -> (String, String)? {
        guard let a = account,
              let ed = callText({ r66_identity(a, 1, $0, $1) }),
              let curve = callText({ r66_identity(a, 2, $0, $1) }) else { return nil }
        return (ed, curve)
    }
    func identities() -> (String, String)? { mutex.lock(); defer { mutex.unlock() }; return valid ? publicIdentity() : nil }
    func signBase64(_ bytes: [UInt8]) -> String? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, let a = account else { return nil }
        return bytes.withUnsafeBufferPointer { b in
            callText { r66_sign(a, b.baseAddress, b.count, $0, $1) }
        }
    }
    func prepareOTK(count: Int, user: String, device: String,
                    canonical: ([String: Any]) -> String?) -> [String: Any]? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, let a = account, count > 0 && count <= 50,
              r66_generate_otk(a, UInt32(count)) == 0,
              let str = callText({ r66_otk_json(a, $0, $1) }),
              let dat = str.data(using: .utf8),
              let keys = (try? JSONSerialization.jsonObject(with: dat, options: [])) as? [String: String] else { return nil }

        guard save() else { return nil }
        var result: [String: Any] = [:]
        for kv in keys.sorted(by: {$0.key < $1.key}) {
            let plain: [String: Any] = ["key": kv.value]
            guard let signedText = canonical(plain),
                  let sig = signBase64(bytes(signedText)) else { return nil }
            let safe = kv.value.replacingOccurrences(of: "+", with: "-")
                               .replacingOccurrences(of: "/", with: "_")
                               .replacingOccurrences(of: "=", with: "")
            let name = "signed_curve25519:r66_\(safe.prefix(24))"
            result[name] = ["key": kv.value,
                            "signatures": [user: ["ed25519:\(device)": sig]]]
        }
        return result
    }
    func markOTKUploaded() -> Bool {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, r66_mark_published(account) == 0 else { return false }
        return save()
    }
    func hasOlm(peer: String) -> Bool {
        mutex.lock(); defer { mutex.unlock() }

        let peers = document["olmPeers"] as? [String: String] ?? [:]
        let sessions = document["olm"] as? [String: Data] ?? [:]
        guard let id = peers[peer], let saved = sessions[id],
              let session = unpickle(2, saved) else { return false }
        r66_release(session)
        return true
    }
    func encryptOlm(peer: String, peerCurve: String, oneTime: String?, plain: [String: Any]) -> [String: Any]? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, let a = account,
              let clear = try? JSONSerialization.data(withJSONObject: plain, options: []) else { return nil }
        var sessions = document["olm"] as? [String: Data] ?? [:]
        var peers = document["olmPeers"] as? [String: String] ?? [:]
        let sid = peers[peer]
        var handle: UnsafeMutableRawPointer?
        if let sid = sid, let stored = sessions[sid] { handle = unpickle(2, stored) }
        if handle == nil {
            guard let otk = oneTime else { return nil }
            let recipient = bytes(peerCurve), pub = bytes(otk)
            handle = recipient.withUnsafeBufferPointer { c in pub.withUnsafeBufferPointer { o in
                r66_olm_outbound(a, c.baseAddress, c.count, o.baseAddress, o.count)
            }}
        }
        guard let h = handle else { return nil }
        defer { r66_release(h) }
        var wire = [UInt8](repeating: 0, count: min(1048576, max(8192, clear.count * 3 + 4096)))
        let n = [UInt8](clear).withUnsafeBufferPointer { src in wire.withUnsafeMutableBufferPointer { dst in
            r66_olm_encrypt(h, src.baseAddress, src.count, dst.baseAddress, dst.count)
        }}
        guard n > 0 && n <= wire.count,
              let obj = try? JSONSerialization.jsonObject(with: Data(wire[0..<n]), options: []),
              let packet = obj as? [String: Any],
              let typ = packet["type"] as? Int, let body = packet["body"] as? String,
              let newid = callText({ r66_session_id(h, $0, $1) }),
              let enc = pickle(h) else { return nil }
        sessions[newid] = enc; peers[peer] = newid
        document["olm"] = sessions; document["olmPeers"] = peers

        guard save() else { return nil }
        return ["type": typ, "body": body]
    }
    func decryptOlm(senderCurve: String, type: Int, body: String) -> [String: Any]? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, let a = account else { return nil }
        var sessions = document["olm"] as? [String: Data] ?? [:]
        let encoded = bytes(body)
        let json: [String: Any] = ["type": type, "body": body]
        guard let msg = try? JSONSerialization.data(withJSONObject: json, options: []) else { return nil }
        for (sid, stored) in sessions {
            guard let handle = unpickle(2, stored) else { continue }
            var plain = [UInt8](repeating: 0, count: max(8192, msg.count * 4))
            let n = [UInt8](msg).withUnsafeBufferPointer { input in plain.withUnsafeMutableBufferPointer { out in
                r66_olm_decrypt(handle, input.baseAddress, input.count, out.baseAddress, out.count)
            }}
            if n > 0 && n <= plain.count, let next = pickle(handle),
               let parsed = (try? JSONSerialization.jsonObject(with: Data(plain[0..<n]), options: [])) as? [String: Any] {
                sessions[sid] = next; document["olm"] = sessions
                let ok = save(); r66_release(handle)
                return ok ? parsed : nil
            }
            r66_release(handle)
        }
        guard type == 0 else { return nil }

        var plain = [UInt8](repeating: 0, count: max(8192, encoded.count * 4))
        let sender = bytes(senderCurve)
        let handle = sender.withUnsafeBufferPointer { s in encoded.withUnsafeBufferPointer { b in plain.withUnsafeMutableBufferPointer { dst in
            r66_olm_inbound(a, s.baseAddress, s.count, b.baseAddress, b.count, dst.baseAddress, dst.count)
        }}}
        guard let h = handle else { return nil }
        defer { r66_release(h) }
        guard let end = plain.firstIndex(of: 0), end > 1,
              let parsed = (try? JSONSerialization.jsonObject(with: Data(plain[0..<end]), options: [])) as? [String: Any],
              let id = callText({ r66_session_id(h, $0, $1) }),
              let stored = pickle(h) else { return nil }
        sessions[id] = stored; document["olm"] = sessions
        guard save() else { return nil }
        return parsed
    }
    func groupForRoom(_ room: String) -> (String, String, Set<String>)? {
        mutex.lock(); defer { mutex.unlock() }
        let all = document["outboundGroups"] as? [String: [String: Any]] ?? [:]
        guard let r = all[room], let sid = r["id"] as? String,
              let stored = r["pickle"] as? Data,
              let h = unpickle(3, stored) else { return nil }
        defer { r66_release(h) }
        guard let key = callText({ r66_group_key(h, $0, $1) }) else { return nil }
        return (sid, key, Set(r["shared"] as? [String] ?? []))
    }
    func makeGroup(room: String) -> (String, String, Set<String>)? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, let h = r66_group_new() else { return nil }
        defer { r66_release(h) }
        guard let sid = callText({ r66_session_id(h, $0, $1) }),
              let key = callText({ r66_group_key(h, $0, $1) }),
              let payload = pickle(h) else { return nil }
        var all = document["outboundGroups"] as? [String: [String: Any]] ?? [:]
        all[room] = ["id": sid, "pickle": payload,
                     "created": Date().timeIntervalSince1970, "count": 0, "shared": [String]()]
        document["outboundGroups"] = all
        guard save(), importGroup(room: room, sender: identities()?.1 ?? "", id: sid, key: key) else { return nil }
        return (sid, key, [])
    }
    func rotateGroupIfNeeded(room: String) -> (String, String, Set<String>)? {
        mutex.lock(); defer { mutex.unlock() }
        let all = document["outboundGroups"] as? [String: [String: Any]] ?? [:]
        if let r = all[room], let created = r["created"] as? Double,
           let count = r["count"] as? Int,
           count < 100 && Date().timeIntervalSince1970 - created < 604800 {
            return groupForRoom(room)
        }
        return makeGroup(room: room)
    }
    func groupShareDone(room: String, fingerprints: [String]) -> Bool {
        mutex.lock(); defer { mutex.unlock() }
        var all = document["outboundGroups"] as? [String: [String: Any]] ?? [:]
        guard var r = all[room] else { return false }
        let old = r["shared"] as? [String] ?? []
        r["shared"] = Array(Set(old + fingerprints)).sorted()
        all[room] = r; document["outboundGroups"] = all
        return save()
    }
    func encryptGroup(room: String, type: String, content: [String: Any], device: String) -> [String: Any]? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid, let sender = identities()?.1,
              let clear = try? JSONSerialization.data(withJSONObject: ["type": type, "content": content, "room_id": room], options: []),
              var all = document["outboundGroups"] as? [String: [String: Any]],
              var record = all[room], let stored = record["pickle"] as? Data,
              let sid = record["id"] as? String,
              let h = unpickle(3, stored) else { return nil }
        defer { r66_release(h) }
        var wire = [UInt8](repeating: 0, count: min(1048576, max(8192, clear.count * 3 + 4096)))
        let n = [UInt8](clear).withUnsafeBufferPointer { input in wire.withUnsafeMutableBufferPointer { out in
            r66_group_encrypt(h, input.baseAddress, input.count, out.baseAddress, out.count)
        }}
        guard n > 0 && n <= wire.count, let cipher = text(Array(wire[0..<n])),
              let next = pickle(h) else { return nil }
        record["pickle"] = next
        record["count"] = (record["count"] as? Int ?? 0) + 1
        all[room] = record; document["outboundGroups"] = all
        guard save() else { return nil }
        return ["algorithm": "m.megolm.v1.aes-sha2", "sender_key": sender,
                "device_id": device, "session_id": sid, "ciphertext": cipher]
    }
    func importGroup(room: String, sender: String, id: String, key: String) -> Bool {
        mutex.lock(); defer { mutex.unlock() }
        guard valid else { return false }
        let b = bytes(key)
        guard let h = b.withUnsafeBufferPointer({ r66_group_inbound($0.baseAddress, $0.count) }) else { return false }
        defer { r66_release(h) }
        guard let sid = callText({ r66_session_id(h, $0, $1) }), sid == id,
              let data = pickle(h) else { return false }
        var inbound = document["inboundGroups"] as? [String: Data] ?? [:]
        let identifier = sender + "|" + sid
        if inbound[identifier] == nil { inbound[identifier] = data }
        document["inboundGroups"] = inbound
        return save()
    }
    func decryptGroup(sender: String, id: String, text cipher: String) -> [String: Any]? {
        mutex.lock(); defer { mutex.unlock() }
        guard valid else { return nil }
        var inbound = document["inboundGroups"] as? [String: Data] ?? [:]
        let identifier = sender + "|" + id
        guard let saved = inbound[identifier], let h = unpickle(4, saved) else { return nil }
        defer { r66_release(h) }
        let payload = bytes(cipher)
        var out = [UInt8](repeating: 0, count: 1048576)
        let n = payload.withUnsafeBufferPointer { buf in out.withUnsafeMutableBufferPointer { dst in
            r66_group_decrypt(h, buf.baseAddress, buf.count, dst.baseAddress, dst.count)
        }}
        guard n > 0 && n <= out.count,
              let decoded = (try? JSONSerialization.jsonObject(with: Data(out[0..<n]), options: [])) as? [String: Any],
              let next = pickle(h) else { return nil }
        inbound[identifier] = next; document["inboundGroups"] = inbound
        return save() ? decoded : nil
    }
}
