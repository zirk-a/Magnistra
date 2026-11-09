// Overview: Post caption layout and measuring.
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

extension MagnistraPostCell {


    static func cachedCaptionLayout(
        post: MagnistraRealPost,
        expanded: Bool,
        width: CGFloat
    ) -> CaptionLayout {
        let key = NSString(string:
            "\(post.mediaID)|\(Int(width.rounded()))|\(expanded)|" +
            "\(post.caption.hashValue)|\(post.username.hashValue)")
        if let box = captionLayoutCache.object(forKey: key) {
            return box.value
        }
        let calculated = captionLayout(
            post: post, expanded: expanded, width: width)
        captionLayoutCache.setObject(
            CaptionLayoutBox(calculated), forKey: key)
        return calculated
    }

    static func measureWidth(
        _ text: String,
        font: UIFont
    ) -> CGFloat {
        let label = UILabel(frame: CGRect.zero)
        label.font = font
        label.numberOfLines = 1
        label.text = text

        return label.sizeThatFits(
            CGSize(
                width: 10000.0,
                height: 100.0
            )
        ).width
    }

    static func measureHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat
    ) -> CGFloat {
        if text.isEmpty {
            return 0.0
        }

        let units = text.utf16.count
        if units > 1024 {
            let columns = max(12, Int(max(1.0, width) / (font.pointSize * 0.52)))
            let lines = min(1000, max(1, (units + columns - 1) / columns))
            return CGFloat(lines) * max(17.0, font.lineHeight)
        }

        let label = UILabel(frame: CGRect.zero)
        label.font = font
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.text = text

        return label.sizeThatFits(
            CGSize(
                width: max(1.0, width),
                height: 10000.0
            )
        ).height
    }

    static func captionLayout(
        post: MagnistraRealPost,
        expanded: Bool,
        width: CGFloat
    ) -> CaptionLayout {
        let bodyFont =
            UIFont.systemFont(
                ofSize: 13.0
            )

        let authorFont =
            UIFont.boldSystemFont(
                ofSize: 13.0
            )

        let contentWidth =
            max(
                40.0,
                width - 20.0
            )

        let authorWidth =
            min(
                measureWidth(
                    post.username,
                    font: authorFont
                ) + 2.0,
                contentWidth * 0.48
            )

        let bulletText = " • "
        let bulletWidth =
            measureWidth(
                bulletText,
                font: bodyFont
            )

        let firstAvailable =
            max(
                24.0,
                contentWidth -
                authorWidth -
                bulletWidth
            )

        let words =
            post.caption
                .components(
                    separatedBy:
                        CharacterSet
                            .whitespacesAndNewlines
                )
                .filter {
                    !$0.isEmpty
                }

        var firstWords: [String] = []
        var restWords: [String] = []

        for word in words {
            if !restWords.isEmpty {
                restWords.append(word)
                continue
            }
            if firstWords.isEmpty {
                firstWords.append(word)
                continue
            }
            let candidate = (firstWords + [word]).joined(separator: " ")
            if measureWidth(candidate, font: bodyFont) <= firstAvailable {
                firstWords.append(word)
            } else {
                restWords.append(word)
            }
        }

        if restWords.isEmpty &&
            firstWords.count < words.count
        {
            restWords =
                Array(
                    words.dropFirst(
                        firstWords.count
                    )
                )
        } else if !restWords.isEmpty {
            let consumed =
                firstWords.count +
                restWords.count

            if consumed < words.count {
                restWords +=
                    Array(
                        words.dropFirst(
                            consumed
                        )
                    )
            }
        }

        let firstLine =
            firstWords.joined(
                separator: " "
            )

        let continuation =
            restWords.joined(
                separator: " "
            )

        let lineHeight =
            max(
                17.0,
                measureHeight(
                    "Ag",
                    font: bodyFont,
                    width:
                        contentWidth
                )
            )

        let fullContinuationHeight =
            measureHeight(
                continuation,
                font: bodyFont,
                width:
                    contentWidth
            )

        let continuationLines =
            fullContinuationHeight <= 0.0
                ? 0
                : Int(
                    ceil(
                        fullContinuationHeight /
                        lineHeight
                    )
                )

        let showToggle =
            continuationLines > 1

        let shownContinuationHeight: CGFloat =
            expanded
                ? fullContinuationHeight
                : min(
                    fullContinuationHeight,
                    lineHeight
                )

        let total =
            max(
                lineHeight,
                lineHeight +
                shownContinuationHeight
            )

        return CaptionLayout(
            authorWidth: authorWidth,
            bulletWidth: bulletWidth,
            firstLine: firstLine,
            continuation: continuation,
            continuationHeight:
                shownContinuationHeight,
            totalHeight: total,
            showToggle: showToggle
        )
    }

    static func mediaBoxHeight(post: MagnistraRealPost, width: CGFloat) -> CGFloat {
        return max(1.0, width)
    }

    static func rowHeight(
        post: MagnistraRealPost,
        expanded: Bool,
        width: CGFloat
    ) -> CGFloat {
        let photoHeight = mediaBoxHeight(post: post, width: width)
        let cacheKey = NSString(string:
            "\(post.mediaID)|\(Int(width.rounded()))|\(Int(photoHeight.rounded()))|\(expanded)|" +
            "\(post.caption.hashValue)|\(post.username.hashValue)|" +
            "\(post.commentCount)|\(post.previewComments.count)")
        if let cached = rowHeightCache.object(forKey: cacheKey) {
            return CGFloat(cached.doubleValue)
        }
        let metrics =
            cachedCaptionLayout(
                post: post,
                expanded: expanded,
                width: width
            )

        let toggleHeight: CGFloat =
            metrics.showToggle
                ? 18.0
                : 0.0

        let previewCount =
            min(
                2,
                post.previewComments.count
            )

        let commentsButtonHeight: CGFloat =
            (
                post.commentCount > 0 ||
                previewCount > 0
            )
                ? 18.0
                : 0.0

        let previewHeight =
            CGFloat(previewCount) * 18.0

        let measured =
            46.0 +
            photoHeight +
            43.0 +
            metrics.totalHeight +
            toggleHeight +
            commentsButtonHeight +
            previewHeight +
            17.0 +
            12.0 +
            10.0
        rowHeightCache.setObject(NSNumber(value: Double(measured)),
            forKey: cacheKey)
        return measured
    }
}
