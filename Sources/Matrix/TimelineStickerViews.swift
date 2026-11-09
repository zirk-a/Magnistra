// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Sticker library and fullscreen sticker screens.
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



final class MagnistraStickerFullscreenVC: UIViewController {

    var onSave: (() -> Void)?
    var saveTitle = "Save Sticker"

    override func viewDidLoad() {
        super.viewDidLoad()
        if onSave != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: saveTitle,
                style: .plain,
                target: self,
                action: #selector(saveTapped)
            )
        }
    }

    @objc private func saveTapped() {
        guard let onSave = onSave else { return }
        onSave()
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.title = "Saved"
    }
}

final class MagnistraStickerLibraryVC: UIViewController, UIScrollViewDelegate {

    private let onSend: (MagnistraSavedSticker) -> Void
    private var segment: UISegmentedControl!
    private var scrollView: UIScrollView!
    private var emptyLabel: UILabel!
    private var buttons: [UIButton] = []
    private var deleteButtons: [UIButton] = []

    private var pendingImportViews: [UIView] = []
    private var pendingImports: [MagnistraStickerPendingImport] = []
    private var items: [MagnistraSavedSticker] = []
    private var editingLibrary = false
    private var animationGeneration = 0
    private var loadingAnimationIDs = Set<String>()
    private var animatedItemIDs = Set<String>()

    init(onSend: @escaping (MagnistraSavedSticker) -> Void) {
        self.onSend = onSend
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stickers"
        view.backgroundColor = UIColor(white: 0.96, alpha: 1.0)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Edit",
            style: .plain,
            target: self,
            action: #selector(toggleStickerEditing)
        )

        segment = UISegmentedControl(items: ["WhatsApp", "Telegram"])
        segment.selectedSegmentIndex = 0
        segment.addTarget(
            self,
            action: #selector(sourceChanged),
            for: .valueChanged
        )
        view.addSubview(segment)

        scrollView = UIScrollView(frame: .zero)
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        view.addSubview(scrollView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stickerLibraryDidChange(_:)),
            name: MagnistraStickerLibraryDidChange,
            object: nil
        )

        emptyLabel = UILabel(frame: .zero)
        emptyLabel.backgroundColor = .clear
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = UIColor(white: 0.45, alpha: 1.0)
        emptyLabel.font = UIFont.systemFont(ofSize: 14)
        scrollView.addSubview(emptyLabel)

        reloadStickers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        segment.frame = CGRect(
            x: 12,
            y: 8,
            width: max(1, width - 24),
            height: 30
        )
        scrollView.frame = CGRect(
            x: 0,
            y: 46,
            width: width,
            height: max(1, view.bounds.height - 46)
        )
        layoutGrid()
        updateVisibleStickerAnimations()
    }

    private var selectedTarget: String {
        return segment.selectedSegmentIndex == 1 ? "telegram" : "whatsapp"
    }

    @objc private func sourceChanged() {
        reloadStickers()
    }

    @objc private func stickerLibraryDidChange(_ note: Notification) {
        reloadStickers()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleStickerAnimations()
    }

    private func staticPreview(for item: MagnistraSavedSticker) -> UIImage? {
        return UIImage(contentsOfFile: item.previewPath)
            ?? MediaCache.stickerLibraryPreview(path: item.displayPath)
    }

    private func reloadStickers() {
        animationGeneration += 1
        loadingAnimationIDs.removeAll()
        animatedItemIDs.removeAll()
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        deleteButtons.removeAll()
        for view in pendingImportViews { view.removeFromSuperview() }
        pendingImportViews.removeAll()
        pendingImports = MagnistraStickerLibrary.shared.pendingImports(
            target: selectedTarget
        )

        items = MagnistraStickerLibrary.shared.items().filter {
            $0.origin == selectedTarget
        }
        emptyLabel.text = selectedTarget == "telegram"
            ? "No Telegram stickers yet"
            : "No WhatsApp stickers yet"
        emptyLabel.isHidden = !items.isEmpty || !pendingImports.isEmpty

        for pendingImport in pendingImports {
            let placeholder = UIView(frame: .zero)
            placeholder.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
            placeholder.layer.cornerRadius = 8
            placeholder.layer.masksToBounds = true
            placeholder.isUserInteractionEnabled = false

            let label = UILabel(frame: .zero)
            label.tag = 7601
            label.backgroundColor = .clear
            label.textAlignment = .center
            label.textColor = UIColor(white: 0.38, alpha: 1.0)
            label.font = UIFont.systemFont(ofSize: 11)
            label.text = "Importing…"
            placeholder.addSubview(label)

            let progress = UIProgressView(progressViewStyle: .default)
            progress.tag = 7602
            progress.progress = pendingImport.progress
            placeholder.addSubview(progress)

            scrollView.addSubview(placeholder)
            pendingImportViews.append(placeholder)
        }

        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.backgroundColor = .clear
            button.adjustsImageWhenHighlighted = false
            button.imageView?.contentMode = .scaleAspectFit

            if let image = staticPreview(for: item) {
                button.setImage(image, for: .normal)
            }

            button.addTarget(
                self,
                action: #selector(stickerTapped(_:)),
                for: .touchUpInside
            )

            let deleteButton = UIButton(type: .custom)
            deleteButton.tag = index
            deleteButton.backgroundColor = UIColor(
                white: 0.10,
                alpha: 0.82
            )
            deleteButton.layer.cornerRadius = 12

            let xBarA = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 2))
            xBarA.bounds = CGRect(x: 0, y: 0, width: 12, height: 2)
            xBarA.center = CGPoint(x: 12, y: 12)
            xBarA.backgroundColor = .white
            xBarA.isUserInteractionEnabled = false
            xBarA.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 4)
            deleteButton.addSubview(xBarA)

            let xBarB = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 2))
            xBarB.bounds = CGRect(x: 0, y: 0, width: 12, height: 2)
            xBarB.center = CGPoint(x: 12, y: 12)
            xBarB.backgroundColor = .white
            xBarB.isUserInteractionEnabled = false
            xBarB.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 4)
            deleteButton.addSubview(xBarB)

            deleteButton.isHidden = !editingLibrary
            deleteButton.addTarget(
                self,
                action: #selector(deleteStickerTapped(_:)),
                for: .touchUpInside
            )
            button.addSubview(deleteButton)

            scrollView.addSubview(button)
            buttons.append(button)
            deleteButtons.append(deleteButton)
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()
        updateVisibleStickerAnimations()
    }

    private func updateVisibleStickerAnimations() {
        guard !buttons.isEmpty else { return }
        let generation = animationGeneration
        let visibleRect = CGRect(
            origin: scrollView.contentOffset,
            size: scrollView.bounds.size
        ).insetBy(dx: 0, dy: -12)

        for (index, button) in buttons.enumerated() {
            guard index < items.count else { continue }
            let item = items[index]
            let visible = button.frame.intersects(visibleRect)

            if !visible {
                animatedItemIDs.remove(item.id)
                if let preview = staticPreview(for: item) {
                    button.setImage(preview, for: .normal)
                }
                continue
            }

            if animatedItemIDs.contains(item.id)
                || loadingAnimationIDs.contains(item.id) {
                continue
            }
            loadingAnimationIDs.insert(item.id)

            if item.sourceKind == "telegram-original" {
                MediaCache.shared.loadStickerAnimatedImage(mxc: item.mxc) { [weak self, weak button] image in
                    guard let self = self else { return }
                    self.loadingAnimationIDs.remove(item.id)
                    guard let button = button,
                          generation == self.animationGeneration,
                          index < self.items.count,
                          self.items[index].id == item.id,
                          button.frame.intersects(CGRect(
                              origin: self.scrollView.contentOffset,
                              size: self.scrollView.bounds.size
                          ).insetBy(dx: 0, dy: -12)),
                          let image = image else { return }
                    self.animatedItemIDs.insert(item.id)
                    button.setImage(image, for: .normal)
                    button.imageView?.startAnimating()
                }
            } else {
                MediaCache.shared.loadStickerLibraryAnimatedImage(path: item.displayPath) { [weak self, weak button] image in
                    guard let self = self else { return }
                    self.loadingAnimationIDs.remove(item.id)
                    guard let button = button,
                          generation == self.animationGeneration,
                          index < self.items.count,
                          self.items[index].id == item.id,
                          button.frame.intersects(CGRect(
                              origin: self.scrollView.contentOffset,
                              size: self.scrollView.bounds.size
                          ).insetBy(dx: 0, dy: -12)),
                          let image = image else { return }
                    self.animatedItemIDs.insert(item.id)
                    button.setImage(image, for: .normal)
                    button.imageView?.startAnimating()
                }
            }
        }
    }

    private func layoutGrid() {
        let columns: CGFloat = 4
        let gap: CGFloat = 8
        let side: CGFloat = 10
        let available = max(1, scrollView.bounds.width - side * 2 - gap * (columns - 1))
        let tile = floor(available / columns)

        for (index, pendingView) in pendingImportViews.enumerated() {
            let row = CGFloat(index / 4)
            let col = CGFloat(index % 4)
            pendingView.frame = CGRect(
                x: side + col * (tile + gap),
                y: side + row * (tile + gap),
                width: tile,
                height: tile
            )
            if let label = pendingView.viewWithTag(7601) as? UILabel {
                label.frame = CGRect(
                    x: 4,
                    y: max(4, tile * 0.38),
                    width: max(1, tile - 8),
                    height: 18
                )
            }
            if let progress = pendingView.viewWithTag(7602) as? UIProgressView {
                progress.frame = CGRect(
                    x: 8,
                    y: max(8, tile * 0.66),
                    width: max(1, tile - 16),
                    height: 12
                )
            }
        }

        for (index, button) in buttons.enumerated() {
            let gridIndex = pendingImportViews.count + index
            let row = CGFloat(gridIndex / 4)
            let col = CGFloat(gridIndex % 4)
            button.frame = CGRect(
                x: side + col * (tile + gap),
                y: side + row * (tile + gap),
                width: tile,
                height: tile
            )
            if index < deleteButtons.count {
                deleteButtons[index].frame = CGRect(
                    x: max(0, tile - 26),
                    y: 2,
                    width: 24,
                    height: 24
                )
            }
        }

        let totalTiles = pendingImportViews.count + buttons.count
        let rows = CGFloat((totalTiles + 3) / 4)
        let contentHeight = side + rows * (tile + gap)
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.width,
            height: max(scrollView.bounds.height + 1, contentHeight)
        )

        emptyLabel.frame = CGRect(
            x: 16,
            y: 40,
            width: max(1, scrollView.bounds.width - 32),
            height: 40
        )
    }

    @objc private func stickerTapped(_ sender: UIButton) {
        guard !editingLibrary,
              sender.tag >= 0,
              sender.tag < items.count else { return }
        let item = items[sender.tag]
        onSend(item)
        navigationController?.popViewController(animated: true)
    }

    @objc private func toggleStickerEditing() {
        editingLibrary = !editingLibrary
        navigationItem.rightBarButtonItem?.title =
            editingLibrary ? "Done" : "Edit"
        for button in deleteButtons {
            button.isHidden = !editingLibrary
        }
    }

    @objc private func deleteStickerTapped(_ sender: UIButton) {
        guard editingLibrary,
              sender.tag >= 0,
              sender.tag < items.count else { return }
        MagnistraStickerLibrary.shared.remove(items[sender.tag])
        reloadStickers()
    }
}