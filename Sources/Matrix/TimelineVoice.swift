// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: voice message recording.
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


    func enterVoiceMode() {
        guard inputMode == .text else { return }

        endReply()
        inputMode = .voice
        messageField.resignFirstResponder()
        voiceHasRecording = false
        voiceIsRecording = false
        voiceRecordSeconds = 0
        updateVoiceRecordButton()
        sendButton.isEnabled = false
        currentFieldHeight = inputMinHeight
        layoutInputBar()
    }

    func exitVoiceMode() {
        cleanUpRecording(deleteFile: true)
        inputMode = .text
        sendButton.isEnabled = true
        sendButton.setTitle("Send", for: .normal)
        placeholderLabel.isHidden = !(messageField.text ?? "").isEmpty
        layoutInputBar()
    }

    @objc func voiceCancelTapped() {
        exitVoiceMode()
    }

    @objc func voiceRecordTapped() {
        if voiceIsRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        stopAudioPlayback()
        stopVoiceProximityMonitoring()

        let session = AVAudioSession.sharedInstance()
        let permSel = NSSelectorFromString("requestRecordPermission:")
        if session.responds(to: permSel) {
            session.requestRecordPermission { [weak self] granted in

                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.beginRecording()
                    } else {
                        self.showSendError(MatrixAPIClient.MatrixError(errcode: "M_FORBIDDEN",
                            error: "Microphone access denied. Enable it in Settings > Privacy."))
                    }
                }
            }
        } else {
            beginRecording()
        }
    }

    func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord)
            try session.setActive(true)
        } catch {
            showSendError(MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                      error: "Could not start audio session"))
            return
        }

        let name = "magnistra-voice-\(Int64(Date().timeIntervalSince1970 * 1000)).m4a"

        let dir = NSTemporaryDirectory() as NSString
        let url = URL(fileURLWithPath: dir.appendingPathComponent(name))
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()
            audioRecorder = recorder
            voiceRecordingURL = url
            voiceIsRecording = true
            voiceRecordSeconds = 0
            voiceRecordTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                                    selector: #selector(voiceRecordTick),
                                                    userInfo: nil, repeats: true)
            updateVoiceRecordButton()
        } catch {
            showSendError(MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                                                      error: "Could not start recording"))
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        voiceRecordTimer?.invalidate()
        voiceRecordTimer = nil
        voiceIsRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        voiceHasRecording = voiceRecordSeconds > 0
        sendButton.isEnabled = voiceHasRecording
        updateVoiceRecordButton()
    }

    @objc func voiceRecordTick() {
        voiceRecordSeconds += 1
        updateVoiceRecordButton()
    }

    func updateVoiceRecordButton() {
        guard voiceRecordButton != nil else { return }
        let title: String
        if voiceIsRecording {
            title = "\u{25A0} Stop \u{00B7} \(voiceDurationString(voiceRecordSeconds))"
        } else if voiceHasRecording {
            title = "\u{25CF} Re-record \u{00B7} \(voiceDurationString(voiceRecordSeconds))"
        } else {
            title = "\u{25CF} Record"
        }
        voiceRecordButton.setTitle(title, for: .normal)
    }

    func voiceDurationString(_ seconds: Int) -> String {
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func cleanUpRecording(deleteFile: Bool) {
        if voiceIsRecording {
            audioRecorder?.stop()
        }
        voiceRecordTimer?.invalidate()
        voiceRecordTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        if deleteFile, let url = voiceRecordingURL {
            try? FileManager.default.removeItem(atPath: url.path)
        }
        audioRecorder = nil
        voiceRecordingURL = nil
        voiceIsRecording = false
        voiceHasRecording = false
        voiceRecordSeconds = 0
    }

    func sendVoiceMessage() {
        guard voiceHasRecording, !voiceIsRecording, !isSending,
              let url = voiceRecordingURL,
              let data = FileManager.default.contents(atPath: url.path) else { return }
        let seconds = voiceRecordSeconds
        let filename = url.lastPathComponent
        let size = data.count
        setSending(true)

        MatrixE2EEManager.shared.prepareOutboundMedia(roomId: room.roomId, inputPath: url.path) {
            [weak self] prepared, prepareError in
            guard let self = self else { return }
            guard let prepared = prepared else {
                self.setSending(false)
                self.showSendError(prepareError ?? MatrixAPIClient.MatrixError(
                    errcode: "M_UNKNOWN", error: "Encrypted voice preparation failed"))
                return
            }
            let uploadMime = prepared.encrypted == nil ? "audio/mp4" : "application/octet-stream"
            self.client.uploadMediaFile(path: prepared.path, filename: filename, mimeType: uploadMime,
                                        progress: nil) { [weak self] json, error in
                guard let self = self else { return }
                if prepared.removeWhenDone { try? FileManager.default.removeItem(atPath: prepared.path) }
                guard let mxc = json?["content_uri"] as? String else {
                    self.setSending(false)
                    self.showSendError(error ?? MatrixAPIClient.MatrixError(
                        errcode: "M_UNKNOWN", error: "Upload returned no content_uri"))
                    return
                }
                if let encrypted = prepared.encrypted {
                    MatrixE2EEManager.registerEncryptedMedia(encrypted, mxc: mxc)
                }
                MediaCache.shared.storeAudioFile(fromPath: url.path, mxc: mxc)
                self.sendAudioEvent(mxc: mxc, size: size, seconds: seconds,
                                    filename: filename, encrypted: prepared.encrypted)
            }
        }
    }

    func sendAudioEvent(mxc: String, size: Int, seconds: Int, filename: String,
                                encrypted: MagnistraEncryptedMediaRecord?) {
        let info: [String: Any] = ["mimetype": "audio/mp4",
                                    "size": size,
                                    "duration": seconds * 1000]
        var body: [String: Any] = ["msgtype": "m.audio",
                                    "body": "Voice message \u{00B7} \(voiceDurationString(seconds))",
                                    "info": info]
        if let encrypted = encrypted {
            body["file"] = encrypted.descriptor(url: mxc)
        } else {
            body["url"] = mxc
        }
        sendRoomEvent(type: "m.room.message", content: body, txnId: newTxnId(),
                      knownEncrypted: encrypted != nil) { [weak self] _, error in
            guard let self = self else { return }
            self.setSending(false)
            if let error = error {
                self.showSendError(error)
            } else {
                self.exitVoiceMode()
            }
        }
    }

    func toggleAudio(mxc: String, durationMs: Int) {
        if playingAudioMxc == mxc, let player = audioPlayer {
            if player.isPlaying {
                player.pause()
                stopAudioProgressTimer()
                stopVoiceProximityMonitoring()
                try? AVAudioSession.sharedInstance().setActive(false)
            } else {
                startPlaybackSession()
                player.play()
                startAudioProgressTimer()
            }
            refreshAudioCells()
            return
        }

        stopAudioPlayback()
        MediaCache.shared.loadAudioPath(mxc: mxc) { [weak self] path in
            guard let self = self else { return }
            guard let path = path else {
                self.showSendError(MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                    error: "Could not load voice message"))
                return
            }
            self.startPlaybackSession()
            do {
                let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                player.delegate = self
                player.prepareToPlay()
                self.audioPlayer = player
                self.playingAudioMxc = mxc
                player.play()
                self.startAudioProgressTimer()
                self.refreshAudioCells()
            } catch {
                self.showSendError(MatrixAPIClient.MatrixError(errcode: "M_UNKNOWN",
                    error: "Could not play voice message"))
            }
        }
    }

    func startPlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)
        try? session.setCategory(.playAndRecord)
        setVoiceDefaultSpeaker(true)
        try? session.setActive(true)
        startVoiceProximityMonitoring()
    }

    func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingAudioMxc = nil
        stopAudioProgressTimer()
        stopVoiceProximityMonitoring()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func startAudioProgressTimer() {
        stopAudioProgressTimer()
        audioProgressTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self,
                                                  selector: #selector(audioProgressTick),
                                                  userInfo: nil, repeats: true)
    }

    func stopAudioProgressTimer() {
        audioProgressTimer?.invalidate()
        audioProgressTimer = nil
    }

    @objc func audioProgressTick() {
        refreshAudioCells()
    }

    func refreshAudioCells() {
        let current = audioPlayer?.currentTime ?? 0
        let duration = audioPlayer?.duration ?? 0
        let playing = audioPlayer?.isPlaying ?? false
        for cell in tableView.visibleCells {
            guard let audioCell = cell as? AudioEventCell else { continue }
            if audioCell.mxc == playingAudioMxc {
                audioCell.setPlaybackState(playing: playing, currentTime: current, duration: duration)
            } else {
                audioCell.setPlaybackState(playing: false, currentTime: 0, duration: audioCell.declaredDuration)
            }
        }
    }

    func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }
}
