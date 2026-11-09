// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: keyboard dismissal and voice proximity routing.
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

extension RoomTimelineVC {


    func installTimelineKeyboardDismissTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(timelineBackgroundTapped(_:)))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
    }

    @objc func timelineBackgroundTapped(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            messageField.resignFirstResponder()
        }
    }

    func setVoiceDefaultSpeaker(_ speaker: Bool) {
        _ = magnistra_audio_set_default_speaker(speaker ? 1 : 0)
    }

    func applyVoiceProximityRoute() {
        setVoiceDefaultSpeaker(!UIDevice.current.proximityState)
    }

    func startVoiceProximityMonitoring() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        if device.isProximityMonitoringEnabled {
            applyVoiceProximityRoute()
        } else {
            setVoiceDefaultSpeaker(true)
        }
    }

    func stopVoiceProximityMonitoring() {
        let device = UIDevice.current
        if device.isProximityMonitoringEnabled {
            device.isProximityMonitoringEnabled = false
        }
        setVoiceDefaultSpeaker(false)
    }

    @objc func voiceProximityChanged(_ notification: Notification) {
        guard audioPlayer?.isPlaying == true else { return }
        applyVoiceProximityRoute()
    }

    func startVideoPlaybackSession() {
        stopVoiceProximityMonitoring()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)
        try? session.setCategory(.playback)
        try? session.setActive(true)
    }

    func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(voiceProximityChanged(_:)),
            name: UIDevice.proximityStateDidChangeNotification, object: UIDevice.current)
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        keyboardHeight = keyboardFrame.height
        UIView.animate(withDuration: duration) {
            self.layoutInputBar()
        }
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        keyboardHeight = 0
        UIView.animate(withDuration: duration) {
            self.layoutInputBar()
        }
    }
}
