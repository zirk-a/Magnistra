// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Models for encrypted and prepared media and outbound Megolm state.
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



struct MagnistraEncryptedMediaRecord {
    let key: [UInt8]
    let iv: [UInt8]
    let sha256: [UInt8]

    func descriptor(url: String) -> [String: Any] {
        return [
            "url": url,
            "v": "v2",
            "key": [
                "kty": "oct",
                "key_ops": ["encrypt", "decrypt"],
                "alg": "A256CTR",
                "k": magnistraMediaBase64URL(key),
                "ext": true
            ],
            "iv": magnistraMediaBase64(iv),
            "hashes": ["sha256": magnistraMediaBase64(sha256)]
        ]
    }
}

struct MagnistraPreparedMedia {
    let path: String
    let encrypted: MagnistraEncryptedMediaRecord?
    let removeWhenDone: Bool
}

struct MagnistraOutboundDevice {
    let userId: String
    let deviceId: String
    let curve25519: String
    let ed25519: String
}

struct MagnistraOutboundMegolm {
    let roomId: String
    var index: UInt32
    var r0: [UInt8]
    var r1: [UInt8]
    var r2: [UInt8]
    var r3: [UInt8]
    let signingPrivate: [UInt8]
    let signingPublic: [UInt8]
    let createdMs: Int64
    var messageCount: Int
    var sharedFingerprints: Set<String>

    var sessionId: String { magnistraMediaBase64(signingPublic) }
}

let magnistraEncryptedMediaLock = NSLock()
var magnistraEncryptedMediaByMXC: [String: MagnistraEncryptedMediaRecord] = [:]

func magnistraMediaBase64(_ bytes: [UInt8]) -> String {
    let table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var out: [UInt8] = []
    var i = 0
    while i < bytes.count {
        let a = Int(bytes[i]); i += 1
        let hasB = i < bytes.count
        let b = hasB ? Int(bytes[i]) : 0
        if hasB { i += 1 }
        let hasC = i < bytes.count
        let c = hasC ? Int(bytes[i]) : 0
        if hasC { i += 1 }

        out.append(table[(a >> 2) & 63])
        out.append(table[((a & 3) << 4) | ((b >> 4) & 15)])
        if hasB { out.append(table[((b & 15) << 2) | ((c >> 6) & 3)]) }
        if hasC { out.append(table[c & 63]) }
    }
    return String(bytes: out, encoding: .utf8) ?? ""
}

func magnistraMediaBase64URL(_ bytes: [UInt8]) -> String {
    return magnistraMediaBase64(bytes)
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
}

func magnistraMediaBase64Decode(_ text: String, expected: Int? = nil) -> [UInt8]? {
    var vals: [UInt8] = []
    for ch in text.utf8 {
        if ch == 61 { break }
        let v: UInt8
        switch ch {
        case 65...90:  v = ch - 65
        case 97...122: v = ch - 97 + 26
        case 48...57:  v = ch - 48 + 52
        case 43, 45:   v = 62
        case 47, 95:   v = 63
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
    if let expected = expected, out.count != expected { return nil }
    return out
}