// Overview: Direct thread: attachments for web Direct (photo picker, media sheet, voice recording).
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


    @objc func magnistraWebAttachmentTapped() {
        guard !magnistraDirectIsMatrix, !magnistraWebSending else { return }
        let sheet = UIActionSheet(title: "Send media", delegate: self,
            cancelButtonTitle: "Cancel", destructiveButtonTitle: nil,
            otherButtonTitles: "Photo", "Record voice")
        sheet.tag = 97501
        sheet.show(in: view)
    }

    func magnistraWebMediaSheetTapped(_ actionSheet: UIActionSheet, clickedButtonAt buttonIndex: Int) {
        guard actionSheet.tag == 97501 else { return }
        if buttonIndex == 0 { magnistraWebChoosePhoto() }
        else if buttonIndex == 1 { magnistraWebBeginVoiceRecording() }
    }

    func magnistraWebChoosePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            magnistraWebShowMediaError("Photo library unavailable.")
            return
        }
        suspendPickerAppearance()
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.view.tag = 97503
        picker.delegate = self
        present(picker, animated: nativePhotoPickerAnimated(picker), completion: { [weak self] in
            (self?.tabBarController as? RootViewController)?
                .showExistingStatusAbovePhotoPicker(true)
        })
    }

    func magnistraWebMediaPickerDidFinish(_ picker: UIImagePickerController,
         didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: nativePhotoPickerAnimated(picker), completion: nil)
        guard let original = image,
              let jpeg = original.jpegData(compressionQuality: 0.83) else {
            magnistraWebShowMediaError("Photo could not be prepared.")
            return
        }
        magnistraWebSendAttachment(jpeg, mime: "image/jpeg", filename: "photo.jpg", isVoice: false)
    }

    func magnistraWebMediaPickerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: nativePhotoPickerAnimated(picker), completion: nil)
    }

    func magnistraWebBeginVoiceRecording() {
        guard !magnistraDirectIsMatrix else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord)
            try AVAudioSession.sharedInstance().setActive(true)
            let recordingFile = "magnistra-direct-voice-" + UUID().uuidString + ".m4a"
            let recordingPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(recordingFile)
            let url = URL(fileURLWithPath: recordingPath)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw NSError(domain: "MagnistraVoice", code: 1) }
            magnistraWebRecordingURL = url
            magnistraWebRecorder = recorder
            magnistraWebVoiceWaveform.removeAll()
            magnistraWebMeterTimer = Timer.scheduledTimer(
                timeInterval: 0.12, target: self,
                selector: #selector(magnistraWebSampleMeter), userInfo: nil, repeats: true)
            if !inlineWebVoiceRecording {
                let alert = UIAlertView(title: "Voice message", message: "Recording...",
                    delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Stop & Send")
                alert.tag = 97502
                alert.show()
            }
        } catch {
            magnistraWebShowMediaError("Microphone recording unavailable.")
        }
    }

    @objc func magnistraWebSampleMeter() {
        guard let recorder = magnistraWebRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))
        magnistraWebVoiceWaveform.append(max(0.0, min(1.0, (power + 60.0) / 60.0)))
    }

    func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        guard alertView.tag == 97502 else { return }
        magnistraWebMeterTimer?.invalidate()
        magnistraWebMeterTimer = nil
        let duration = magnistraWebRecorder?.currentTime ?? 0
        magnistraWebRecorder?.stop()
        magnistraWebRecorder = nil
        guard buttonIndex == 1, duration >= 0.4,
              let url = magnistraWebRecordingURL,
              let audio = try? Data(contentsOf: url), !audio.isEmpty else {
            if let url = magnistraWebRecordingURL { try? FileManager.default.removeItem(at: url) }
            magnistraWebRecordingURL = nil
            return
        }
        let samples = magnistraWebVoiceWaveform
        magnistraWebRecordingURL = nil
        try? FileManager.default.removeItem(at: url)
        magnistraWebSendAttachment(audio, mime: "audio/mp4", filename: "voice.m4a",
                                   isVoice: true, waveform: samples)
    }

    func magnistraWebSendAttachment(_ data: Data, mime: String,
        filename: String, isVoice: Bool, waveform: [Double] = []) {
        guard !magnistraDirectIsMatrix, !magnistraWebSending else { return }
        magnistraWebSending = true
        let thread = summary.threadFBID
        loadQueue.addOperation { [weak self] in
            do {
                _ = try MagnistraHomeService.sendDirectWebMedia(
                    threadFBID: thread, data: data, mime: mime,
                    filename: filename, isVoice: isVoice, waveform: waveform)
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.magnistraWebSending = false
                    self.loadThread()
                }
            } catch {
                let description = error.localizedDescription
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self else { return }
                    self.magnistraWebSending = false
                    self.magnistraWebShowMediaError(description)
                }
            }
        }
    }

    func magnistraWebShowMediaError(_ message: String) {
        UIAlertView(title: "Media not sent", message: message,
            delegate: nil, cancelButtonTitle: "OK").show()
    }

func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if magnistraDirectDateRowMessageIndex(indexPath) != nil { return }

        cell.transform = CGAffineTransform.identity
        (tableView.viewWithTag(1300000 + self.magnistraDirectMessageIndex(indexPath)) as? UILabel)?.removeFromSuperview()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === magnistraDirectHorizontalPan,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: tableView)
        return velocity.x < 0.0 && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === magnistraDirectHorizontalPan
    }
}
