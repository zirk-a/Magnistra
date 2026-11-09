// Overview: Direct thread: attach menu, photo/video picker and camera flow (including Matrix camera media).
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


    @objc func attachTapped() {
        guard !sending
        else {
            return
        }

        if outgoingVoiceMode {
            cancelOutgoingVoiceMode(
                deleteFile:
                    true
            )

            return
        }

        messageView.resignFirstResponder()

        let sheet =
            UIActionSheet()

        sheet.delegate =
            self

        sheet.title =
            "Attach"

        sheet.addButton(
            withTitle:
                magnistraDirectIsMatrix ? "Photos & Videos" : "Photo"
        )

        if magnistraDirectIsMatrix {
            sheet.addButton(withTitle: "Camera")
        }
        if magnistraDirectIsMatrix {
            sheet.addButton(withTitle: "Video")
        }

        sheet.addButton(
            withTitle:
                "Voice Message"
        )

        sheet.addButton(
            withTitle:
                "Sticker"
        )

        let cancel =
            sheet.addButton(
                withTitle:
                    "Cancel"
            )

        sheet.cancelButtonIndex =
            cancel

        sheet.show(
            in:
                view
        )
    }

    func actionSheet(
        _ actionSheet:
            UIActionSheet,
        clickedButtonAt
            buttonIndex:
                Int
    ) {
        if actionSheet.tag == 99727 {
            guard buttonIndex != actionSheet.cancelButtonIndex,
                  let choice = actionSheet.buttonTitle(at: buttonIndex) else { return }
            if choice == "Take Photo" {
                presentMatrixCameraMedia("public.image")
            } else if choice == "Record Video" {
                presentMatrixCameraMedia("public.movie")
            }
            return
        }
        if actionSheet.tag == 98532 {
            if buttonIndex != actionSheet.cancelButtonIndex &&
               actionSheet.buttonTitle(at: buttonIndex) == "Save Sticker" {
                magnistraConfirmSaveSticker()
            } else {
                magnistraPendingStickerSaveIndex = -1
            }
            return
        }

        if actionSheet.tag == 97501 {
            magnistraWebMediaSheetTapped(actionSheet, clickedButtonAt: buttonIndex)
            return
        }

        guard
            buttonIndex !=
                actionSheet.cancelButtonIndex,
            let title =
                actionSheet.buttonTitle(
                    at:
                        buttonIndex
                )
        else {
            return
        }

        switch title {
        case "Photo", "Photos & Videos":
            presentDirectPicker(
                mediaType:
                    "public.image"
            )

        case "Video":
            guard magnistraDirectIsMatrix else { return }
            presentDirectPicker(mediaType: "public.movie")

        case "Camera":
            if magnistraDirectIsMatrix {
                chooseMatrixCameraMode()
            }

        case "Sticker":
            if magnistraDirectIsMatrix {
                magnistraOpenSavedStickerLibrary()
            } else {
                magnistraOpenInstagramCatalog()
            }

        case "Voice Message":
            magnistraEnterVoiceMode()

        default:
            break
        }
    }

    func suspendPickerAppearance() {
        guard !nativePickerAppearanceSuspended else { return }
        nativePickerAppearanceSuspended = true
        let items = UIBarButtonItem.appearance()
        items.setBackgroundImage(nil, for: .normal, barMetrics: .default)
        items.setBackgroundImage(nil, for: .highlighted, barMetrics: .default)
        items.setBackButtonBackgroundImage(nil, for: .normal, barMetrics: .default)
        items.setBackButtonBackgroundImage(nil, for: .highlighted, barMetrics: .default)
    }

    func chooseMatrixCameraMode() {
        guard magnistraDirectIsMatrix, !sending else { return }
        let choices = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              choices.contains("public.image") || choices.contains("public.movie") else {
            showDirectOutboundError("Camera unavailable on this device.")
            return
        }
        messageView.resignFirstResponder()
        let sheet = UIActionSheet()
        sheet.tag = 99727
        sheet.delegate = self
        sheet.title = "Camera"
        if choices.contains("public.image") { sheet.addButton(withTitle: "Take Photo") }
        if choices.contains("public.movie") { sheet.addButton(withTitle: "Record Video") }
        sheet.cancelButtonIndex = sheet.addButton(withTitle: "Cancel")
        sheet.show(in: view)
    }

    func presentMatrixCameraMedia(_ mediaType: String) {
        guard magnistraDirectIsMatrix,
              UIImagePickerController.isSourceTypeAvailable(.camera),
              (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(mediaType)
        else {
            showDirectOutboundError("This camera mode is unavailable on this device.")
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.mediaTypes = [mediaType]
        picker.allowsEditing = false
        if mediaType == "public.movie" {
            picker.videoQuality = .typeMedium
            picker.videoMaximumDuration = 30.0
            picker.cameraCaptureMode = .video
        }
        pendingPickerMode = "matrix.capture"
        present(picker, animated: true)
    }

    func presentMatrixCamera() {
        guard magnistraDirectIsMatrix else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showDirectOutboundError("Camera unavailable on this device.")
            return
        }
        let supported = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
        let allowed = ["public.image", "public.movie"].filter { supported.contains($0) }
        guard !allowed.isEmpty else {
            showDirectOutboundError("Camera capture is unavailable on this device.")
            return
        }
        pendingPickerMode = "matrix.capture"
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.mediaTypes = allowed
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 30.0
        if allowed.contains("public.movie") {
            picker.cameraCaptureMode = .video
        }
        present(picker, animated: true)
    }

    func ui5MaintainNativePhotoLibraryStatus(
        _ navigationController: UINavigationController
    ) {
        guard let picker = navigationController as? UIImagePickerController,
              picker.sourceType == .photoLibrary else { return }
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        guard major == 5 || major == 6 else { return }
        guard let root = tabBarController as? RootViewController else { return }
        let app = UIApplication.shared
        if app.statusBarStyle.rawValue != 1 {
            app.statusBarStyle = UIStatusBarStyle(rawValue: 1) ?? .default
        }
        root.showExistingStatusAbovePhotoPicker(true)
        MagnistraLegacyClearStatusBarRenderer.shared.apply(on: root.view)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        ui5MaintainNativePhotoLibraryStatus(navigationController)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        ui5MaintainNativePhotoLibraryStatus(navigationController)
    }

    func nativePhotoPickerAnimated(
        _ picker: UIImagePickerController
    ) -> Bool {
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        return !(major == 5 || major == 6) || picker.sourceType != .photoLibrary
    }

    func presentDirectPicker(
        mediaType:
            String
    ) {
        guard
            UIImagePickerController
                .isSourceTypeAvailable(
                    .photoLibrary
                )
        else {
            showDirectOutboundError(
                "Photo library unavailable."
            )

            return
        }

        let available =
            UIImagePickerController
                .availableMediaTypes(
                    for:
                        .photoLibrary
                ) ??
            []

        guard
            available.contains(
                mediaType
            )
        else {
            showDirectOutboundError(
                mediaType ==
                    "public.movie"
                    ? "No video picker is available on this device."
                    : "No photo picker is available on this device."
            )

            return
        }

        pendingPickerMode =
            mediaType

        suspendPickerAppearance()
        let picker =
            UIImagePickerController()

        picker.delegate =
            self

        picker.sourceType =
            .photoLibrary

        if magnistraDirectIsMatrix {

            let allowed = ["public.image", "public.movie"].filter { available.contains($0) }
            picker.mediaTypes = allowed
        } else {
            picker.mediaTypes = [mediaType]
        }

        if magnistraDirectIsMatrix || mediaType == "public.movie" {
            picker.videoQuality =
                .typeMedium

            picker.videoMaximumDuration =
                30.0
        }

        present(
            picker,
            animated:
                nativePhotoPickerAnimated(picker),
            completion: { [weak self] in
                guard mediaType == "public.image" else { return }
                (self?.tabBarController as? RootViewController)?
                    .showExistingStatusAbovePhotoPicker(true)
            }
        )
    }

    func imagePickerControllerDidCancel(
        _ picker:
            UIImagePickerController
    ) {
        if picker.view.tag == 97503 {
            magnistraWebMediaPickerDidCancel(picker)
            return
        }

        pendingPickerMode =
            ""

        picker.dismiss(
            animated:
                nativePhotoPickerAnimated(picker)
        )
    }

    func imagePickerController(
        _ picker:
            UIImagePickerController,
        didFinishPickingMediaWithInfo
            info:
                [
                    UIImagePickerController.InfoKey:
                        Any
                ]
    ) {
        if picker.view.tag == 97503 {
            magnistraWebMediaPickerDidFinish(picker, didFinishPickingMediaWithInfo: info)
            return
        }

        let mode = magnistraDirectIsMatrix
            ? ((info[.mediaType] as? String) ?? pendingPickerMode)
            : pendingPickerMode

        pendingPickerMode =
            ""

        if
            mode ==
                "public.image"
        {
            guard
                let image =
                    info[
                        .originalImage
                    ] as?
                        UIImage,
                let url =
                    prepareDirectPhoto(
                        image
                    )
            else {
                picker.dismiss(
                    animated:
                        nativePhotoPickerAnimated(picker)
                )

                showDirectOutboundError(
                    "Couldn’t prepare that photo."
                )

                return
            }

            picker.dismiss(
                animated:
                    nativePhotoPickerAnimated(picker)
            ) {
                [weak self] in

                self?
                    .sendDirectPreparedAttachment(
                        fileURL:
                            url,
                        fileName:
                            "photo.jpg",
                        mimeType:
                            "image/jpeg",
                        voiceClip:
                            false,
                        kindName:
                            "photo"
                    )
            }

            return
        }

        if
            mode ==
                "public.movie"
        {
            guard
                let sourceURL =
                    info[
                        .mediaURL
                    ] as?
                        URL
            else {
                picker.dismiss(
                    animated:
                        nativePhotoPickerAnimated(picker)
                )

                showDirectOutboundError(
                    "Couldn’t open that video."
                )

                return
            }

            if magnistraDirectIsMatrix {
                sendMatrixSelectedVideo(sourceURL, picker: picker)
                return
            }
            picker.dismiss(
                animated:
                    nativePhotoPickerAnimated(picker)
            ) {
                [weak self] in

                self?
                    .prepareDirectVideo(
                        sourceURL
                    )
            }

            return
        }

        picker.dismiss(
            animated:
                nativePhotoPickerAnimated(picker)
        )
    }

    func sendMatrixSelectedVideo(
        _ sourceURL: URL, picker: UIImagePickerController
    ) {
        guard sourceURL.isFileURL else {
            picker.dismiss(animated: nativePhotoPickerAnimated(picker))
            showDirectOutboundError("This video is not available as a local file.")
            return
        }
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "mov" || ext == "mp4" else {
            picker.dismiss(animated: nativePhotoPickerAnimated(picker))
            showDirectOutboundError("Unsupported video file format.")
            return
        }
        let name = "magnistra-matrix-video-" + UUID().uuidString + "." + ext
        let destinationPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        let destination = URL(fileURLWithPath: destinationPath)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            picker.dismiss(animated: nativePhotoPickerAnimated(picker))
            showDirectOutboundError("Couldn’t prepare this video: " + error.localizedDescription)
            return
        }
        let mime = ext == "mov" ? "video/quicktime" : "video/mp4"
        picker.dismiss(animated: nativePhotoPickerAnimated(picker)) { [weak self] in
            self?.sendDirectPreparedAttachment(
                fileURL: destination,
                fileName: "video." + ext,
                mimeType: mime,
                voiceClip: false,
                kindName: "video"
            )
        }
    }

    func prepareDirectPhoto(
        _ image:
            UIImage
    ) -> URL? {
        let longest =
            max(
                image.size.width,
                image.size.height
            )

        let scale =
            longest > 1080.0
                ? 1080.0 /
                    longest
                : 1.0

        let target =
            CGSize(
                width:
                    max(
                        1.0,
                        floor(
                            image.size.width *
                            scale
                        )
                    ),
                height:
                    max(
                        1.0,
                        floor(
                            image.size.height *
                            scale
                        )
                    )
            )

        UIGraphicsBeginImageContextWithOptions(
            target,
            true,
            1.0
        )

        image.draw(
            in:
                CGRect(
                    origin:
                        CGPoint.zero,
                    size:
                        target
                )
        )

        let prepared =
            UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        guard
            let finalImage =
                prepared,
            let data =
                finalImage.jpegData(
                    compressionQuality:
                        0.86
                )
        else {
            return nil
        }

        let url =
            URL(
                fileURLWithPath:
                    NSTemporaryDirectory() +
                    "magnistra-direct-photo-" +
                    String(
                        Int64(
                            Date()
                                .timeIntervalSince1970 *
                            1000.0
                        )
                    ) +
                    ".jpg"
            )

        do {
            try data.write(
                to:
                    url,
                options:
                    .atomic
            )

            return url
        } catch {
            return nil
        }
    }

    func prepareDirectVideo(
        _ sourceURL:
            URL
    ) {
        guard
            let exporter =
                AVAssetExportSession(
                    asset:
                        AVURLAsset(
                            url:
                                sourceURL
                        ),
                    presetName:
                        AVAssetExportPresetMediumQuality
                )
        else {
            showDirectOutboundError(
                "Couldn’t prepare that video."
            )

            return
        }

        let outputURL =
            URL(
                fileURLWithPath:
                    NSTemporaryDirectory() +
                    "magnistra-direct-video-" +
                    String(
                        Int64(
                            Date()
                                .timeIntervalSince1970 *
                            1000.0
                        )
                    ) +
                    ".mp4"
            )

        try?
            FileManager.default
                .removeItem(
                    at:
                        outputURL
                )

        exporter.outputURL =
            outputURL

        exporter.outputFileType =
            .mp4

        exporter.shouldOptimizeForNetworkUse =
            true

        attachButton.isEnabled =
            false

        exporter.exportAsynchronously {
            [weak self] in

            OperationQueue.main
                .addOperation {
                    guard
                        let self =
                            self
                    else {
                        return
                    }

                    self.attachButton.isEnabled =
                        true

                    if
                        exporter.status ==
                            .completed
                    {
                        self
                            .sendDirectPreparedAttachment(
                                fileURL:
                                    outputURL,
                                fileName:
                                    "video.mp4",
                                mimeType:
                                    "video/mp4",
                                voiceClip:
                                    false,
                                kindName:
                                    "video"
                            )
                    } else {
                        try?
                            FileManager.default
                                .removeItem(
                                    at:
                                        outputURL
                                )

                        self
                            .showDirectOutboundError(
                                "Couldn’t convert that video to MP4."
                            )
                    }
                }
        }
    }
}
