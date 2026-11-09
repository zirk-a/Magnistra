// Overview: Direct thread: media message cells (photo, animated GIF preview, loading preview).
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



final class MagnistraDirectLoadingPreviewView: UIImageView {
    var showsAnimatedPlaceholder: Bool = false {
        didSet { updateAnimatedPlaceholder() }
    }

    var magnistraOnDecodedImage: ((UIImage) -> Void)?
    override var image: UIImage? {
        didSet {
            updateAnimatedPlaceholder()
            if let actual = image { magnistraOnDecodedImage?(actual) }
        }
    }
    func updateAnimatedPlaceholder() {
        if !showsAnimatedPlaceholder {

            backgroundColor = UIColor(white: 0.92, alpha: 1.0)
        } else if image == nil {
            backgroundColor = UIColor(white: 0.86, alpha: 1.0)
        } else {
            backgroundColor = UIColor.clear
        }
    }
}

class MagnistraDirectPreviewCell:
    MagnistraDirectMessageCell
{
    let previewView =
        MagnistraDirectLoadingPreviewView()

    var chatThumbnailCache: NSCache<NSString, UIImage>?

    var representedMessageID =
        ""

    private var pendingImage:
        UIImage?

    override init(
        style:
            UITableViewCell.CellStyle,
        reuseIdentifier:
            String?
    ) {
        super.init(
            style: style,
            reuseIdentifier:
                reuseIdentifier
        )

        previewView.backgroundColor =
            UIColor(
                white:
                    0.92,
                alpha:
                    1.0
            )

        previewView.contentMode =
            .scaleAspectFill

        previewView.clipsToBounds =
            true

        bubbleView.addSubview(
            previewView
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    func configurePreview(
        _ message:
            MagnistraDirectMessage
    ) {
        outgoing =
            message.isOutgoing

        representedMessageID =
            message.messageID

        previewView.image =
            nil

        pendingImage =
            nil

        let chatImageKey = (message.messageID + "|" + (message.previewURL ?? "")) as NSString
        if let ready = chatThumbnailCache?.object(forKey: chatImageKey) {
            previewView.image = ready
            return
        }

        let messageID =
            message.messageID

        MagnistraDirectMessageCell
            .requestPreview(
                message
            ) {
                [weak self] image in

                guard
                    let self =
                        self,
                    self.representedMessageID ==
                        messageID,
                    let image =
                        image
                else {
                    return
                }

                if image.images == nil {
                    let cost = max(1, Int(image.size.width * image.size.height * 4.0))
                    if cost <= 4 * 1024 * 1024 {
                        self.chatThumbnailCache?.setObject(image,
                            forKey: chatImageKey, cost: cost)
                    }
                }

                if
                    MagnistraDirectMessageCell
                        .isPreviewApplicationSuspended()
                {
                    self.pendingImage =
                        image
                } else {
                    self.previewView.image =
                        image
                    self.pendingImage =
                        nil
                }
            }
    }

    override func applyPendingPreviewIfNeeded() {
        guard
            let image =
                pendingImage
        else {
            return
        }

        previewView.image =
            image

        pendingImage =
            nil
    }
}

class MagnistraDirectMediaCell:
    MagnistraDirectPreviewCell
{

    static var magnistraDirectRealGIFRatios: [String: CGFloat] = [:]

    static private(set) var magnistraDirectGIFGeometryVersion = 0
    private var magnistraDirectGIFMessageID = ""
    private var magnistraDirectGIFOnscreenRatio: CGFloat? = nil

    private static func magnistraActualGIFSize(_ ratio: CGFloat,
                                                availableWidth: CGFloat) -> CGSize {

        let actual = max(0.25, min(4.0, ratio))
        let limit = min(196.0, min(max(1.0, availableWidth - 20.0),
                                   availableWidth * 0.68))
        let wide = min(limit, 260.0 * actual)
        return CGSize(width: max(1.0, wide), height: max(1.0, wide / actual))
    }

    private func magnistraDirectDecodedGIFReady(_ image: UIImage) {
        guard directAnimatedLayoutMode == 2,
              !magnistraDirectGIFMessageID.isEmpty,
              image.size.width > 0, image.size.height > 0 else { return }
        let actual = max(0.25, min(4.0, image.size.width / image.size.height))
        if let old = MagnistraDirectMediaCell.magnistraDirectRealGIFRatios[
            magnistraDirectGIFMessageID], abs(old - actual) < 0.015 { return }
        MagnistraDirectMediaCell.magnistraDirectRealGIFRatios[
            magnistraDirectGIFMessageID] = actual
        MagnistraDirectMediaCell.magnistraDirectGIFGeometryVersion += 1
        magnistraDirectGIFOnscreenRatio = actual
        setNeedsLayout()

        var parent: UIView? = self
        while let view = parent {
            if let list = view as? UITableView {
                OperationQueue.main.addOperation { [weak self, weak list] in
                    guard let owner = self, owner.window != nil,
                          owner.directAnimatedLayoutMode == 2,
                          MagnistraDirectMediaCell.magnistraDirectRealGIFRatios[
                             owner.magnistraDirectGIFMessageID] != nil else { return }
                    list?.beginUpdates()
                    list?.endUpdates()
                    owner.setNeedsLayout()
                }
                break
            }
            parent = view.superview
        }
    }

    private var directAnimatedLayoutMode = 0

    private static func directAnimatedModeOfMessage(_ message: MagnistraDirectMessage) -> Int {
        guard message.mediaKind == "photo", message.previewURL != nil else { return 0 }
        let kind = message.contentType.lowercased()

        guard kind.contains("animated") || kind == "sticker" || kind == "gif"
        else { return 0 }
        return kind == "sticker" || message.text == "Sticker" ? 1 : 2
    }

    private static func directAnimatedMediaSize(mode: Int, aspect: CGFloat,
                                                availableWidth: CGFloat) -> CGSize {
        let ratio = max(0.35, min(2.5, aspect))
        if mode == 1 {

            let maxSide = min(112.0, max(1.0, availableWidth - 20.0))
            return ratio >= 1.0
                ? CGSize(width: maxSide, height: maxSide / ratio)
                : CGSize(width: maxSide * ratio, height: maxSide)
        }

        let gifRatio = max(1.50, min(2.40, ratio))
        let width = min(196.0, min(max(1.0, availableWidth - 20.0),
                                  availableWidth * 0.68))
        return CGSize(width: max(1.0, width),
                      height: max(1.0, width / gifRatio))
    }

    let playGlyph =
        MagnistraDirectPlayGlyphView()

    var isVideo =
        false

    var aspect:
        CGFloat =
            1.0

    override init(
        style:
            UITableViewCell.CellStyle,
        reuseIdentifier:
            String?
    ) {
        super.init(
            style: style,
            reuseIdentifier:
                reuseIdentifier
        )

        bubbleView.backgroundColor =
            UIColor.clear

        bubbleView.layer.cornerRadius =
            9.0

        bubbleView.clipsToBounds =
            true

        previewView.layer.cornerRadius =
            9.0

        playGlyph.isHidden =
            true

        bubbleView.addSubview(
            playGlyph
        )
    }

    required init?(
        coder:
            NSCoder
    ) {
        fatalError()
    }

    func configureMedia(
        _ message:
            MagnistraDirectMessage,
        video:
            Bool
    ) {
        directAnimatedLayoutMode = video ? 0 :
            MagnistraDirectMediaCell.directAnimatedModeOfMessage(message)
        magnistraDirectGIFMessageID = message.messageID
        magnistraDirectGIFOnscreenRatio = MagnistraDirectMediaCell
            .magnistraDirectRealGIFRatios[message.messageID]
        if directAnimatedLayoutMode == 2 {
            previewView.magnistraOnDecodedImage = { [weak self] image in
                guard let owner = self else { return }
                owner.magnistraDirectDecodedGIFReady(image)
            }
        } else {
            previewView.magnistraOnDecodedImage = nil
        }
        if directAnimatedLayoutMode == 1 {
            bubbleView.backgroundColor = UIColor.clear
            bubbleView.layer.borderWidth = 0.0
            bubbleView.layer.cornerRadius = 0.0
            bubbleView.clipsToBounds = false
            previewView.backgroundColor = UIColor.clear
            previewView.layer.cornerRadius = 0.0
            previewView.clipsToBounds = false
            previewView.contentMode = .scaleAspectFit
        } else if directAnimatedLayoutMode == 2 {

            bubbleView.backgroundColor = UIColor.clear
            bubbleView.layer.borderWidth = 0.0
            bubbleView.layer.cornerRadius = 0.0
            bubbleView.clipsToBounds = false
            previewView.layer.cornerRadius = 7.0
            previewView.clipsToBounds = true
            previewView.contentMode = .scaleAspectFit
        }

        isVideo =
            video

        aspect =
            CGFloat(
                max(
                    0.35,
                    min(
                        2.5,
                        message.mediaAspectRatio
                    )
                )
            )

        playGlyph.isHidden =
            !video

        configurePreview(
            message
        )

        setNeedsLayout()

        previewView.showsAnimatedPlaceholder = directAnimatedLayoutMode != 0
        if directAnimatedLayoutMode != 0 && previewView.image == nil {
            previewView.backgroundColor = UIColor(white: 0.86, alpha: 1.0)
        }

        if directAnimatedLayoutMode == 2, let ready = previewView.image {
            magnistraDirectDecodedGIFReady(ready)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if directAnimatedLayoutMode != 0 {
            let box: CGSize
            if directAnimatedLayoutMode == 2,
               let resolved = magnistraDirectGIFOnscreenRatio {
                box = MagnistraDirectMediaCell.magnistraActualGIFSize(
                    resolved, availableWidth: bounds.size.width)
            } else {
                box = MagnistraDirectMediaCell.directAnimatedMediaSize(
                    mode: directAnimatedLayoutMode, aspect: aspect,
                    availableWidth: bounds.size.width)
            }
            bubbleView.frame = CGRect(x: alignedX(width: box.width), y: 5.0,
                                      width: box.width, height: box.height)
            previewView.frame = bubbleView.bounds
            previewView.contentMode = .scaleAspectFit
            playGlyph.frame = CGRect.zero
            playGlyph.isHidden = true
            magnistraDirectKeepBubbleInside()
            return
        }

        let mediaWidth =
            min(
                196.0,
                bounds.size.width *
                0.68
            )

        let mediaHeight =
            max(
                100.0,
                min(
                    230.0,
                    mediaWidth /
                    max(
                        0.35,
                        aspect
                    )
                )
            )

        bubbleView.frame =
            CGRect(
                x:
                    alignedX(
                        width:
                            mediaWidth
                    ),
                y: 5.0,
                width:
                    mediaWidth,
                height:
                    mediaHeight
            )

        previewView.frame =
            bubbleView.bounds

        if isVideo {
            let glyph:
                CGFloat =
                    28.0

            playGlyph.frame =
                CGRect(
                    x:
                        floor(
                            (
                                mediaWidth -
                                glyph
                            ) /
                            2.0
                        ),
                    y:
                        floor(
                            (
                                mediaHeight -
                                glyph
                            ) /
                            2.0
                        ),
                    width: glyph,
                    height: glyph
                )
        } else {
            playGlyph.frame =
                CGRect.zero
        }
    }

    static func rowHeight(
        for message:
            MagnistraDirectMessage,
        width:
            CGFloat
    ) -> CGFloat {
        let animatedMode = MagnistraDirectMediaCell.directAnimatedModeOfMessage(message)
        if animatedMode != 0 {
            let box: CGSize
            if animatedMode == 2,
               let resolved = MagnistraDirectMediaCell
                    .magnistraDirectRealGIFRatios[message.messageID] {
                box = MagnistraDirectMediaCell.magnistraActualGIFSize(
                    resolved, availableWidth: width)
            } else {
                box = MagnistraDirectMediaCell.directAnimatedMediaSize(
                    mode: animatedMode, aspect: CGFloat(message.mediaAspectRatio),
                    availableWidth: width)
            }
            return box.height + 10.0
        }

        let mediaWidth =
            min(
                196.0,
                width *
                0.68
            )

        let aspect =
            CGFloat(
                max(
                    0.35,
                    min(
                        2.5,
                        message.mediaAspectRatio
                    )
                )
            )

        let mediaHeight =
            max(
                100.0,
                min(
                    230.0,
                    mediaWidth /
                    aspect
                )
            )

        return
            mediaHeight +
            10.0
    }
}

final class MagnistraDirectPhotoCell:
    MagnistraDirectMediaCell
{
    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        configureMedia(
            message,
            video: false
        )
    }
}

final class MagnistraDirectVideoCell:
    MagnistraDirectMediaCell
{
    override func configure(
        _ message:
            MagnistraDirectMessage
    ) {
        configureMedia(
            message,
            video: true
        )
    }
}