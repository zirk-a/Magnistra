// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Matrix avatar UI (moved unchanged from MediaCache.swift).
import UIKit
class AvatarView: UIView {
    private let imageView = UIImageView()
    private let initialsLabel = UILabel()
    private var currentMxc: String?

    static let thumbPx = 96

    private static let palette: [UIColor] = [
        UIColor(red: 0.90, green: 0.30, blue: 0.35, alpha: 1),
        UIColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1),
        UIColor(red: 0.30, green: 0.65, blue: 0.40, alpha: 1),
        UIColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1),
        UIColor(red: 0.55, green: 0.40, blue: 0.80, alpha: 1),
        UIColor(red: 0.40, green: 0.60, blue: 0.65, alpha: 1),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        initialsLabel.backgroundColor = .clear
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        addSubview(initialsLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        imageView.frame = bounds
        initialsLabel.frame = bounds
        initialsLabel.font = UIFont.boldSystemFont(ofSize: max(9, bounds.width * 0.42))
    }

    func setAvatar(mxc: String?, name: String) {

        if let mxc = mxc, !mxc.isEmpty, mxc == currentMxc, imageView.image != nil { return }
        currentMxc = mxc

        initialsLabel.text = AvatarView.initials(from: name)
        initialsLabel.isHidden = false
        backgroundColor = AvatarView.color(for: name)
        imageView.image = nil
        imageView.isHidden = true

        guard let mxc = mxc, !mxc.isEmpty else { return }
        MediaCache.shared.loadThumbnail(mxc: mxc, width: AvatarView.thumbPx, height: AvatarView.thumbPx) { [weak self] image in
            guard let self = self, self.currentMxc == mxc, let image = image else { return }
            self.imageView.image = image
            self.imageView.isHidden = false

            self.initialsLabel.isHidden = true
        }
    }

    private static func initials(from name: String) -> String {
        var cleaned = name
        if let first = cleaned.first, first == "@" || first == "#" || first == "!" {
            cleaned = String(cleaned.dropFirst())
        }
        let words = cleaned.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    private static func color(for name: String) -> UIColor {
        var hash = 0
        for scalar in name.unicodeScalars { hash = (hash &* 31 &+ Int(scalar.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}
