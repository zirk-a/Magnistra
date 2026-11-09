// Overview: Encrypted local storage: seals and opens private app state and preferences with a Keychain-held key.
import UIKit
import Security
import QuartzCore
import CoreText
import ImageIO
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import SystemConfiguration

import Foundation
import Security

@_silgen_name("magnistra_private_seal")
private func magnistraPrivateSeal(_ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                  _ key: UnsafePointer<UInt8>?,
                                  _ result: UnsafeMutablePointer<UInt8>?, _ capacity: Int,
                                  _ written: UnsafeMutablePointer<Int>?) -> Int32
@_silgen_name("magnistra_private_open")
private func magnistraPrivateOpen(_ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                  _ key: UnsafePointer<UInt8>?,
                                  _ result: UnsafeMutablePointer<UInt8>?, _ capacity: Int,
                                  _ written: UnsafeMutablePointer<Int>?) -> Int32

final class MagnistraPrivateState {
    static let shared = MagnistraPrivateState()
    private let lock = NSRecursiveLock()
    private let directory: String
    private let prefsPath: String
    private let megolmPath: String
    private var encryptionKey: Data?
    private var entries: [String: Any] = [:]
    private var ready = false

    private init() {
        let library = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        directory = (library as NSString).appendingPathComponent("Application Support/Magnistra")
        prefsPath = (directory as NSString).appendingPathComponent("private-state.dat")
        megolmPath = (directory as NSString).appendingPathComponent("megolm.dat")
        do {
            try FileManager.default.createDirectory(atPath: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
        } catch { return }
        let hasExistingVault = FileManager.default.fileExists(atPath: prefsPath)
            || FileManager.default.fileExists(atPath: megolmPath)
        guard let key = MagnistraPrivateState.retrieveKey(allowCreation: !hasExistingVault) else {

            return
        }
        encryptionKey = key
        if FileManager.default.fileExists(atPath: prefsPath) {
            guard let bytes = FileManager.default.contents(atPath: prefsPath),
                  let decoded = open(bytes),
                  let object = try? PropertyListSerialization.propertyList(from: decoded,
                                                    options: [], format: nil),
                  let dictionary = object as? [String: Any] else { return }
            entries = dictionary
        }
        ready = true
    }

    private static func retrieveKey(allowCreation: Bool) -> Data? {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.zirka.magnistra.matrix.private.v1",
            kSecAttrAccount as String: "vault-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecSuccess {
            guard let key = value as? Data, key.count == 32 else { return nil }
            return key
        }
        guard status == errSecItemNotFound && allowCreation else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        let create: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.zirka.magnistra.matrix.private.v1",
            kSecAttrAccount as String: "vault-key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(bytes)
        ]
        let added = SecItemAdd(create as CFDictionary, nil)
        guard added == errSecSuccess || added == errSecDuplicateItem else { return nil }
        var readBack: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &readBack) == errSecSuccess,
              let verified = readBack as? Data, verified.count == 32 else { return nil }
        return verified
    }

    private func transform(_ bytes: Data, opening: Bool) -> Data? {
        guard let key = encryptionKey, !bytes.isEmpty, bytes.count <= 32 * 1024 * 1024 else {
            return nil
        }
        let capacity = opening ? bytes.count : bytes.count + 44
        var output = Data(count: capacity)
        var length = 0
        let status: Int32 = bytes.withUnsafeBytes { source in
            key.withUnsafeBytes { secret in
                output.withUnsafeMutableBytes { destination in
                    guard let inputPtr = source.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let keyPtr = secret.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let outputPtr = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    if opening {
                        return magnistraPrivateOpen(inputPtr, bytes.count, keyPtr,
                                                    outputPtr, capacity, &length)
                    }
                    return magnistraPrivateSeal(inputPtr, bytes.count, keyPtr,
                                                outputPtr, capacity, &length)
                }
            }
        }
        guard status == 0 && length > 0 && length <= capacity else { return nil }
        return output.subdata(in: 0..<length)
    }
    private func seal(_ bytes: Data) -> Data? { return transform(bytes, opening: false) }
    private func open(_ bytes: Data) -> Data? { return transform(bytes, opening: true) }

    @discardableResult
    private func saveVerified(_ bytes: Data, at path: String) -> Bool {
        guard ready, let encrypted = seal(bytes),
              (encrypted as NSData).write(toFile: path, atomically: true),
              let saved = FileManager.default.contents(atPath: path),
              let recovered = open(saved), recovered == bytes else { return false }
        let protect: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? FileManager.default.setAttributes(protect, ofItemAtPath: path)
        return true
    }
    @discardableResult
    private func writePreferences() -> Bool {
        guard let bytes = try? PropertyListSerialization.data(fromPropertyList: entries,
                              format: .binary, options: 0) else { return false }
        return saveVerified(bytes, at: prefsPath)
    }

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready && encryptionKey != nil
    }

    func string(forKey key: String) -> String? {
        return object(forKey: key) as? String
    }
    func dictionary(forKey key: String) -> [String: Any]? {
        return object(forKey: key) as? [String: Any]
    }

    func stringArray(forKey key: String) -> [String]? {
        return object(forKey: key) as? [String]
    }

    func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ready ? entries : [:]
    }
    func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }

        return ready ? entries[key] : nil
    }
    func integer(forKey key: String) -> Int {
        if let number = object(forKey: key) as? NSNumber { return number.intValue }
        return 0
    }
    func bool(forKey key: String) -> Bool {
        if let number = object(forKey: key) as? NSNumber { return number.boolValue }
        return false
    }
    func set(_ value: Any, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        guard ready else { return }
        let old = entries[key]
        entries[key] = value
        if !writePreferences() {
            if let old = old { entries[key] = old } else { entries.removeValue(forKey: key) }
        }
    }
    func removeObject(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        let old = entries.removeValue(forKey: key)
        if ready && !writePreferences(), let old = old { entries[key] = old; return }

    }
    @discardableResult
    func synchronize() -> Bool { return isReady }

    func megolmContents(legacyPath: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard ready, FileManager.default.fileExists(atPath: megolmPath),
              let encrypted = FileManager.default.contents(atPath: megolmPath) else {
            return nil
        }
        return open(encrypted)
    }
    @discardableResult
    func saveMegolm(_ bytes: Data, legacyPath: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return saveVerified(bytes, at: megolmPath)
    }
    func deleteMegolm(legacyPath: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(atPath: megolmPath)
    }
}
