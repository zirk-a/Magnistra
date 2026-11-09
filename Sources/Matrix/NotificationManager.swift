// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Notifications and background task handling for Matrix.
import UIKit

final class NotificationManager {
    static let shared = NotificationManager()

    private static let enabledKey = "magnistra.notificationsEnabled"

    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: enabledKey) == nil { return true }
            return defaults.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    weak var syncEngine: SyncEngine?

    var contextResolver: ((_ roomId: String, _ userId: String) -> (sender: String?, room: String?))?

    private var bgTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var isBackground = false

    private let maxPerSync = 5

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func registerSettingsIfNeeded() {
#if IOS8_TARGET
        let types: UIUserNotificationType = [.alert, .sound, .badge]
        let settings = UIUserNotificationSettings(types: types, categories: nil)
        UIApplication.shared.registerUserNotificationSettings(settings)
#endif
    }

    func setEnabled(_ on: Bool) {
        NotificationManager.isEnabled = on
        if on {
            registerSettingsIfNeeded()

            if isBackground { beginBackgroundTask(); registerKeepAlive() }
        } else {
            clearKeepAlive()
            endBackgroundTask()
        }
    }

    @objc private func appDidEnterBackground() {
        isBackground = true
        guard NotificationManager.isEnabled else { return }
        beginBackgroundTask()
        registerKeepAlive()
    }

    @objc private func appDidBecomeActive() {
        isBackground = false
        endBackgroundTask()
        clearKeepAlive()
    }

    private func beginBackgroundTask() {
        guard bgTask == UIBackgroundTaskIdentifier.invalid else { return }

        bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            self?.syncEngine?.stop()
            self?.endBackgroundTask()
        })
    }

    private func endBackgroundTask() {
        guard bgTask != UIBackgroundTaskIdentifier.invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = UIBackgroundTaskIdentifier.invalid
    }

    private func registerKeepAlive() {
        UIApplication.shared.setKeepAliveTimeout(600) { [weak self] in
            guard let self = self, NotificationManager.isEnabled else { return }
            self.beginBackgroundTask()
            self.syncEngine?.start()
        }
    }

    private func clearKeepAlive() {
        UIApplication.shared.clearKeepAliveTimeout()
    }

    func handleSync(_ json: [String: Any], isInitial: Bool) {
        guard NotificationManager.isEnabled, isBackground, !isInitial else { return }
        let selfId = MatrixSession.userId
        guard let rooms = json["rooms"] as? [String: Any],
              let join = rooms["join"] as? [String: Any] else { return }

        var pending: [(name: String, room: String?, body: String)] = []
        for (roomId, rawRoom) in join {
            if pending.count >= maxPerSync { break }
            guard let roomJSON = rawRoom as? [String: Any],
                  let timeline = roomJSON["timeline"] as? [String: Any],
                  let events = timeline["events"] as? [[String: Any]] else { continue }

            for rawEvent in events {
                if pending.count >= maxPerSync { break }

                let rawType = rawEvent["type"] as? String
                guard rawType == "m.room.message" || rawType == "m.room.encrypted" else { continue }

                let rawSender = rawEvent["sender"] as? String
                if let selfId = selfId, rawSender == selfId { continue }

                var event = rawEvent
                var body = "Encrypted message"

                if rawType == "m.room.encrypted" {
                    if let decrypted = MatrixE2EEManager.shared.decryptRoomEvent(rawEvent) {
                        event = decrypted
                    }
                }

                if (event["type"] as? String) == "m.room.message",
                   let content = event["content"] as? [String: Any] {
                    body = (content["body"] as? String) ?? "New message"
                }

                let sender = (event["sender"] as? String) ?? rawSender
                var name = NotificationManager.localpart(sender)
                var roomName: String?
                if let sender = sender {
                    let context = contextResolver?(roomId, sender)
                    if let resolved = context?.sender, !resolved.isEmpty { name = resolved }
                    roomName = context?.room
                }
                pending.append((name, roomName, body))
            }
        }

        guard !pending.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, NotificationManager.isEnabled, self.isBackground else { return }
            guard UIApplication.shared.applicationState != .active else { return }
            for msg in pending {
                self.postNotification(name: msg.name, room: msg.room, body: msg.body)
            }
        }
    }

    private func postNotification(name: String, room: String?, body: String) {
        let note = UILocalNotification()
        note.alertBody = NotificationManager.alertBody(name: name, room: room, body: body)
        note.soundName = UILocalNotificationDefaultSoundName
        UIApplication.shared.presentLocalNotificationNow(note)
    }

    private static func alertBody(name: String, room: String?, body: String) -> String {
        var title = name
        if let room = room, !room.isEmpty, room != name, !room.hasPrefix("!") {
            title = title.isEmpty ? room : "\(name) \u{00B7} \(room)"
        }
        return title.isEmpty ? body : "\(title): \(body)"
    }

    private static func localpart(_ userId: String?) -> String {
        guard var s = userId else { return "" }
        if s.hasPrefix("@") { s.removeFirst() }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return s
    }
}
