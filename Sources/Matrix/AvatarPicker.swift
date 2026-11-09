// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix: picks and uploads an avatar image.
import Foundation
import UIKit

final class AvatarPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    typealias Completion = (String?, UIImage?, Error?) -> Void

    private let client: MatrixAPIClient
    private weak var presenter: UIViewController?
    private var completion: Completion?

    private static let maxDimension: CGFloat = 800

    init(client: MatrixAPIClient) {
        self.client = client
        super.init()
    }

    func start(from presenter: UIViewController, anchor: UIView, completion: @escaping Completion) {
        self.presenter = presenter
        self.completion = completion

        let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
#if LEGACY_TARGET
        let sheet = UIActionSheet()
        sheet.title = "Photo"
        if hasCamera { sheet.addButton(withTitle: "Take Photo") }
        sheet.addButton(withTitle: "Choose from Library")
        sheet.addButton(withTitle: "Cancel")
        sheet.cancelButtonIndex = sheet.numberOfButtons - 1
        sheet.delegate = self
        sheet.show(in: anchor)
#else
        let sheet = UIAlertController(title: "Photo", message: nil, preferredStyle: .actionSheet)
        if hasCamera {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentPicker(source: .camera)
            })
        }
        sheet.addAction(UIAlertAction(title: "Choose from Library", style: .default) { [weak self] _ in
            self?.presentPicker(source: .photoLibrary)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finish(nil, nil, nil)
        })
        sheet.popoverPresentationController?.sourceView = anchor
        presenter.present(sheet, animated: true)
#endif
    }

    fileprivate func presentPicker(source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    fileprivate func finish(_ mxc: String?, _ image: UIImage?, _ error: Error?) {
        let done = completion
        completion = nil
        done?(mxc, image, error)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { finish(nil, nil, nil); return }
        upload(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(nil, nil, nil)
    }

    private func upload(_ image: UIImage) {
        let scaled = AvatarPicker.downscale(image, maxDimension: AvatarPicker.maxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.8) else { finish(nil, nil, nil); return }

        let filename = "magnistra-avatar-\(Int64(Date().timeIntervalSince1970 * 1000)).jpg"
        client.uploadMedia(data: data, filename: filename, mimeType: "image/jpeg") { [weak self] json, error in
            guard let self = self else { return }
            guard let mxc = json?["content_uri"] as? String, !mxc.isEmpty else {
                self.finish(nil, nil, error)
                return
            }

            MediaCache.shared.storeThumbnail(scaled, mxc: mxc,
                                             width: AvatarView.thumbPx, height: AvatarView.thumbPx)
            MediaCache.shared.storeFull(scaled, mxc: mxc)
            self.finish(mxc, scaled, nil)
        }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension, longEdge > 0 else { return image }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? image
    }
}

extension AvatarPicker: UIActionSheetDelegate {
    func actionSheet(_ actionSheet: UIActionSheet, clickedButtonAt buttonIndex: Int) {
        if buttonIndex == actionSheet.cancelButtonIndex { finish(nil, nil, nil); return }

        let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
        if hasCamera && buttonIndex == 0 { presentPicker(source: .camera) }
        else { presentPicker(source: .photoLibrary) }
    }
}
