// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline: title view, status label, reply bar and upload bar.
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

extension RoomTimelineVC {


    func buildStatusLabel() {
        let w: CGFloat = 260, h: CGFloat = 72
        statusLabel = UILabel(frame: CGRect(x: (view.bounds.width - w) / 2,
                                            y: (view.bounds.height - h) / 2,
                                            width: w, height: h))
        statusLabel.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin,
                                        .flexibleLeftMargin, .flexibleRightMargin]
        statusLabel.backgroundColor = .clear
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = .gray
        statusLabel.text = "No messages yet."
        statusLabel.isHidden = true
        view.insertSubview(statusLabel, aboveSubview: tableView)
    }

    func setupTitleView() {
        let avatarSize: CGFloat = 30
        let gap: CGFloat = 8
        let label = UILabel()
        label.backgroundColor = .clear
        label.text = room.name
        label.font = UIFont.boldSystemFont(ofSize: 17)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()

        let maxLabelWidth = max(60, UIScreen.main.bounds.width - 180)
        let labelWidth = min(label.frame.width, maxLabelWidth)
        let height: CGFloat = 36
        let container = UIView(frame: CGRect(x: 0, y: 0,
                                             width: avatarSize + gap + labelWidth, height: height))
        let avatar = AvatarView(frame: CGRect(x: 0, y: (height - avatarSize) / 2,
                                              width: avatarSize, height: avatarSize))
        avatar.setAvatar(mxc: room.avatarMxc, name: room.name)
        container.addSubview(avatar)
        label.frame = CGRect(x: avatarSize + gap, y: (height - label.frame.height) / 2,
                             width: labelWidth, height: label.frame.height)
        container.addSubview(label)

        container.isUserInteractionEnabled = true
        container.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                              action: #selector(openRoomSettings)))
        navigationItem.titleView = container

        let membersItem: UIBarButtonItem
        if let icon = UIImage(named: "Users") {
            membersItem = UIBarButtonItem(image: icon, style: .plain,
                                          target: self, action: #selector(openMemberList))
        } else {
            membersItem = UIBarButtonItem(title: "Members", style: .plain,
                                          target: self, action: #selector(openMemberList))
        }
        navigationItem.rightBarButtonItem = membersItem
    }

    @objc func openMemberList() {
        let vc = MemberListVC(room: room, client: client,
                              memberNames: memberNames, memberAvatars: memberAvatars)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc func openRoomSettings() {
        let vc = RoomSettingsVC(room: room, client: client)
        vc.onRoomUpdated = { [weak self] updated in
            guard let self = self else { return }
            self.room = updated
            self.setupTitleView()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    func buildReplyBar() {
        replyBar = UIView(frame: .zero)
        replyBar.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        replyBar.isHidden = true

        replyLabel = UILabel(frame: .zero)
        replyLabel.backgroundColor = .clear
        replyLabel.font = UIFont.systemFont(ofSize: 12)
        replyLabel.textColor = UIColor(white: 0.3, alpha: 1.0)
        replyLabel.lineBreakMode = .byTruncatingTail
        replyBar.addSubview(replyLabel)

        replyCancelButton = UIButton(type: .system)
        replyCancelButton.setTitle("\u{2715} Cancel", for: .normal)
        replyCancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        replyCancelButton.addTarget(self, action: #selector(replyCancelTapped), for: .touchUpInside)
        replyBar.addSubview(replyCancelButton)

        view.addSubview(replyBar)
    }

    func buildUploadBar() {
        uploadBar = UIView(frame: .zero)
        uploadBar.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        uploadBar.isHidden = true

        uploadLabel = UILabel(frame: .zero)
        uploadLabel.backgroundColor = .clear
        uploadLabel.font = UIFont.systemFont(ofSize: 12)
        uploadLabel.textColor = UIColor(white: 0.3, alpha: 1.0)
        uploadBar.addSubview(uploadLabel)

        uploadProgressView = UIProgressView(progressViewStyle: .default)
        uploadBar.addSubview(uploadProgressView)

        view.addSubview(uploadBar)
    }

    func setUploadProgress(_ fraction: Float?) {
        guard uploadBar != nil else { return }
        guard let fraction = fraction else {
            guard !uploadBar.isHidden else { return }
            uploadBar.isHidden = true
            layoutInputBar()
            return
        }
        let clamped = min(max(fraction, 0), 1)
        uploadLabel.text = "Uploading… \(Int(clamped * 100))%"
        uploadProgressView.progress = clamped
        if uploadBar.isHidden {
            uploadBar.isHidden = false
            layoutInputBar()
        }
    }

    func buildTypingLabel() {
        typingLabel = UILabel(frame: .zero)
        typingLabel.backgroundColor = .clear
        typingLabel.font = UIFont.italicSystemFont(ofSize: 12)
        typingLabel.textColor = .gray
        typingLabel.isHidden = true
        view.addSubview(typingLabel)
    }

    func buildInputBar() {

        inputBar = UIView(frame: .zero)
        inputBar.backgroundColor = UIColor(white: 0.97, alpha: 1.0)

        attachButton = UIButton(type: .system)
        attachButton.setTitle("+", for: .normal)
        attachButton.titleLabel?.font = UIFont.systemFont(ofSize: 30)

        attachButton.titleEdgeInsets = UIEdgeInsets(top: -3, left: 0, bottom: 0, right: 0)
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        inputBar.addSubview(attachButton)

        messageField = UITextView(frame: .zero)
        messageField.backgroundColor = .white
        messageField.layer.cornerRadius = 8
        messageField.layer.masksToBounds = true
        messageField.layer.borderWidth = 0.5
        messageField.layer.borderColor = UIColor(white: 0.8, alpha: 1.0).cgColor
        messageField.font = UIFont.systemFont(ofSize: 16)
        messageField.delegate = self

        messageField.isScrollEnabled = false

        if messageField.responds(to: NSSelectorFromString("setTextContainerInset:")) {
            messageField.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        }
        if messageField.responds(to: NSSelectorFromString("textContainer")) {
            messageField.textContainer.lineFragmentPadding = 4
        }
        inputBar.addSubview(messageField)

        placeholderLabel = UILabel(frame: .zero)
        placeholderLabel.text = "Message"
        placeholderLabel.font = messageField.font
        placeholderLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
        placeholderLabel.isUserInteractionEnabled = false
        messageField.addSubview(placeholderLabel)

        sendButton = UIButton(type: .system)
        sendButton.setTitle("Send", for: .normal)
        sendButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        inputBar.addSubview(sendButton)

        voiceCancelButton = UIButton(type: .system)
        voiceCancelButton.setTitle("Cancel", for: .normal)
        voiceCancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        voiceCancelButton.addTarget(self, action: #selector(voiceCancelTapped), for: .touchUpInside)
        voiceCancelButton.isHidden = true
        inputBar.addSubview(voiceCancelButton)

        voiceRecordButton = UIButton(type: .system)
        voiceRecordButton.setTitle("\u{25CF} Record", for: .normal)
        voiceRecordButton.setTitleColor(UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1.0), for: .normal)
        voiceRecordButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        voiceRecordButton.addTarget(self, action: #selector(voiceRecordTapped), for: .touchUpInside)
        voiceRecordButton.isHidden = true
        inputBar.addSubview(voiceRecordButton)

        view.addSubview(inputBar)
        currentFieldHeight = inputMinHeight
        layoutInputBar()
    }

    func layoutInputBar() {
        let barWidth = view.bounds.width
        let barHeight = currentFieldHeight + inputVPad * 2
        let barY = view.bounds.height - keyboardHeight - barHeight
        inputBar.frame = CGRect(x: 0, y: barY, width: barWidth, height: barHeight)

        let buttonH = inputMinHeight
        let buttonY = barHeight - inputVPad - buttonH
        sendButton.frame = CGRect(x: barWidth - hMargin - sendWidth, y: buttonY,
                                  width: sendWidth, height: buttonH)

        if inputMode == .voice {
            attachButton.isHidden = true
            messageField.isHidden = true
            placeholderLabel.isHidden = true
            voiceCancelButton.isHidden = false
            voiceRecordButton.isHidden = false
            let cancelW: CGFloat = 64
            voiceCancelButton.frame = CGRect(x: hMargin, y: buttonY, width: cancelW, height: buttonH)
            let recX = hMargin + cancelW + hSpacing
            let recW = (barWidth - hMargin - sendWidth - hSpacing) - recX
            voiceRecordButton.frame = CGRect(x: recX, y: buttonY, width: max(0, recW), height: buttonH)
        } else {
            attachButton.isHidden = false
            messageField.isHidden = false
            if voiceCancelButton != nil { voiceCancelButton.isHidden = true }
            if voiceRecordButton != nil { voiceRecordButton.isHidden = true }
            attachButton.frame = CGRect(x: hMargin, y: buttonY, width: attachWidth, height: buttonH)

            let fieldX = hMargin + attachWidth + hSpacing
            let fieldWidth = barWidth - fieldX - hMargin - sendWidth - hSpacing
            messageField.frame = CGRect(x: fieldX, y: inputVPad, width: fieldWidth, height: currentFieldHeight)

            let phInset: CGFloat = 8
            placeholderLabel.frame = CGRect(x: phInset, y: phInset,
                                            width: fieldWidth - phInset * 2,
                                            height: messageField.font!.lineHeight + 2)
        }

        let replyVisible = replyBar != nil && !replyBar.isHidden
        let replyH: CGFloat = replyVisible ? replyBarHeight : 0
        if replyVisible {
            replyBar.frame = CGRect(x: 0, y: barY - replyH, width: barWidth, height: replyH)
            let cancelW: CGFloat = 76
            replyLabel.frame = CGRect(x: hMargin, y: 0,
                                      width: max(0, barWidth - hMargin * 2 - cancelW), height: replyH)
            replyCancelButton.frame = CGRect(x: barWidth - hMargin - cancelW, y: 0,
                                             width: cancelW, height: replyH)
        }

        let uploadVisible = uploadBar != nil && !uploadBar.isHidden
        let uploadH: CGFloat = uploadVisible ? uploadBarHeight : 0
        if uploadVisible {
            uploadBar.frame = CGRect(x: 0, y: barY - replyH - uploadH, width: barWidth, height: uploadH)
            let labelW: CGFloat = 110
            uploadLabel.frame = CGRect(x: hMargin, y: 0, width: labelW, height: uploadH)
            let barX = hMargin + labelW

            uploadProgressView.frame = CGRect(x: barX, y: (uploadH - 2) / 2,
                                              width: max(0, barWidth - barX - hMargin), height: 2)
        }

        let typingVisible = !typingUsers.isEmpty
        let typingH: CGFloat = typingVisible ? typingBarHeight : 0
        if typingLabel != nil {
            typingLabel.isHidden = !typingVisible
            typingLabel.frame = CGRect(x: hMargin, y: barY - replyH - uploadH - typingH,
                                       width: barWidth - hMargin * 2, height: typingH)
        }

        if isViewLoaded, tableView != nil {
            tableView.frame.size.height = barY - replyH - uploadH - typingH
        }
    }

    func adjustInputHeight() {
        let fitWidth = messageField.bounds.width
        let content = messageField.sizeThatFits(CGSize(width: fitWidth, height: .greatestFiniteMagnitude)).height
        let target = min(max(content, inputMinHeight), inputMaxHeight)

        let shouldScroll = content > inputMaxHeight
        if messageField.isScrollEnabled != shouldScroll { messageField.isScrollEnabled = shouldScroll }
        guard abs(target - currentFieldHeight) > 0.5 else { return }
        currentFieldHeight = target
        layoutInputBar()
        scrollToBottom(animated: false)
    }
}
