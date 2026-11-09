// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Migration helper that preserves the existing Matrix device state.
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



enum MatrixDeviceStateMigration {
    static func preserveExistingDevice() -> Bool {
        guard let uid = MatrixSession.userId, let did = MatrixSession.deviceId,
              !uid.isEmpty, !did.isEmpty else { return false }
        let defaults = MagnistraPrivateState.shared
        let keys = defaults.dictionaryRepresentation()
        let pairs: [(String,String)] = [
            ("magnistra_matrix.verify.\(uid).\(did).", "magnistra.verify.\(uid).\(did)."),
            ("magnistra_matrix.e2ee.\(uid).\(did).", "magnistra.e2ee.\(uid).\(did).")
        ]
        var updates: [(String, Any)] = []
        for (oldPrefix,newPrefix) in pairs {
            for (key,val) in keys where key.hasPrefix(oldPrefix) {
                let target = newPrefix + String(key.dropFirst(oldPrefix.count))
                if let existing = keys[target] {

                    if !((existing as AnyObject).isEqual(val)) {
                        NSLog("MATRIX_DEVICE_STATE=CONFLICT; NO_REKEY; target=REDACTED")
                        return false
                    }
                } else {
                    updates.append((target,val))
                }
            }
        }
        for (key,value) in updates { defaults.set(value,forKey:key) }
        if !updates.isEmpty { defaults.synchronize() }
        NSLog("MATRIX_DEVICE_STATE=PRESERVED copied_fields=%ld", updates.count)
        return true
    }
}