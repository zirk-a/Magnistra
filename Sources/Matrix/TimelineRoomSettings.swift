// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room settings and member list screens.
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



class RoomSettingsVC: UIViewController, UITableViewDataSource, UITableViewDelegate {

    var onRoomUpdated: ((Room) -> Void)?

    var room: Room
    private let client: MatrixAPIClient
    private var tableView: UITableView!
    private let cellId = "RoomSettingCell"

    private var avatarPicker: AvatarPicker?
    private let leaveSheetTag = 95

    init(room: Room, client: MatrixAPIClient) {
        self.room = room
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Room Settings"
        view.backgroundColor = .white

        tableView = UITableView(frame: view.bounds, style: .grouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
    }

    func numberOfSections(in tableView: UITableView) -> Int { return 3 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Room"
        case 1: return "People"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 && indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId + "AV") ??
                UITableViewCell(style: .default, reuseIdentifier: cellId + "AV")
            cell.textLabel?.text = "Photo"
            cell.textLabel?.textColor = .black
            cell.textLabel?.textAlignment = .left
            let avatar = AvatarView(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
            avatar.setAvatar(mxc: room.avatarMxc, name: room.name)
            cell.accessoryView = avatar
            cell.selectionStyle = .default
            return cell
        }
        if indexPath.section == 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId) ??
                UITableViewCell(style: .default, reuseIdentifier: cellId)
            cell.accessoryView = nil
            cell.accessoryType = .none
            cell.textLabel?.text = "Leave Room"
            cell.textLabel?.textColor = UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1.0)
            cell.textLabel?.textAlignment = .center
            cell.selectionStyle = .default
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId + "V") ??
            UITableViewCell(style: .value1, reuseIdentifier: cellId + "V")
        cell.accessoryView = nil
        cell.textLabel?.textColor = .black
        cell.textLabel?.textAlignment = .left
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        if indexPath.section == 1 {
            cell.textLabel?.text = "Invite someone\u{2026}"
            cell.detailTextLabel?.text = nil
            return cell
        }
        if indexPath.row == 1 {
            cell.textLabel?.text = "Name"
            cell.detailTextLabel?.text = room.name
        } else {
            cell.textLabel?.text = "Topic"
            let topic = room.topic ?? ""
            cell.detailTextLabel?.text = topic.isEmpty ? "None" : topic
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            pickPhoto()
        case (0, 1):
            editName()
        case (0, 2):
            editTopic()
        case (1, _):
            navigationController?.pushViewController(
                InviteUserVC(roomId: room.roomId, client: client), animated: true)
        default:
            confirmLeave()
        }
    }

    private func editName() {
        let editor = TextEditVC(screenTitle: "Room name", placeholder: "Room name",
                                current: room.name, multiline: false)
        editor.onSave = { [weak self] name in self?.saveName(name) }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func editTopic() {
        let editor = TextEditVC(screenTitle: "Topic", placeholder: "Topic",
                                current: room.topic ?? "", multiline: true)
        editor.onSave = { [weak self] topic in self?.saveTopic(topic) }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func saveName(_ raw: String) {
        let name = raw.roomSettingsTrimmed()
        guard !name.isEmpty, name != room.name else { return }
        putState("m.room.name", body: ["name": name]) { [weak self] in
            guard let self = self else { return }
            self.room.name = name
            self.commit()
        }
    }

    private func saveTopic(_ raw: String) {
        let topic = raw.roomSettingsTrimmed()
        guard topic != (room.topic ?? "") else { return }
        putState("m.room.topic", body: ["topic": topic]) { [weak self] in
            guard let self = self else { return }
            self.room.topic = topic
            self.commit()
        }
    }

    private func pickPhoto() {
        let picker = AvatarPicker(client: client)
        avatarPicker = picker
        picker.start(from: self, anchor: view) { [weak self] mxc, _, error in
            guard let self = self else { return }
            self.avatarPicker = nil
            guard let mxc = mxc else {
                if let error = error { self.showAlert("Couldn't upload", "\(error)") }
                return
            }
            self.putState("m.room.avatar", body: ["url": mxc]) { [weak self] in
                guard let self = self else { return }
                self.room.avatarMxc = mxc
                self.commit()
            }
        }
    }

    private func putState(_ eventType: String, body: [String: Any],
                          onSuccess: @escaping () -> Void) {
        let path = "/_matrix/client/v3/rooms/\(room.roomId)/state/\(eventType)"
        client.put(path, body: body) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {

                self.showAlert("Couldn't update", "\(error)")
                return
            }
            onSuccess()
        }
    }

    private func commit() {
        if isViewLoaded { tableView.reloadData() }
        onRoomUpdated?(room)
    }

    private func confirmLeave() {
        let message = "You'll stop receiving messages from this room. You'll need a new invite to rejoin."
#if LEGACY_TARGET
        let sheet = UIActionSheet()
        sheet.title = message
        sheet.addButton(withTitle: "Leave Room")
        sheet.addButton(withTitle: "Cancel")
        sheet.destructiveButtonIndex = 0
        sheet.cancelButtonIndex = 1
        sheet.tag = leaveSheetTag
        sheet.delegate = self
        sheet.show(in: view)
#else
        let alert = UIAlertController(title: "Leave room?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave Room", style: .destructive) { [weak self] _ in
            self?.performLeave()
        })
        present(alert, animated: true)
#endif
    }

    fileprivate func performLeave() {
        client.post("/_matrix/client/v3/rooms/\(room.roomId)/leave", body: [:]) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                self.showAlert("Couldn't leave", "\(error)")
                return
            }

            self.navigationController?.popToRootViewController(animated: true)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
#if LEGACY_TARGET
        let alert = UIAlertView()
        alert.title = title
        alert.message = message
        alert.addButton(withTitle: "OK")
        alert.show()
#else
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
#endif
    }
}

#if LEGACY_TARGET
extension RoomSettingsVC: UIActionSheetDelegate {
    func actionSheet(_ actionSheet: UIActionSheet, clickedButtonAt buttonIndex: Int) {
        guard actionSheet.tag == leaveSheetTag,
              buttonIndex == actionSheet.destructiveButtonIndex else { return }
        performLeave()
    }
}
#endif

extension String {

    func roomSettingsTrimmed() -> String {
        let ws: Set<Character> = [" ", "\t", "\n", "\r"]
        var chars = Array(self)
        while let f = chars.first, ws.contains(f) { chars.removeFirst() }
        while let l = chars.last, ws.contains(l) { chars.removeLast() }
        return String(chars)
    }
}

class MemberListVC: UIViewController, UITableViewDataSource, UITableViewDelegate {

    let room: Room
    private let client: MatrixAPIClient
    private var names: [String: String]
    private var avatars: [String: String]

    private var userIds: [String] = []

    private var tableView: UITableView!
    private let cellId = "MemberCell"
    private var statusLabel: UILabel!

    init(room: Room, client: MatrixAPIClient,
         memberNames: [String: String], memberAvatars: [String: String]) {
        self.room = room
        self.client = client
        self.names = memberNames
        self.avatars = memberAvatars
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Members"
        view.backgroundColor = .white

        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        view.addSubview(tableView)

        statusLabel = UILabel(frame: CGRect(x: 20, y: 90, width: view.bounds.width - 40, height: 24))
        statusLabel.autoresizingMask = [.flexibleWidth]
        statusLabel.backgroundColor = .clear
        statusLabel.textColor = .gray
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.text = "Loading members\u{2026}"
        view.addSubview(statusLabel)

        rebuildFromLocal()
        fetchMembers()
    }

    private func rebuildFromLocal() {

        userIds = Array(Set(names.keys).union(avatars.keys)).sorted { a, b in
            let na = (names[a] ?? a).lowercased()
            let nb = (names[b] ?? b).lowercased()
            return na == nb ? a < b : na < nb
        }
        statusLabel.isHidden = !userIds.isEmpty
        tableView.reloadData()
    }

    private func fetchMembers() {
        let path = "/_matrix/client/v3/rooms/\(room.roomId)/joined_members"
        client.get(path) { [weak self] json, error in
            guard let self = self else { return }
            guard let joined = json?["joined"] as? [String: Any] else {
                if self.userIds.isEmpty {
                    self.statusLabel.text = "Couldn't load members."
                    self.statusLabel.isHidden = false
                }
                return
            }
            for (userId, value) in joined {
                guard let info = value as? [String: Any] else { continue }
                if let dn = info["display_name"] as? String, !dn.isEmpty {
                    self.names[userId] = dn
                }
                if let av = info["avatar_url"] as? String, av.hasPrefix("mxc://") {
                    self.avatars[userId] = av
                }
                if self.names[userId] == nil { self.names[userId] = userId }
            }
            self.rebuildFromLocal()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return userIds.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId) as? MemberCell
            ?? MemberCell(style: .subtitle, reuseIdentifier: cellId)
        let userId = userIds[indexPath.row]
        let name = names[userId] ?? userId
        cell.textLabel?.text = name
        cell.detailTextLabel?.text = userId
        cell.detailTextLabel?.textColor = .gray
        cell.selectionStyle = .none
        cell.setAvatar(mxc: avatars[userId], name: name)
        return cell
    }
}

class MemberCell: UITableViewCell {
    let avatarView = AvatarView()
    private let avatarSize: CGFloat = 40
    private let avatarMargin: CGFloat = 12

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(avatarView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setAvatar(mxc: String?, name: String) {
        avatarView.setAvatar(mxc: mxc, name: name)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = (contentView.bounds.height - avatarSize) / 2
        avatarView.frame = CGRect(x: avatarMargin, y: y, width: avatarSize, height: avatarSize)
        let textLeft = avatarMargin + avatarSize + 12
        if let tl = textLabel {
            tl.frame.origin.x = textLeft
            tl.frame.size.width = contentView.bounds.width - textLeft - avatarMargin
        }
        if let dl = detailTextLabel {
            dl.frame.origin.x = textLeft
            dl.frame.size.width = contentView.bounds.width - textLeft - avatarMargin
        }
    }
}