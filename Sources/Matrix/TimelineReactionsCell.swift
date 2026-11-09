// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: reactions cell.
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



class ReactionsCell: UITableViewCell {
    static let chipHeight: CGFloat = 22
    static let chipGap: CGFloat = 4
    static let rowGap: CGFloat = 2
    static let topGap: CGFloat = 1
    static let bottomGap: CGFloat = 4
    static let chipHPadding: CGFloat = 8
    static let font = UIFont.systemFont(ofSize: 13)

    private var chips: [UIButton] = []
    private var items: [ReactionItem] = []
    private var isOwnMessage = false
    private var revealOffset: CGFloat = 0

    var onTapKey: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [ReactionItem], isOwn: Bool) {
        self.items = items
        isOwnMessage = isOwn

        while chips.count < items.count {
            let button = UIButton(type: .custom)
            button.titleLabel?.font = ReactionsCell.font
            button.layer.cornerRadius = ReactionsCell.chipHeight / 2
            button.layer.borderWidth = 1
            button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            contentView.addSubview(button)
            chips.append(button)
        }
        for (index, button) in chips.enumerated() {
            guard index < items.count else {
                button.isHidden = true
                continue
            }
            let item = items[index]
            let mine = item.mineEventId != nil
            button.isHidden = false
            button.tag = index
            button.setTitle(ReactionsCell.chipTitle(item), for: .normal)
            button.setTitleColor(mine ? UIColor(red: 0.0, green: 0.35, blue: 0.75, alpha: 1.0) : .darkGray,
                                 for: .normal)

            button.backgroundColor = mine
                ? UIColor(red: 0.85, green: 0.91, blue: 1.0, alpha: 1.0)
                : UIColor(white: 0.90, alpha: 1.0)
            button.layer.borderColor = (mine
                ? UIColor(red: 0.35, green: 0.6, blue: 0.95, alpha: 1.0)
                : UIColor(white: 0.78, alpha: 1.0)).cgColor
        }
        setNeedsLayout()
    }

    func setRevealOffset(_ offset: CGFloat) {
        guard offset != revealOffset else { return }
        revealOffset = offset
        setNeedsLayout()
        layoutIfNeeded()
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < items.count else { return }
        onTapKey?(items[sender.tag].key)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let (frames, _) = ReactionsCell.layout(items: items, width: width)

        let leftStart = EventCell.outerMargin + EventCell.senderGutter
        for (index, frame) in frames.enumerated() where index < chips.count {
            var f = frame
            if isOwnMessage {
                let lineWidth = ReactionsCell.lineWidth(frames: frames, y: frame.origin.y)
                f.origin.x = width - EventCell.outerMargin - lineWidth + frame.origin.x
            } else {
                f.origin.x = leftStart + frame.origin.x
            }
            f.origin.x -= revealOffset
            chips[index].frame = f
        }
    }

    static func height(items: [ReactionItem], width: CGFloat) -> CGFloat {
        return layout(items: items, width: width).1
    }

    private static func layout(items: [ReactionItem], width: CGFloat) -> ([CGRect], CGFloat) {
        let available = max(40, width - EventCell.outerMargin * 2 - EventCell.senderGutter)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = topGap
        for item in items {
            let chipWidth = min(available, textWidth(chipTitle(item)) + chipHPadding * 2)
            if x > 0 && x + chipWidth > available {
                x = 0
                y += chipHeight + rowGap
            }
            frames.append(CGRect(x: x, y: y, width: chipWidth, height: chipHeight))
            x += chipWidth + chipGap
        }
        return (frames, y + chipHeight + bottomGap)
    }

    private static func lineWidth(frames: [CGRect], y: CGFloat) -> CGFloat {
        var maxX: CGFloat = 0
        for frame in frames where frame.origin.y == y { maxX = max(maxX, frame.maxX) }
        return maxX
    }

    private static func chipTitle(_ item: ReactionItem) -> String {
        return item.count > 1 ? "\(item.key) \(item.count)" : item.key
    }

    private static let sizingLabel = UILabel()
    private static var widthCache: [String: CGFloat] = [:]
    private static func textWidth(_ text: String) -> CGFloat {
        if let cached = widthCache[text] { return cached }
        sizingLabel.font = font
        sizingLabel.text = text
        let width = ceil(sizingLabel.sizeThatFits(CGSize(width: 10000, height: chipHeight)).width)
        if widthCache.count > 200 { widthCache.removeAll() }
        widthCache[text] = width
        return width
    }
}