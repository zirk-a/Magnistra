// Overview: Direct thread: recording and sending outgoing voice messages.
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

extension MagnistraDirectThreadViewController {


    func magnistraVoiceDiscardIcon() -> UIImage? {
        let size = CGSize(width: 28.0, height: 28.0)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(UIColor(
            red: 0.176, green: 0.312, blue: 0.448, alpha: 1.0
        ).cgColor)
        context.fillEllipse(in: CGRect(x: 1.0, y: 1.0, width: 26.0, height: 26.0))
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.3)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 10.0, y: 10.0))
        context.addLine(to: CGPoint(x: 18.0, y: 18.0))
        context.move(to: CGPoint(x: 18.0, y: 10.0))
        context.addLine(to: CGPoint(x: 10.0, y: 18.0))
        context.strokePath()
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    func magnistraEnterVoiceMode() {
        guard !sending && !outgoingVoiceMode else { return }
        if !keepKeyboardDuringVoice { messageView.resignFirstResponder() }
        outgoingVoiceMode = true
        outgoingVoiceReady = false
        if !keepKeyboardDuringVoice { messageView.isHidden = true }
        messagePlaceholder.isHidden = true
        voiceStatusLabel.isHidden = true
        magnistraVoiceToggleButton.isHidden = false
        magnistraVoiceToggleButton.setTitle("Start", for: .normal)
        magnistraVoiceToggleButton.accessibilityLabel = "Start voice recording"
        attachButton.setTitle("", for: .normal)
        attachButton.setImage(magnistraVoiceDiscardIcon(), for: .normal)
        attachButton.accessibilityLabel = "Discard voice message"
        sendButton.setTitle("Send", for: .normal)
        sendButton.isEnabled = false
    }

    @objc func magnistraVoiceToggleTapped() {
        guard outgoingVoiceMode && !sending else { return }
        if outgoingVoiceRecorder != nil {
            stopOutgoingVoiceRecording()
            return
        }
        if outgoingVoiceReady {
            if let oldFile = outgoingVoiceURL {
                try? FileManager.default.removeItem(at: oldFile)
            }
            outgoingVoiceURL = nil
            outgoingVoiceReady = false
            sendButton.isEnabled = false
        }
        beginOutgoingVoiceRecording()
    }

    func beginOutgoingVoiceRecording() {
        guard
            !sending,
            outgoingVoiceMode,
            outgoingVoiceRecorder == nil
        else {
            return
        }

        let url =
            URL(
                fileURLWithPath:
                    NSTemporaryDirectory() +
                    "magnistra-direct-voice-" +
                    String(
                        Int64(
                            Date()
                                .timeIntervalSince1970 *
                            1000.0
                        )
                    ) +
                    (magnistraDirectIsMatrix ? ".m4a" : ".wav")
            )

        try?
            FileManager.default
                .removeItem(
                    at:
                        url
                )

        let settings: [String: Any]
        if magnistraDirectIsMatrix {

            settings = [
                AVFormatIDKey: 1633772320,
                AVSampleRateKey: 22050.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32000
            ]
        } else {

            settings = [
                AVFormatIDKey: 1819304813,
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        }

        do {
            let session =
                AVAudioSession
                    .sharedInstance()

            try session.setCategory(
                .record
            )

            try session.setActive(
                true
            )

            let recorder =
                try AVAudioRecorder(
                    url:
                        url,
                    settings:
                        settings
                )

            recorder.isMeteringEnabled = true

            recorder.prepareToRecord()

            guard
                recorder.record()
            else {
                throw NSError(
                    domain:
                        "MagnistraDirect",
                    code:
                        6940,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Audio recording did not start."
                    ]
                )
            }

            outgoingVoiceRecorder =
                recorder

            outgoingVoiceURL =
                url

            outgoingVoiceMode =
                true

            outgoingVoiceReady =
                false

            magnistraRecordedVoiceLevels.removeAll(keepingCapacity: true)

            outgoingVoiceStartedAt = Date()

            if !keepKeyboardDuringVoice {
                messageView.isHidden = true
            }

            messagePlaceholder.isHidden =
                true

            voiceStatusLabel.isHidden = true
            magnistraVoiceToggleButton.setTitle("Stop 0:00", for: .normal)
            magnistraVoiceToggleButton.accessibilityLabel = "Stop voice recording"
            sendButton.setTitle("Send", for: .normal)
            sendButton.isEnabled = false

            outgoingVoiceTimer?
                .invalidate()

            outgoingVoiceTimer =
                Timer.scheduledTimer(
                    timeInterval:
                        0.20,
                    target:
                        self,
                    selector:
                        #selector(
                            outgoingVoiceTimerTick
                        ),
                    userInfo:
                        nil,
                    repeats:
                        true
                )
        } catch {
            restoreDirectAudioSession()

            try?
                FileManager.default
                    .removeItem(
                        at:
                            url
                    )

            showDirectOutboundError(
                error.localizedDescription
            )
        }
    }

    @objc func outgoingVoiceTimerTick() {
        if let recorder = outgoingVoiceRecorder, recorder.isRecording {
            recorder.updateMeters()
            let decibels = Double(recorder.averagePower(forChannel: 0))
            let normalized = max(0.0, min(1.0, (decibels + 60.0) / 60.0))

            magnistraRecordedVoiceLevels.append(Double(Int(normalized * 100.0)) / 100.0)
        }

        guard
            outgoingVoiceMode,
            outgoingVoiceRecorder != nil,
            let started =
                outgoingVoiceStartedAt
        else {
            return
        }

        let seconds =
            max(
                0,
                Int(
                    Date()
                        .timeIntervalSince(
                            started
                        )
                )
            )

        magnistraVoiceToggleButton.setTitle(
            String(format: "Stop %d:%02d", seconds / 60, seconds % 60),
            for: .normal
        )
        voiceStatusLabel.text =
            String(
                format:
                    "Recording %d:%02d",
                seconds / 60,
                seconds % 60
            )

        if seconds >= 60 {
            stopOutgoingVoiceRecording()
        }
    }

    func outgoingVoiceSendTapped() {
        guard outgoingVoiceRecorder == nil else { return }

        guard
            outgoingVoiceReady,
            let url =
                outgoingVoiceURL
        else {
            return
        }

        sendDirectPreparedAttachment(
            fileURL:
                url,
            fileName:
                "voice.m4a",
            mimeType:
                "audio/mp4",
            voiceClip:
                true,
            kindName:
                "voice message"
        )
    }

    func stopOutgoingVoiceRecording() {
        outgoingVoiceTimer?
            .invalidate()

        outgoingVoiceTimer =
            nil

        outgoingVoiceRecorder?
            .stop()

        outgoingVoiceRecorder =
            nil

        restoreDirectAudioSession()

        let seconds =
            max(
                0,
                Int(
                    outgoingVoiceStartedAt
                        .map {
                            Date()
                                .timeIntervalSince(
                                    $0
                                )
                        } ??
                    0.0
                )
            )

        voiceDurationMS = seconds * 1000
        outgoingVoiceStartedAt =
            nil

        outgoingVoiceReady =
            outgoingVoiceURL != nil

        voiceStatusLabel.text =
            String(
                format:
                    "Voice %d:%02d",
                seconds / 60,
                seconds % 60
            )

        magnistraVoiceToggleButton.setTitle("Start Again", for: .normal)
        magnistraVoiceToggleButton.accessibilityLabel = "Record voice again"

        sendButton.setTitle(
            "Send",
            for:
                .normal
        )

        sendButton.isEnabled =
            outgoingVoiceReady
    }

    func cancelOutgoingVoiceMode(
        deleteFile:
            Bool
    ) {
        outgoingVoiceTimer?
            .invalidate()

        outgoingVoiceTimer =
            nil

        outgoingVoiceRecorder?
            .stop()

        outgoingVoiceRecorder =
            nil

        restoreDirectAudioSession()

        if
            deleteFile,
            let url =
                outgoingVoiceURL
        {
            try?
                FileManager.default
                    .removeItem(
                        at:
                            url
                    )
        }

        outgoingVoiceURL =
            nil

        voiceDurationMS = 0
        outgoingVoiceStartedAt =
            nil

        outgoingVoiceMode =
            false

        outgoingVoiceReady =
            false

        voiceStatusLabel.isHidden =
            true

        voiceStatusLabel.text =
            nil

        messageView.isHidden =
            false

        messagePlaceholder.isHidden =
            !messageView.text.isEmpty

        magnistraVoiceToggleButton.isHidden = true
        magnistraVoiceToggleButton.setTitle("Start", for: .normal)
        attachButton.setImage(nil, for: .normal)
        attachButton.accessibilityLabel = "Add attachment"

        attachButton.setTitle(
            "+",
            for:
                .normal
        )

        sendButton.setTitle(
            "Send",
            for:
                .normal
        )

        let clean =
            messageView.text
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        sendButton.isEnabled =
            !clean.isEmpty

        sendButton.alpha =
            1.0
    }

    func restoreDirectAudioSession() {
        do {
            let session =
                AVAudioSession
                    .sharedInstance()

            try session.setCategory(
                .playback
            )

            try session.setActive(
                true
            )
        } catch {
        }
    }
}
