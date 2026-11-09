// Overview: Direct thread: message composer bar (text, photo, sticker, mic and camera buttons) and the voice-hold gesture.
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


    func composerIcon(_ name: String) -> UIImage? {
        return UIImage(named: "MGComposer" + name)
    }

    func setupComposer() {

        composerBar.isOpaque = false
        composerBar.backgroundColor = UIColor.clear
        composerBar.clipsToBounds = true

        composerFadeLayer.colors = [UIColor.white.withAlphaComponent(0.0).cgColor,
                                   UIColor.white.withAlphaComponent(1.0).cgColor,
                                   UIColor.white.withAlphaComponent(1.0).cgColor]

        composerFadeLayer.isOpaque = false
        composerFadeLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        composerFadeLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        composerFadeLayer.locations = [NSNumber(value: 0.0), NSNumber(value: 0.5),
                                      NSNumber(value: 1.0)]

        composerBar.layer.insertSublayer(composerFadeLayer, at: 0)
        composerBar.layer.shadowOpacity = 0.0
        composerTopBorder.isHidden = true
        attachButton.isHidden = true
        messageFieldShell.backgroundColor = UIColor.white
        messageFieldShell.layer.cornerRadius = 23.0
        messageFieldShell.layer.borderWidth = 0.85
        messageFieldShell.layer.borderColor = UIColor(white: 0.85, alpha: 1.0).cgColor
        messageFieldShell.clipsToBounds = true
        messageView.font = UIFont.systemFont(ofSize: 16.0)
        messageView.textColor = UIColor.black
        messagePlaceholder.font = UIFont.systemFont(ofSize: 16.0)
        messagePlaceholder.textColor = UIColor(white: 0.59, alpha: 1.0)
        for (button,name) in [(composerMicButton,"Mic"),(composerPhotoButton,"Photo"),(composerStickerButton,"Sticker")] {
            button.backgroundColor = UIColor.clear
            button.setImage(composerIcon(name), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.imageEdgeInsets = UIEdgeInsets(top: 1.5, left: 1.5, bottom: 1.5, right: 1.5)
            button.accessibilityLabel = name == "Mic" ? "Hold to record voice message" : (name == "Photo" ? "Photo library" : "Stickers")
            composerBar.addSubview(button)
        }
        composerCameraButton.setImage(composerIcon("Camera"), for: .normal)
        composerCameraButton.backgroundColor = UIColor.clear
        composerCameraButton.imageView?.contentMode = .scaleAspectFit
        composerCameraButton.accessibilityLabel = "Take photo"
        composerCameraButton.addTarget(self, action: #selector(composerTakePhoto), for: .touchUpInside)
        composerBar.addSubview(composerCameraButton)
        composerPhotoButton.addTarget(self, action: #selector(composerPickPhoto), for: .touchUpInside)
        composerStickerButton.addTarget(self, action: #selector(composerPickSticker), for: .touchUpInside)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(composerHoldVoice(_:)))
        press.minimumPressDuration = 0.12
        press.allowableMovement = 500.0
        press.cancelsTouchesInView = true
        composerMicButton.addGestureRecognizer(press)
        voiceHoldGesture = press
        sendButton.setTitle("", for: .normal)
        sendButton.setImage(composerIcon("Send"), for: .normal)
        sendButton.imageView?.contentMode = .scaleAspectFit
        sendButton.imageEdgeInsets = UIEdgeInsets(top: 10.5, left: 9.0, bottom: 7.5, right: 9.0)
        sendButton.backgroundColor = UIColor(red: 0.286, green: 0.35, blue: 0.98, alpha: 1.0)
        sendButton.layer.borderWidth = 0
        sendButton.layer.cornerRadius = 20.0

        voiceRecordBand.backgroundColor = UIColor(red: 0.286, green: 0.35, blue: 0.98, alpha: 1.0)
        voiceRecordBand.layer.cornerRadius = 23.0
        voiceRecordBand.clipsToBounds = true
        voiceRecordBand.isUserInteractionEnabled = false
        voiceRecordBand.isHidden = true
        composerBar.addSubview(voiceRecordBand)
        voiceTrashDisk.backgroundColor = UIColor.white
        voiceTrashDisk.layer.cornerRadius = 18.0
        voiceTrashDisk.clipsToBounds = true
        voiceRecordBand.addSubview(voiceTrashDisk)
        voiceTrashIcon.contentMode = .scaleAspectFit
        voiceTrashIcon.image = composerIcon("Trash")
        voiceTrashDisk.addSubview(voiceTrashIcon)
        voiceDurationLabel.backgroundColor = UIColor.clear
        voiceDurationLabel.textColor = UIColor.white
        voiceDurationLabel.font = UIFont.boldSystemFont(ofSize: 12.0)
        voiceDurationLabel.textAlignment = .right
        voiceRecordBand.addSubview(voiceDurationLabel)
        for _ in 0..<42 {
            let dot = UIView()
            dot.backgroundColor = UIColor.white
            dot.layer.cornerRadius = 1.1
            dot.isHidden = true
            voiceRecordBand.addSubview(dot)
            voiceRecordingDots.append(dot)
        }
        layoutComposer()
    }

    func layoutComposerFade() {
        guard composerBar.superview != nil else { return }
        composerFadeLayer.frame = composerBar.bounds
    }

    func layoutComposer() {
        guard composerBar.superview != nil else { return }
        let width = composerBar.bounds.width
        let height = composerBar.bounds.height
        guard width > 75 && height > 15 else { return }
        layoutComposerFade()
        let inset: CGFloat = 6.0

        let h: CGFloat = max(46.0, height - 4.0)
        let y: CGFloat = (height - h) / 2.0
        messageFieldShell.frame = CGRect(x: inset, y: y, width: width - inset * 2.0, height: h)
        messageFieldShell.layer.cornerRadius = min(23.0, h / 2.0)
        let textPresent = !messageView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        composerMicButton.isHidden = textPresent
        composerPhotoButton.isHidden = textPresent
        composerStickerButton.isHidden = textPresent
        sendButton.isHidden = !textPresent
        sendButton.setTitle("", for: .normal)
        let right = width - inset - 8.0
        let iconSide: CGFloat = 32.0
        let gap: CGFloat = 3.0

        let iconBottomY = y + h - 7.0
        composerStickerButton.frame = CGRect(x: right - iconSide, y: iconBottomY-iconSide, width: iconSide, height: iconSide)
        composerPhotoButton.frame = CGRect(x: right - iconSide*2-gap, y: iconBottomY-iconSide, width: iconSide, height: iconSide)
        composerMicButton.frame = CGRect(x: right - iconSide*3-gap*2, y: iconBottomY-iconSide, width: iconSide, height: iconSide)

        let sendSide: CGFloat = 36.0
        sendButton.frame = CGRect(x: width - inset - 5.0 - sendSide,
                                  y: y + h - 5.0 - sendSide,
                                  width: sendSide, height: sendSide)
        sendButton.layer.cornerRadius = sendSide / 2.0
        let rightLimit = textPresent ? sendButton.frame.minX : composerMicButton.frame.minX

        let controlSide: CGFloat = 36.0
        composerCameraButton.frame = CGRect(x: inset + 5.0,
                                  y: y + h - 5.0 - controlSide,
                                  width: controlSide, height: controlSide)
        composerCameraButton.isHidden = isRecordingVoice

        let textX: CGFloat = 51.0
        let editableWidth = max(38.0, rightLimit - (inset + textX) - 6.0)
        messageView.frame = CGRect(x: textX, y: 4.0, width: editableWidth,
                                   height: max(38.0, h-8.0))

        messagePlaceholder.frame = CGRect(x: textX + 9.0, y: (h-21.0)/2.0,
                                          width: max(10.0, editableWidth-11.0), height: 21.0)
        voiceStatusLabel.isHidden = true
        magnistraVoiceToggleButton.isHidden = true
        attachButton.isHidden = true
        voiceRecordBand.frame = messageFieldShell.frame
        voiceRecordBand.layer.cornerRadius = h/2.0
        voiceTrashDisk.frame = CGRect(x: 5, y: (h-36)/2.0, width: 36, height: 36)
        voiceTrashIcon.frame = CGRect(x: 8, y: 8, width: 20, height: 20)
        voiceDurationLabel.frame = CGRect(x: voiceRecordBand.bounds.width-60, y: 0, width: 48, height: h)
        if isRecordingVoice { renderVoiceRecordingDots() }
    }

    @objc func composerTakePhoto() {
        guard !isRecordingVoice && !sending else { return }
        if magnistraDirectIsMatrix {
            chooseMatrixCameraMode()
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              let types = UIImagePickerController.availableMediaTypes(for: .camera),
              types.contains("public.image") else {
            showDirectOutboundError("Camera unavailable on this device.")
            return
        }
        messageView.resignFirstResponder()
        pendingPickerMode = "public.image"
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    @objc func composerPickPhoto() {
        guard !isRecordingVoice && !sending else { return }
        messageView.resignFirstResponder()

        presentDirectPicker(mediaType: "public.image")
    }

    @objc func composerPickSticker() {
        guard !isRecordingVoice && !sending else { return }
        messageView.resignFirstResponder()
        if magnistraDirectIsMatrix { magnistraOpenSavedStickerLibrary() }
        else { magnistraOpenInstagramCatalog() }
    }

    @objc func composerHoldVoice(_ press: UILongPressGestureRecognizer) {
        let point = press.location(in: composerBar)
        switch press.state {
        case .began:
            guard !sending && !magnistraWebSending && !isRecordingVoice &&
                messageView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            voiceCancelArmed = false
            keepKeyboardDuringVoice = messageView.isFirstResponder

            magnistraEnterVoiceMode()
            beginOutgoingVoiceRecording()
            guard outgoingVoiceRecorder != nil else {
                cancelOutgoingVoiceMode(deleteFile: true)
                keepKeyboardDuringVoice = false
                return
            }
            isRecordingVoice = true
            voiceRecordingStartDate = Date()
            voiceRecordBand.isHidden = false
            voiceDurationLabel.text = "0:00"
            layoutComposer()
            voiceRefreshTimer?.invalidate()
            voiceRefreshTimer = Timer.scheduledTimer(timeInterval: 0.12, target: self,
                selector: #selector(voiceRecordingTick), userInfo: nil, repeats: true)
            UIView.animate(withDuration: 0.12) { self.voiceRecordBand.alpha = 1.0 }
        case .changed:
            guard isRecordingVoice else { return }
            let deleteRegion = point.x < 78.0
            voiceCancelArmed = deleteRegion

            voiceTrashDisk.backgroundColor = deleteRegion
                ? UIColor(red: 0.96, green: 0.18, blue: 0.20, alpha: 1.0)
                : UIColor.white
            voiceTrashIcon.image = composerIcon(deleteRegion ? "TrashWhite" : "Trash")
        case .ended:
            guard isRecordingVoice else { return }
            endVoiceRecording(cancel: voiceCancelArmed || point.x < 78.0)
        case .cancelled, .failed:
            if isRecordingVoice { endVoiceRecording(cancel: true) }
        default: break
        }
    }

    @objc func voiceRecordingTick() {
        guard isRecordingVoice else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(voiceRecordingStartDate ?? Date())))
        voiceDurationLabel.text = String(format: "%d:%02d", seconds/60, seconds%60)
        renderVoiceRecordingDots()
        if seconds >= 60 { endVoiceRecording(cancel: false) }
    }

    func renderVoiceRecordingDots() {
        let samples = magnistraRecordedVoiceLevels
        let maxDots = min(voiceRecordingDots.count, max(0, Int((voiceRecordBand.bounds.width-118.0)/4.0)))
        let visible = min(samples.count, maxDots)
        for index in voiceRecordingDots.indices {
            let dot = voiceRecordingDots[index]
            if index < visible {
                let actual = CGFloat(max(0.0,min(1.0,samples[max(0,samples.count-visible+index)])))
                let height = max(4.0, 4.0 + actual * 14.0)
                dot.frame = CGRect(x: 50.0 + CGFloat(index) * 4.0, y: (voiceRecordBand.bounds.height-height)/2.0, width: 2.0, height: height)
                dot.layer.cornerRadius = 1.0
                dot.isHidden = false
            } else { dot.isHidden = true }
        }
    }

    func endVoiceRecording(cancel: Bool) {
        guard isRecordingVoice else { return }
        voiceRefreshTimer?.invalidate()
        voiceRefreshTimer = nil
        isRecordingVoice = false
        voiceCancelArmed = false
        voiceRecordBand.isHidden = true
        voiceRecordBand.alpha = 1.0
        voiceRecordBand.backgroundColor = UIColor(red: 0.286, green: 0.35, blue: 0.98, alpha: 1.0)
        voiceTrashDisk.backgroundColor = UIColor.white
        voiceTrashIcon.image = composerIcon("Trash")

        if outgoingVoiceRecorder != nil { stopOutgoingVoiceRecording() }
        if cancel { cancelOutgoingVoiceMode(deleteFile: true) }
        else if outgoingVoiceReady { outgoingVoiceSendTapped() }
        keepKeyboardDuringVoice = false

        layoutComposer()
    }

    func matrixSenderNameForMessage(_ index: Int) -> String? {
        guard index >= 0 && index < messages.count else { return nil }
        let current = messages[index]
        guard !current.isOutgoing else { return nil }
        if magnistraDirectIsMatrix {
            guard matrixGroupConfirmed else { return nil }
        } else {
            guard summary.isGroupConversation else { return nil }
        }
        let id = current.senderID
        guard !id.isEmpty else { return nil }
        if index > 0 {
            let previous = messages[index - 1]

            if !previous.isOutgoing && previous.senderID == id &&
                !magnistraDirectShowsDate(at: index) { return nil }
        }
        let name = magnistraDirectIsMatrix
            ? (matrixMemberNames[id] ?? id)
            : (current.senderName.isEmpty ? id : current.senderName)
        return name.isEmpty ? nil : name
    }

    func loadMatrixGroupNames() {
        guard magnistraDirectIsMatrix else { return }
        MagnistraMatrixDirectBackend.shared.loadRoomParticipants(roomId: summary.threadFBID) {
            [weak self] result, error in
            OperationQueue.main.addOperation { [weak self] in
                guard let owner = self, error == nil, let people = result else { return }
                var names: [String: String] = [:]
                var nonBot = 0
                let ownID = MagnistraMatrixAccountStore.userId
                for member in people {
                    guard let id = member["id"], !id.isEmpty else { continue }
                    let name = member["name"] ?? id
                    names[id] = name
                    let lowered = (id + " " + name).lowercased()
                    let isBridgeBot = lowered.contains("bridgebot") ||
                        lowered.contains("bridge bot") || lowered.contains("instagram bot")
                    if id != ownID && !isBridgeBot { nonBot += 1 }
                }
                owner.matrixMemberNames = names
                owner.matrixGroupConfirmed = nonBot >= 2
                owner.cachedRowHeights.removeAll(keepingCapacity: true)
                owner.tableView.reloadData()
            }
        }
    }
}
