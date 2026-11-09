// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: text view, image picker, action sheet and audio delegate callbacks.
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



extension RoomTimelineVC: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {

        let isEmpty = textView.text.isEmpty
        if placeholderLabel.isHidden == isEmpty { placeholderLabel.isHidden = !isEmpty }
        adjustInputHeight()
        sendTypingIfNeeded(isEmpty: isEmpty)
    }
}

extension RoomTimelineVC: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {

        if let url = info[.mediaURL] as? URL {
            picker.dismiss(animated: true)
            uploadAndSendVideo(atPath: url.path)
            return
        }
        guard let image = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true)
            return
        }

        picker.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            let confirm = ImageConfirmVC(image: image) { [weak self] picked in
                self?.uploadAndSendImage(picked)
            }
            self.navigationController?.pushViewController(confirm, animated: true)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

#if LEGACY_TARGET
extension RoomTimelineVC: UIActionSheetDelegate {
    func actionSheet(_ actionSheet: UIActionSheet, clickedButtonAt buttonIndex: Int) {
        if actionSheet.tag == reactionSheetTag {
            guard buttonIndex != actionSheet.cancelButtonIndex,
                  let key = actionSheet.buttonTitle(at: buttonIndex),
                  let target = pendingReactionEventId else { return }
            toggleReaction(target: target, key: key)
            return
        }
        if actionSheet.tag == deleteSheetTag {
            if buttonIndex == actionSheet.destructiveButtonIndex { deleteConfirmed() }
            return
        }
        if actionSheet.tag == pendingSheetTag {
            if buttonIndex == actionSheet.destructiveButtonIndex {
                discardPending()
            } else if buttonIndex != actionSheet.cancelButtonIndex {
                retryPending()
            }
            return
        }

        switch actionSheet.buttonTitle(at: buttonIndex) {
        case "Take Photo": presentPicker(source: .camera)
        case "Choose from Library": presentPicker(source: .photoLibrary)
        case "Stickers": presentStickerLibrary()
        case "Save Video":
            if let sticker = pendingSaveSticker, sticker.semanticGIF {
                saveSemanticGIFVideoToPhotos(mxc: sticker.mxc)
                pendingSaveSticker = nil
            }
        case "WhatsApp Sticker":
            if let sticker = pendingSaveSticker, sticker.semanticGIF {
                MagnistraStickerLibrary.shared.saveSemanticGIFAsSticker(
                    mxc: sticker.mxc,
                    target: "whatsapp",
                    width: sticker.width,
                    height: sticker.height
                )
                pendingSaveSticker = nil
            }
        case "Telegram Sticker":
            if let sticker = pendingSaveSticker, sticker.semanticGIF {
                MagnistraStickerLibrary.shared.saveSemanticGIFAsSticker(
                    mxc: sticker.mxc,
                    target: "telegram",
                    width: sticker.width,
                    height: sticker.height
                )
                pendingSaveSticker = nil
            }
        case "Cancel":
            if pendingSaveSticker?.semanticGIF == true {
                pendingSaveSticker = nil
            }
        case "Voice Message": enterVoiceMode()
        default: break
        }
    }
}
#endif

extension RoomTimelineVC: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            voiceHasRecording = false
            sendButton.isEnabled = false
            updateVoiceRecordButton()
        }
    }
}

extension RoomTimelineVC: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopAudioPlayback()
        refreshAudioCells()
    }
}

extension RoomTimelineVC: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }

    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        docController = nil
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        docController = nil
    }
}