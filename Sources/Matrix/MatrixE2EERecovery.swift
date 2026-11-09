// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Recovery helpers: decrypting own outbound events and normalizing media content.
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
    var magnistraOutboundReady: Bool {
        return api != nil && userId != nil && deviceId != nil && identity != nil
    }
    static func magnistraNormalizedMediaContent(_ content: [String:Any]) -> [String:Any] {
        var value=content
        registerEncryptedMedia(in:&value)
        return value
    }
    func magnistraDecryptOwnOutboundEvent(_ event: [String:Any]) -> [String:Any]? {
        return decryptRoomEvent(event)
    }
}