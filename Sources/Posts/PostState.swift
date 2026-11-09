// Overview: Post cell follow-button state.
import UIKit
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import Security
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration

extension MagnistraPostCell {

    static func resetTransientFollowConfirmation() {
        transientFollowingMediaIDs.removeAll()
    }

    func updatePostFollowButton(_ post: MagnistraRealPost, following: Bool) {
        followButton.setImage(nil, for: .normal)
        let onThisPost = following && MagnistraPostCell.transientFollowingMediaIDs.contains(post.mediaID)
        if following && !onThisPost {
            followButton.setTitle(nil, for: .normal)
            followButton.isHidden = true
            followButton.accessibilityLabel = "Following"
        } else {
            followButton.isHidden = false
            followButton.setTitle(onThisPost ? "Following" : "Follow", for: .normal)
            followButton.setTitleColor(onThisPost
                ? UIColor(red: 0.21, green: 0.60, blue: 0.18, alpha: 1.0)
                : MagnistraPostCell.magnistraBlue, for: .normal)
            followButton.accessibilityLabel = onThisPost ? "Following" : "Follow"
        }

        setNeedsLayout()
    }

    static func loadingPostColor(mediaID: String) -> UIColor {

        var hash: UInt32 = 2166136261
        for byte in mediaID.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        let index = Int(hash % UInt32(loadingPostPalette.count))
        return loadingPostPalette[index]
    }
}
