// Overview: Comment preview view shown under a post.
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



final class MagnistraCommentPreviewView:
    UIView
{
    let authorLabel = UILabel()
    private let bulletLabel = UILabel()
    private let bodyLabel = UILabel()

    override init(
        frame: CGRect
    ) {
        super.init(frame: frame)

        backgroundColor =
            UIColor.clear

        authorLabel.backgroundColor =
            UIColor.clear
        authorLabel.textColor =
            MagnistraPostCell
                .magnistraBlue
        authorLabel.font =
            UIFont.boldSystemFont(
                ofSize: 11.5
            )

        addSubview(
            authorLabel
        )

        bulletLabel.backgroundColor =
            UIColor.clear
        bulletLabel.textColor =
            UIColor(
                white: 0.50,
                alpha: 1.0
            )
        bulletLabel.font =
            UIFont.systemFont(
                ofSize: 11.5
            )
        bulletLabel.text =
            "•"
        bulletLabel.textAlignment =
            .center

        addSubview(
            bulletLabel
        )

        bodyLabel.backgroundColor =
            UIColor.clear
        bodyLabel.textColor =
            UIColor(
                white: 0.32,
                alpha: 1.0
            )
        bodyLabel.font =
            UIFont.systemFont(
                ofSize: 11.5
            )
        bodyLabel.lineBreakMode =
            .byTruncatingTail

        addSubview(
            bodyLabel
        )
    }

    required init?(
        coder: NSCoder
    ) {
        super.init(coder: coder)
    }

    func configure(
        _ comment:
            MagnistraComment?
    ) {
        guard let comment =
            comment
        else {
            isHidden = true
            authorLabel.text = nil
            bodyLabel.text = nil
            return
        }

        isHidden = false
        authorLabel.text =
            comment.username
        bodyLabel.text =
            comment.text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width =
            bounds.size.width

        let authorWidth =
            min(
                max(
                    34.0,
                    CGFloat(
                        authorLabel
                            .text?
                            .utf16
                            .count ?? 0
                    ) *
                    6.5 +
                    4.0
                ),
                width * 0.40
            )

        authorLabel.frame =
            CGRect(
                x: 0.0,
                y: 0.0,
                width:
                    authorWidth,
                height: 18.0
            )

        bulletLabel.frame =
            CGRect(
                x:
                    authorWidth,
                y: 0.0,
                width: 16.0,
                height: 18.0
            )

        bodyLabel.frame =
            CGRect(
                x:
                    authorWidth +
                    16.0,
                y: 0.0,
                width:
                    max(
                        10.0,
                        width -
                        authorWidth -
                        16.0
                    ),
                height: 18.0
            )
    }
}