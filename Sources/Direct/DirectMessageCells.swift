// Overview: Direct thread: zoomable photo view and full-screen photo viewer.
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



final class MagnistraDirectZoomingPhotoView: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()
    private var loadedPhoto: UIImage?
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        minimumZoomScale = 1.0
        maximumZoomScale = 4.0
        photo.contentMode = .scaleAspectFit
        photo.backgroundColor = UIColor.black
        addSubview(photo)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ image: UIImage) {
        loadedPhoto = image
        photo.image = image
        fitPhotoToBounds()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { fitPhotoToBounds() }
        centerPhoto()
    }

    private func fitPhotoToBounds() {
        lastSize = bounds.size
        guard let image = loadedPhoto, image.size.width > 0.0,
              image.size.height > 0.0, bounds.width > 0.0,
              bounds.height > 0.0 else { return }
        let fit = min(bounds.width / image.size.width,
                      bounds.height / image.size.height)
        setZoomScale(1.0, animated: false)
        photo.frame = CGRect(x: 0.0, y: 0.0,
                             width: image.size.width * fit,
                             height: image.size.height * fit)
        contentSize = photo.bounds.size
        centerPhoto()
    }

    private func centerPhoto() {
        let x = max((bounds.width - contentSize.width) / 2.0, 0.0)
        let y = max((bounds.height - contentSize.height) / 2.0, 0.0)
        photo.center = CGPoint(x: contentSize.width / 2.0 + x,
                               y: contentSize.height / 2.0 + y)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return photo }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }
}

final class MagnistraDirectPhotoViewController:
    UIViewController
{
    let remoteURL:
        String

    private let stableKey:
        String

    private let loadQueue:
        OperationQueue =
            {
                let queue =
                    OperationQueue()

                queue.maxConcurrentOperationCount =
                    1

                return queue
            }()

    private let zoomPhoto = MagnistraDirectZoomingPhotoView(frame: .zero)

    init(
        remoteURL:
            String,
        stableKey:
            String
    ) {
        self.remoteURL =
            remoteURL

        self.stableKey =
            stableKey

        super.init(
            nibName:
                nil,
            bundle:
                nil
        )

        title =
            "Photo"
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor =
            UIColor.black

        zoomPhoto.frame = view.bounds
        zoomPhoto.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(zoomPhoto)

        loadQueue.addOperation {
            [weak self] in

            guard
                let self =
                    self,
                let path =
                    MagnistraHomeService
                        .materializeFeedImage(
                            url:
                                self.remoteURL,
                            stableKey:
                                self.stableKey,
                            isAvatar:
                                false
                        ),
                let image =
                    UIImage(
                        contentsOfFile:
                            path
                    )
            else {
                return
            }

            OperationQueue.main
                .addOperation {
                    [weak self] in

                    self?.zoomPhoto.show(image)
                }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        zoomPhoto.frame = view.bounds
    }
}

@_silgen_name("magnistra_direct_decode_ogg_opus_to_wav")
func magnistraDirectOggToWav(_ input: UnsafePointer<CChar>,
                                      _ output: UnsafePointer<CChar>) -> Int32

func magnistraDirectLegacyPlayableAudio(_ bytes: Data) -> Data? {
    let raw = bytes as NSData
    if raw.length < 4 { return nil }
    let magic = raw.bytes.assumingMemoryBound(to: UInt8.self)
    if magic[0] != 79 || magic[1] != 103 || magic[2] != 103 || magic[3] != 83 {
        return bytes
    }

    let base = (NSTemporaryDirectory() as NSString)
    let ogg = base.appendingPathComponent("magnistra-direct-playback.ogg")
    let wav = base.appendingPathComponent("magnistra-direct-playback.wav")
    defer {
        try? FileManager.default.removeItem(atPath: ogg)
        try? FileManager.default.removeItem(atPath: wav)
    }
    guard raw.write(toFile: ogg, atomically: true) else { return nil }
    let result = ogg.withCString { input in
        wav.withCString { output in magnistraDirectOggToWav(input, output) }
    }
    if result != 0 { return nil }
    return NSData(contentsOfFile: wav) as Data?
}

