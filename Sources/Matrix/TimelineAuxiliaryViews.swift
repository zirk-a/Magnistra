// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Image confirmation screen and text file viewer.
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



class ImageConfirmVC: UIViewController {

    let image: UIImage
    private let onSend: (UIImage) -> Void
    private var imageView: UIImageView!

    private var sent = false

    init(image: UIImage, onSend: @escaping (UIImage) -> Void) {
        self.image = image
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
        title = "Send Photo"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView = UIImageView(frame: view.bounds)
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        view.addSubview(imageView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Send", style: .done,
                                                            target: self, action: #selector(sendTapped))
    }

    @objc private func sendTapped() {
        guard !sent else { return }
        sent = true
        onSend(image)
        navigationController?.popViewController(animated: true)
    }
}

class TextFileViewerVC: UIViewController {

    static let maxBytes = 512 * 1024

    private let path: String

    init(path: String, filename: String) {
        self.path = path
        super.init(nibName: nil, bundle: nil)
        title = filename
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let textView = UITextView(frame: view.bounds)
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isEditable = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.text = TextFileViewerVC.readText(path: path)
        view.addSubview(textView)
    }

    private static func readText(path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            return "Couldn't read this file."
        }
        let truncated = data.count > maxBytes
        let slice = truncated ? data.subdata(in: 0..<maxBytes) : data

        let text = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1)
            ?? ""
        if text.isEmpty { return "This file has no readable text." }
        return truncated ? text + "\n\n\u{2026} (truncated)" : text
    }
}