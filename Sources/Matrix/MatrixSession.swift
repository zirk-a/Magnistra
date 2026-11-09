// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix session state, device identity and verification transaction models.
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



@_silgen_name("vdz5_r3_abi_version")
func vdz5_r3_abi_version() -> UInt32
@_silgen_name("vdz5_r3_bridge_selftest")
func vdz5_r3_bridge_selftest() -> UInt32
@_silgen_name("vdz5_r3_ffi_selftest")
func vdz5_r3_ffi_selftest() -> UInt32

enum MagnistraVodozemac {
    static let status: String = {
        guard vdz5_r3_abi_version() == 0x00030000 else { return "ABI_VERSION_MISMATCH" }
        guard vdz5_r3_bridge_selftest() == 0 else { return "RUST_CRYPTO_SELFTEST_FAILED" }
        guard vdz5_r3_ffi_selftest() == 0 else { return "C_BRIDGE_SELFTEST_FAILED" }
        return "NATIVE_STATIC_BRIDGE_READY"
    }()
}

struct MatrixSession {
    static var homeserverURL: String? {
        get { return MagnistraMatrixAccountStore.homeserverURL }
        set { MagnistraMatrixAccountStore.homeserverURL = newValue }
    }

    static var accessToken: String? {
        get { return MagnistraMatrixAccountStore.accessToken }
        set { MagnistraMatrixAccountStore.accessToken = newValue }
    }

    static var deviceId: String? {
        get { return MagnistraMatrixAccountStore.deviceId }
        set { MagnistraMatrixAccountStore.deviceId = newValue }
    }

    static var userId: String? {
        get { return MagnistraMatrixAccountStore.userId }
        set { MagnistraMatrixAccountStore.userId = newValue }
    }

    static var isConfigured: Bool {
        return homeserverURL != nil &&
               accessToken != nil &&
               userId != nil
    }

    static func clear() {
        MagnistraMatrixAccountStore.clearSession()
    }

    static func makeAPIClient() -> MatrixAPIClient {
        return MatrixAPIClient(
            homeserverBaseURL:
                homeserverURL ?? "",
            accessToken:
                accessToken
        )
    }
}

struct MagnistraDeviceIdentity {
    let edPrivate: [UInt8]
    let edPublic: [UInt8]
    let curvePrivate: [UInt8]
    let curvePublic: [UInt8]
}

final class MagnistraVerificationTransaction {
    let id: String
    let remoteUser: String
    let remoteDevice: String
    var startContent: [String: Any]?
    var ephemeralPrivate: [UInt8] = []
    var ephemeralPublic: [UInt8] = []
    var ephemeralPublicB64 = ""
    var remoteEphemeralB64: String?
    var sharedSecret: [UInt8]?
    var remoteEd25519: String?
    var pendingRemoteMac: [String: Any]?
    var localConfirmed = false
    var localMacSent = false
    var remoteMacVerified = false
    var doneSent = false

    init(id: String, remoteUser: String, remoteDevice: String) {
        self.id = id
        self.remoteUser = remoteUser
        self.remoteDevice = remoteDevice
    }
}

typealias MagnistraMatrixBackendSession = MatrixSession
typealias MagnistraMatrixDeviceVerificationManager = DeviceVerificationManager
typealias MagnistraMatrixE2EEManager = MatrixE2EEManager
typealias MagnistraMatrixEncryptedMediaRecord = MagnistraEncryptedMediaRecord
typealias MagnistraMatrixPreparedMedia = MagnistraPreparedMedia
