// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room model and RoomStore (room persistence).
import Foundation

struct Room {
    let roomId: String
    var name: String
    var lastMessage: String
    var lastMessageTimestamp: Double
    var prevBatch: String?

    var timelineEvents: [RoomEvent] = []

    var avatarMxc: String?

    var memberNames: [String: String] = [:]
    var memberAvatars: [String: String] = [:]

    var unreadCount: Int = 0

    var roomType: String?

    var spaceChildren: Set<String> = []

    var bridgeNetwork: String?
    var bridgeAvatarMxc: String?

    var topic: String?

    var isSpace: Bool { return roomType == "m.space" }

    private static let maxBufferedEvents = 50

    static func parse(roomId: String, json: [String: Any], existing: Room?, selfUserId: String?,
                       isOpen: Bool = false, isInitialSync: Bool = false) -> Room {
        var name = existing?.name ?? roomId
        var lastMessage = existing?.lastMessage ?? ""
        var lastTimestamp = existing?.lastMessageTimestamp ?? 0
        var prevBatch = existing?.prevBatch
        var timelineEvents = existing?.timelineEvents ?? []
        var unreadCount = existing?.unreadCount ?? 0
        var avatarMxc = existing?.avatarMxc
        var memberNames = existing?.memberNames ?? [:]
        var memberAvatars = existing?.memberAvatars ?? [:]
        var roomType = existing?.roomType
        var spaceChildren = existing?.spaceChildren ?? []
        var bridgeNetwork = existing?.bridgeNetwork
        var bridgeAvatarMxc = existing?.bridgeAvatarMxc
        var topic = existing?.topic
        var explicitAvatarFound = existing?.avatarMxc != nil
        var fallbackMemberName: String?
        var fallbackMemberAvatar: String?
        var explicitNameFound = existing != nil && existing?.name != roomId

        func considerStateEvent(_ event: [String: Any]) {
            guard let type = event["type"] as? String,
                  let content = event["content"] as? [String: Any] else { return }
            if type == "m.room.name", let roomName = content["name"] as? String, !roomName.isEmpty {
                name = roomName
                explicitNameFound = true
            } else if type == "m.room.avatar", let url = content["url"] as? String, url.hasPrefix("mxc://") {
                avatarMxc = url
                explicitAvatarFound = true
            } else if type == "m.room.topic", let t = content["topic"] as? String {
                topic = t
            } else if type == "m.room.create" {

                if let t = content["type"] as? String, !t.isEmpty { roomType = t }
            } else if type == "m.space.child" {

                if let childId = event["state_key"] as? String, !childId.isEmpty {
                    if content.isEmpty { spaceChildren.remove(childId) }
                    else { spaceChildren.insert(childId) }
                }
            } else if type == "uk.half-shot.bridge" {

                if let proto = content["protocol"] as? [String: Any] {
                    bridgeNetwork = (proto["displayname"] as? String)
                        ?? (proto["id"] as? String) ?? bridgeNetwork
                    if let av = proto["avatar_url"] as? String, av.hasPrefix("mxc://") {
                        bridgeAvatarMxc = av
                    }
                }
            } else if type == "m.room.member",
                      content["membership"] as? String == "join",
                      let sender = event["sender"] as? String {

                if let displayname = content["displayname"] as? String, !displayname.isEmpty {
                    memberNames[sender] = displayname
                }
                if let avatar = content["avatar_url"] as? String, avatar.hasPrefix("mxc://") {
                    memberAvatars[sender] = avatar
                }

                if sender != selfUserId {
                    let candidateName = (content["displayname"] as? String) ?? sender
                    let candidateLower = candidateName.lowercased()
                    let candidateIsBridgeBot =
                        candidateLower.contains("bridgebot") ||
                        candidateLower.contains("bridge bot")
                    let currentLower = fallbackMemberName?.lowercased() ?? ""
                    let currentIsBridgeBot =
                        currentLower.contains("bridgebot") ||
                        currentLower.contains("bridge bot")
                    if fallbackMemberName == nil || (currentIsBridgeBot && !candidateIsBridgeBot) {
                        fallbackMemberName = candidateName
                        fallbackMemberAvatar = content["avatar_url"] as? String
                    }
                }
            }
        }

        if let state = json["state"] as? [String: Any],
           let stateEvents = state["events"] as? [[String: Any]] {
            stateEvents.forEach(considerStateEvent)
        }

        if let timeline = json["timeline"] as? [String: Any] {
            if prevBatch == nil, let batch = timeline["prev_batch"] as? String {
                prevBatch = batch
            }
            if let events = timeline["events"] as? [[String: Any]] {
                events.forEach(considerStateEvent)

                for event in events {
                    let type = event["type"] as? String
                    guard type == "m.room.message" || type == "m.room.encrypted" else { continue }

                    if type == "m.room.message",
                       let content = event["content"] as? [String: Any],
                       let body = content["body"] as? String {
                        lastMessage = body
                    } else if type == "m.room.encrypted",
                              let decrypted = MatrixE2EEManager.shared.decryptRoomEvent(event),
                              let content = decrypted["content"] as? [String: Any],
                              let body = content["body"] as? String {
                        lastMessage = body
                    }

                    if let ts = (event["origin_server_ts"] as? NSNumber)?.doubleValue {
                        lastTimestamp = max(lastTimestamp, ts)
                    }

                    if !isOpen, !isInitialSync,
                       let sender = event["sender"] as? String, sender != selfUserId {
                        unreadCount += 1
                    }
                }
                timelineEvents.append(contentsOf: events.compactMap { RoomEvent.parse($0) })
                if timelineEvents.count > maxBufferedEvents {
                    timelineEvents.removeFirst(timelineEvents.count - maxBufferedEvents)
                }
            }
        }

        if fallbackMemberName == nil {
            for (memberId, memberName) in memberNames where memberId != selfUserId {
                let lower = memberName.lowercased()
                let isBridgeBot = lower.contains("bridgebot") || lower.contains("bridge bot")
                if !isBridgeBot {
                    fallbackMemberName = memberName
                    fallbackMemberAvatar = memberAvatars[memberId]
                    break
                }
            }
        }

        let explicitNameLower = name.lowercased()
        let explicitNameIsBridgeBot =
            explicitNameLower.contains("bridgebot") ||
            explicitNameLower.contains("bridge bot")

        if (!explicitNameFound || explicitNameIsBridgeBot),
           let fallbackMemberName = fallbackMemberName {
            let fallbackLower = fallbackMemberName.lowercased()
            let fallbackIsBridgeBot =
                fallbackLower.contains("bridgebot") ||
                fallbackLower.contains("bridge bot")
            if !fallbackIsBridgeBot {
                name = fallbackMemberName
            }
        }

        if (!explicitAvatarFound || explicitNameIsBridgeBot),
           let fallbackMemberAvatar = fallbackMemberAvatar,
           fallbackMemberAvatar.hasPrefix("mxc://") {
            avatarMxc = fallbackMemberAvatar
        }

        if let unreadNotifications = json["unread_notifications"] as? [String: Any],
           let count = (unreadNotifications["notification_count"] as? NSNumber)?.intValue {
            unreadCount = max(unreadCount, count)
        }

        if isOpen { unreadCount = 0 }

        return Room(roomId: roomId, name: name, lastMessage: lastMessage,
                    lastMessageTimestamp: lastTimestamp, prevBatch: prevBatch,
                    timelineEvents: timelineEvents,
                    avatarMxc: avatarMxc, memberNames: memberNames, memberAvatars: memberAvatars,
                    unreadCount: unreadCount,
                    roomType: roomType, spaceChildren: spaceChildren,
                    bridgeNetwork: bridgeNetwork, bridgeAvatarMxc: bridgeAvatarMxc,
                    topic: topic)
    }
}

final class RoomStore {

    static let shared = RoomStore()

    struct Snapshot {
        let since: String
        let rooms: [Room]
        let invites: [Invitation]
    }

    private static let version = 3

    private let path: String

    private let queue = DispatchQueue(label: "com.magnistra.roomstore")

    private var pending: Snapshot?
    private var writeScheduled = false
    private let writeDelay: TimeInterval = 4

    private init() {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        path = (documents as NSString).appendingPathComponent("magnistra-roomlist.json")
    }

    func load() -> Snapshot? {
        guard let userId = MatrixSession.userId else { return nil }

        guard let data = FileManager.default.contents(atPath: path),
              let json = (try? MagnistraJSONKit.jsonObject(with: data, options: [])) as? [String: Any],
              (json["version"] as? NSNumber)?.intValue == RoomStore.version,
              json["userId"] as? String == userId,
              let since = json["since"] as? String, !since.isEmpty else { return nil }
        let rooms = (json["rooms"] as? [[String: Any]] ?? []).compactMap { RoomStore.decodeRoom($0) }
        let invites = (json["invites"] as? [[String: Any]] ?? []).compactMap { RoomStore.decodeInvite($0) }
        guard !rooms.isEmpty else { return nil }
        return Snapshot(since: since, rooms: rooms, invites: invites)
    }

    func save(since: String, rooms: [Room], invites: [Invitation]) {
        pending = Snapshot(since: since, rooms: rooms, invites: invites)
        guard !writeScheduled else { return }
        writeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDelay) { [weak self] in
            guard let self = self else { return }
            self.writeScheduled = false
            guard let snapshot = self.pending else { return }
            self.pending = nil
            self.queue.async { self.write(snapshot) }
        }
    }

    func flush(since: String, rooms: [Room], invites: [Invitation]) {
        pending = nil
        writeScheduled = false
        write(Snapshot(since: since, rooms: rooms, invites: invites))
    }

    func discard() {
        pending = nil
        writeScheduled = false
        let path = self.path
        queue.async { try? FileManager.default.removeItem(atPath: path) }
    }

    private func write(_ snapshot: Snapshot) {
        guard let userId = MatrixSession.userId else { return }
        let json: [String: Any] = [
            "version": RoomStore.version,
            "userId": userId,
            "since": snapshot.since,
            "rooms": snapshot.rooms.map { RoomStore.encodeRoom($0) },
            "invites": snapshot.invites.map { RoomStore.encodeInvite($0) },
        ]
        guard let data = try? MagnistraJSONKit.data(withJSONObject: json, options: []) else { return }

        (data as NSData).write(toFile: path, atomically: true)
    }

    private static func encodeRoom(_ room: Room) -> [String: Any] {
        var d: [String: Any] = [
            "id": room.roomId,
            "name": room.name,
            "last": room.lastMessage,
            "ts": room.lastMessageTimestamp,
            "unread": room.unreadCount,
        ]

        if let v = room.avatarMxc { d["avatar"] = v }
        if !room.memberNames.isEmpty { d["names"] = room.memberNames }
        if !room.memberAvatars.isEmpty { d["avatars"] = room.memberAvatars }
        if let v = room.roomType { d["type"] = v }
        if !room.spaceChildren.isEmpty { d["children"] = Array(room.spaceChildren) }
        if let v = room.bridgeNetwork { d["bridge"] = v }
        if let v = room.bridgeAvatarMxc { d["bridgeAvatar"] = v }
        if let v = room.topic { d["topic"] = v }
        return d
    }

    private static func decodeRoom(_ d: [String: Any]) -> Room? {
        guard let roomId = d["id"] as? String, !roomId.isEmpty else { return nil }
        return Room(roomId: roomId,
                    name: d["name"] as? String ?? roomId,
                    lastMessage: d["last"] as? String ?? "",
                    lastMessageTimestamp: (d["ts"] as? NSNumber)?.doubleValue ?? 0,

                    prevBatch: nil,
                    timelineEvents: [],
                    avatarMxc: d["avatar"] as? String,
                    memberNames: stringMap(d["names"]),
                    memberAvatars: stringMap(d["avatars"]),
                    unreadCount: (d["unread"] as? NSNumber)?.intValue ?? 0,
                    roomType: d["type"] as? String,
                    spaceChildren: Set(stringArray(d["children"])),
                    bridgeNetwork: d["bridge"] as? String,
                    bridgeAvatarMxc: d["bridgeAvatar"] as? String,
                    topic: d["topic"] as? String)
    }

    private static func encodeInvite(_ invite: Invitation) -> [String: Any] {
        var d: [String: Any] = ["id": invite.roomId, "name": invite.name]
        if let v = invite.inviter { d["by"] = v }
        return d
    }

    private static func decodeInvite(_ d: [String: Any]) -> Invitation? {
        guard let roomId = d["id"] as? String, !roomId.isEmpty else { return nil }
        return Invitation(roomId: roomId, name: d["name"] as? String ?? roomId,
                          inviter: d["by"] as? String)
    }

    private static func stringMap(_ any: Any?) -> [String: String] {
        guard let raw = any as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, value) in raw {
            if let s = value as? String { out[key] = s }
        }
        return out
    }

    private static func stringArray(_ any: Any?) -> [String] {
        guard let raw = any as? [Any] else { return [] }
        return raw.compactMap { $0 as? String }
    }
}
