// Overview: Post action bar (like, save and repost state and counts).
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



final class MagnistraPostActionBarLabel:
    UILabel
{
    private let likeIcon = UIImageView()
    private let likeCountLabel = UILabel()
    private let commentIcon = UIImageView()
    private let commentCountLabel = UILabel()
    private let repostIcon = UIImageView()
    private let repostCountLabel = UILabel()
    private let sendIcon = UIImageView()
    private let shareCountLabel = UILabel()
    private let saveIcon = UIImageView()

    var onLikeTap: (() -> Void)?
    var onCommentsTap: (() -> Void)?
    var onRepostTap: (() -> Void)?
    var onShareTap: (() -> Void)?
    var onSaveTap: (() -> Void)?

    private var liked = false
    private var saved = false
    private var reposted = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        text = nil
        clipsToBounds = false
        isUserInteractionEnabled = true

        for view in [
            likeIcon,
            commentIcon,
            repostIcon,
            sendIcon,
            saveIcon
        ] {
            view.backgroundColor = UIColor.clear
            view.contentMode = .scaleAspectFit
            view.isUserInteractionEnabled = false
            addSubview(view)
        }

        commentIcon.image =
            UIImage(
                named:
                    "MagnistraPostComment"
            )

        sendIcon.image = MagnistraProfileIcons.png("Share")
        sendIcon.transform = CGAffineTransform.identity

        for label in [
            likeCountLabel,
            commentCountLabel,
            repostCountLabel,
            shareCountLabel
        ] {
            label.backgroundColor =
                UIColor.clear
            label.textColor =
                UIColor(
                    white:
                        0.18,
                    alpha:
                        1.0
                )
            label.font =
                UIFont.boldSystemFont(
                    ofSize:
                        11.5
                )
            label.textAlignment =
                .left
            label.adjustsFontSizeToFitWidth =
                true
            label.minimumScaleFactor =
                0.72
            label.lineBreakMode =
                .byClipping
            label.isUserInteractionEnabled =
                false
            addSubview(
                label
            )
        }

        refreshStateIcons()

        addGestureRecognizer(
            UITapGestureRecognizer(
                target:
                    self,
                action:
                    #selector(
                        actionTap(_:)
                    )
            )
        )
    }

    func configure(
        likes: Int,
        comments: Int,
        reposts: Int,
        shares: Int
    ) {
        likeCountLabel.text =
            MagnistraPostActionBarLabel
                .compactCount(
                    max(
                        0,
                        likes
                    )
                )

        commentCountLabel.text =
            MagnistraPostActionBarLabel
                .compactCount(
                    max(
                        0,
                        comments
                    )
                )

        repostCountLabel.text =
            MagnistraPostActionBarLabel
                .compactCount(
                    max(
                        0,
                        reposts
                    )
                )

        if shares >= 0 {
            shareCountLabel.text =
                MagnistraPostActionBarLabel.compactCount(shares)
        } else {
            shareCountLabel.text = nil
        }

        setNeedsLayout()
    }

    func setLikeState(
        _ value: Bool,
        likes: Int
    ) {
        liked =
            value

        likeCountLabel.text =
            MagnistraPostActionBarLabel
                .compactCount(
                    max(
                        0,
                        likes
                    )
                )

        refreshStateIcons()
    }

    func setSaveState(
        _ value: Bool
    ) {
        saved =
            value
        refreshStateIcons()
    }

    func setRepostState(
        _ value: Bool,
        reposts: Int
    ) {
        reposted =
            value

        repostCountLabel.text =
            MagnistraPostActionBarLabel
                .compactCount(
                    max(
                        0,
                        reposts
                    )
                )

        refreshStateIcons()
    }

    func reset() {
        liked = false
        saved = false
        reposted = false

        likeCountLabel.text = nil
        commentCountLabel.text = nil
        repostCountLabel.text = nil
        shareCountLabel.text = nil

        refreshStateIcons()
    }

    private func refreshStateIcons() {
        likeIcon.image =
            UIImage(
                named:
                    liked
                        ? "MagnistraPostLikeActive"
                        : "MagnistraPostLike"
            )

        saveIcon.image =
            UIImage(
                named:
                    saved
                        ? "MagnistraPostSaveActive"
                        : "MagnistraPostSave"
            )

        repostIcon.image =
            UIImage(
                named:
                    reposted
                        ? "MagnistraPostRepostActive"
                        : "MagnistraPostRepost"
            )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let h =
            max(
                1.0,
                bounds.size.height
            )

        let iconSide: CGFloat = 27.0
        let sendIconSide: CGFloat = 26.0
        let iconY =
            (h - iconSide) * 0.5

        let innerGap: CGFloat = 3.0
        var groupGap: CGFloat = 7.0

        let saveX =
            max(
                0.0,
                bounds.size.width -
                    iconSide
            )

        let leftAvailable =
            max(
                1.0,
                saveX - 8.0
            )

        func hasCount(
            _ label: UILabel
        ) -> Bool {
            guard
                let value = label.text
            else {
                return false
            }

            return
                !value.isEmpty
        }

        let visibleCountLabels =
            [
                likeCountLabel,
                commentCountLabel,
                repostCountLabel,
                shareCountLabel
            ]
            .filter {
                hasCount($0)
            }

        let countSlots =
            CGFloat(
                max(
                    1,
                    visibleCountLabels.count
                )
            )

        let countCap =
            max(
                20.0,
                min(
                    40.0,
                    (
                        leftAvailable -
                        iconSide * 3.0 -
                        sendIconSide -
                        innerGap *
                            CGFloat(
                                visibleCountLabels.count
                            ) -
                        groupGap * 3.0
                    ) /
                    countSlots
                )
            )

        func countWidth(
            _ label: UILabel
        ) -> CGFloat {
            guard hasCount(label) else {
                return 0.0
            }

            let fit =
                label.sizeThatFits(
                    CGSize(
                        width: 80.0,
                        height: h
                    )
                )

            return
                ceil(
                    max(
                        14.0,
                        min(
                            countCap,
                            fit.width + 1.0
                        )
                    )
                )
        }

        let widths = [
            countWidth(likeCountLabel),
            countWidth(commentCountLabel),
            countWidth(repostCountLabel),
            countWidth(shareCountLabel)
        ]

        let usedInner =
            innerGap *
            CGFloat(
                widths.filter {
                    $0 > 0.0
                }.count
            )

        let naturalWidth =
            iconSide * 3.0 +
            sendIconSide +
            widths.reduce(
                0.0,
                +
            ) +
            usedInner +
            groupGap * 3.0

        if naturalWidth > leftAvailable {
            groupGap =
                max(
                    2.0,
                    groupGap -
                    (
                        naturalWidth -
                        leftAvailable
                    ) /
                    3.0
                )
        }

        var x: CGFloat = 0.0

        func place(
            icon: UIImageView,
            label: UILabel,
            width: CGFloat,
            side: CGFloat,
            addTrailingGap: Bool
        ) {
            let localIconY =
                (h - side) * 0.5

            icon.bounds =
                CGRect(
                    x: 0.0,
                    y: 0.0,
                    width: side,
                    height: side
                )

            icon.center =
                CGPoint(
                    x: x + side * 0.5,
                    y: localIconY + side * 0.5
                )

            x +=
                side

            if width > 0.0 {
                x += innerGap

                label.frame =
                    CGRect(
                        x: x,
                        y: 0.0,
                        width: width,
                        height: h
                    )

                x =
                    label.frame.maxX
            } else {
                label.frame =
                    CGRect(
                        x: x,
                        y: 0.0,
                        width: 0.0,
                        height: h
                    )
            }

            if addTrailingGap {
                x += groupGap
            }
        }

        place(
            icon: likeIcon,
            label: likeCountLabel,
            width: widths[0],
            side: iconSide,
            addTrailingGap: true
        )

        place(
            icon: commentIcon,
            label: commentCountLabel,
            width: widths[1],
            side: iconSide,
            addTrailingGap: true
        )

        place(
            icon: repostIcon,
            label: repostCountLabel,
            width: widths[2],
            side: iconSide,
            addTrailingGap: true
        )

        place(
            icon: sendIcon,
            label: shareCountLabel,
            width: widths[3],
            side: sendIconSide,
            addTrailingGap: false
        )

        saveIcon.bounds =
            CGRect(
                x: 0.0,
                y: 0.0,
                width: iconSide,
                height: iconSide
            )

        saveIcon.center =
            CGPoint(
                x: saveX + iconSide * 0.5,
                y: iconY + iconSide * 0.5
            )
    }

    @objc private func actionTap(
        _ recognizer:
            UITapGestureRecognizer
    ) {
        let point =
            recognizer.location(
                in: self
            )

        func hit(
            icon: UIImageView,
            label: UILabel?
        ) -> Bool {
            var area =
                icon.frame

            if
                let label = label,
                label.frame.width > 0.0
            {
                area =
                    area.union(
                        label.frame
                    )
            }

            area =
                area.insetBy(
                    dx: -4.0,
                    dy: -6.0
                )

            return
                area.contains(
                    point
                )
        }

        if hit(
            icon: likeIcon,
            label: likeCountLabel
        ) {
            onLikeTap?()
            return
        }

        if hit(
            icon: commentIcon,
            label: commentCountLabel
        ) {
            onCommentsTap?()
            return
        }

        if hit(
            icon: repostIcon,
            label: repostCountLabel
        ) {
            onRepostTap?()
            return
        }

        if hit(
            icon: sendIcon,
            label: shareCountLabel
        ) {
            onShareTap?()
            return
        }

        if hit(
            icon: saveIcon,
            label: nil
        ) {
            onSaveTap?()
        }
    }

    private static func compactCount(
        _ value: Int
    ) -> String {
        if value >= 1_000_000 {
            let n =
                Double(
                    value
                ) /
                1_000_000.0

            return
                String(
                    format:
                        n >= 10.0
                            ? "%.0fM"
                            : "%.1fM",
                    n
                )
        }

        if value >= 1_000 {
            let n =
                Double(
                    value
                ) /
                1_000.0

            return
                String(
                    format:
                        n >= 10.0
                            ? "%.0fK"
                            : "%.1fK",
                    n
                )
        }

        return
            "\(value)"
    }
}