// Overview: Direct backend selection: providers for web Direct and Matrix-backed Direct, plus the inbox screens that use them.
import UIKit
import Security
import QuartzCore
import CoreText
import ImageIO
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import SystemConfiguration

enum MagnistraDirectBackendMode: String {
    case web
    case matrix
    case hybrid

    var displayName: String {
        switch self {
        case .web:
            return "Web"
        case .matrix:
            return "Matrix"
        case .hybrid:
            return "Hybrid"
        }
    }
}

enum MagnistraDirectBackendStore {
    private static let key =
        "MagnistraDirectBackendMode"

    static func current() -> MagnistraDirectBackendMode {
        guard
            let raw =
                UserDefaults.standard
                    .string(
                        forKey:
                            key
                    ),
            let mode =
                MagnistraDirectBackendMode(
                    rawValue:
                        raw
                )
        else {
            return .web
        }

        return mode
    }

    static func set(
        _ mode:
            MagnistraDirectBackendMode
    ) {
        UserDefaults.standard
            .set(
                mode.rawValue,
                forKey:
                    key
            )

        UserDefaults.standard
            .synchronize()
    }
}

protocol MagnistraDirectProvider {
    var backendMode: MagnistraDirectBackendMode { get }
    func loadInbox() throws -> MagnistraDirectInboxPage
}

private struct MagnistraWebDirectProvider:
    MagnistraDirectProvider
{
    let backendMode:
        MagnistraDirectBackendMode =
            .web

    func loadInbox()
        throws -> MagnistraDirectInboxPage
    {
        return
            try MagnistraHomeService
                .loadDirectInbox()
    }
}

final class MagnistraMatrixRoomParticipantsViewController: UITableViewController {
    private var roomId: String = ""
    private var members: [[String: String]] = []
    private let status = UILabel(frame: .zero)

    func setRoomId(_ id: String) {
        roomId = id
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Participants"
        tableView.rowHeight = 62.0
        tableView.backgroundColor = UIColor.white
        status.frame = CGRect(x: 12.0, y: 0.0,
                              width: view.bounds.width - 24.0, height: 100.0)
        status.autoresizingMask = [.flexibleWidth]
        status.textAlignment = .center
        status.textColor = UIColor.gray
        status.font = UIFont.systemFont(ofSize: 14.0)
        status.numberOfLines = 0
        status.backgroundColor = UIColor.clear
        status.text = "Loading participants..."
        tableView.backgroundView = status
        MagnistraMatrixDirectBackend.shared.loadRoomParticipants(roomId: roomId) {
            [weak self] result, error in
            OperationQueue.main.addOperation { [weak self] in
                guard let owner = self else { return }
                if let error = error {
                    owner.status.text = "Could not load participants.\n" + error.localizedDescription
                    owner.members = []
                } else {
                    owner.members = (result ?? []).sorted {
                        ($0["name"] ?? "").localizedCaseInsensitiveCompare(
                            $1["name"] ?? "") == .orderedAscending
                    }
                    owner.status.text = owner.members.isEmpty ? "No joined participants." : nil
                }
                owner.tableView.reloadData()
            }
        }
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        return members.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuse = "MagnistraMatrixRoomMember"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuse) ??
            UITableViewCell(style: .subtitle, reuseIdentifier: reuse)
        let item = members[indexPath.row]
        cell.textLabel?.text = item["name"] ?? item["id"] ?? "Member"
        cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 15.0)
        cell.detailTextLabel?.text = item["id"]
        cell.detailTextLabel?.textColor = UIColor.gray
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12.0)
        cell.selectionStyle = .none

        let avatarSize = CGSize(width: 42.0, height: 42.0)
        UIGraphicsBeginImageContextWithOptions(avatarSize, false, 1.0)
        UIColor(white: 0.91, alpha: 1.0).setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: avatarSize)).fill()
        let placeholder = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        cell.imageView?.image = placeholder
        cell.imageView?.contentMode = .scaleAspectFill
        cell.imageView?.clipsToBounds = true
        cell.imageView?.layer.cornerRadius = 21.0
        if let avatar = item["avatar_url"], avatar.hasPrefix("mxc://") {
            let memberID = item["id"] ?? ""
            MagnistraMatrixMediaStore.shared.loadImage(mxc: avatar) { [weak self, weak cell] image in
                guard let image = image else { return }
                UIGraphicsBeginImageContextWithOptions(avatarSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: avatarSize))
                let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                OperationQueue.main.addOperation { [weak self, weak cell] in
                    guard let owner = self, let target = cell,
                          let visible = owner.tableView.indexPath(for: target),
                          visible.row < owner.members.count,
                          owner.members[visible.row]["id"] == memberID else { return }
                    target.imageView?.image = thumbnail
                    target.setNeedsLayout()
                }
            }
        }
        return cell
    }
}

enum MagnistraMatrixDirectService {
    private static let userAgent =
        "Magnistra/1.0"

    private static let inboxFilter =
        "%7B%22room%22%3A%7B%22timeline%22%3A%7B%22limit%22%3A1%7D%2C%22ephemeral%22%3A%7B%22types%22%3A%5B%5D%7D%2C%22account_data%22%3A%7B%22types%22%3A%5B%5D%7D%7D%2C%22presence%22%3A%7B%22types%22%3A%5B%5D%7D%7D"

    private static func makeError(
        _ message: String,
        code: Int
    ) -> NSError {
        return NSError(
            domain: "MagnistraMatrixDirect",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey:
                    message
            ]
        )
    }

    private static func stateEvents(
        _ room: [String: Any]
    ) -> [[String: Any]] {
        guard
            let state =
                room["state"] as? [String: Any],
            let events =
                state["events"] as? [[String: Any]]
        else {
            return []
        }

        return events
    }

    private static func roomName(
        roomId: String,
        room: [String: Any]
    ) -> String {
        var explicitName: String?
        var alias: String?
        var fallbackName: String?
        var fallbackIsBot = true

        let selfUserId =
            MagnistraMatrixAccountStore
                .userId

        for event in stateEvents(room) {
            guard
                let type =
                    event["type"] as? String,
                let content =
                    event["content"] as? [String: Any]
            else {
                continue
            }

            if
                type == "m.room.name",
                let value =
                    content["name"] as? String
            {
                let clean =
                    value.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                if !clean.isEmpty {
                    explicitName = clean
                }

                continue
            }

            if
                type == "m.room.canonical_alias",
                let value =
                    content["alias"] as? String
            {
                let clean =
                    value.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                if !clean.isEmpty {
                    alias = clean
                }

                continue
            }

            guard
                type == "m.room.member",
                content["membership"] as? String ==
                    "join"
            else {
                continue
            }

            let memberId =
                (
                    event["state_key"]
                        as? String
                ) ??
                (
                    event["sender"]
                        as? String
                ) ??
                ""

            if
                memberId.isEmpty ||
                memberId == selfUserId
            {
                continue
            }

            let rawDisplay =
                (
                    content["displayname"]
                        as? String
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

            let localpart: String = {
                var value = memberId

                if value.hasPrefix("@") {
                    value.removeFirst()
                }

                if
                    let colon =
                        value.firstIndex(
                            of:
                                ":"
                        )
                {
                    value =
                        String(
                            value[
                                value.startIndex..<colon
                            ]
                        )
                }

                return value
            }()

            let candidate =
                (
                    rawDisplay?.isEmpty == false
                        ? rawDisplay
                        : nil
                ) ??
                localpart

            if candidate.isEmpty {
                continue
            }

            let identity =
                (
                    candidate +
                    " " +
                    memberId
                )
                .lowercased()

            let isBot =
                identity.contains(
                    "bridgebot"
                ) ||
                identity.contains(
                    "bridge bot"
                ) ||
                identity.contains(
                    "whatsapp bot"
                )

            if
                fallbackName == nil ||
                (
                    fallbackIsBot &&
                    !isBot
                )
            {
                fallbackName =
                    candidate

                fallbackIsBot =
                    isBot
            }
        }

        if
            let explicitName =
                explicitName
        {
            let lowered =
                explicitName
                    .lowercased()

            let looksLikeBot =
                lowered.contains(
                    "bridgebot"
                ) ||
                lowered.contains(
                    "bridge bot"
                ) ||
                lowered.contains(
                    "whatsapp bot"
                )

            if
                !looksLikeBot ||
                fallbackName == nil
            {
                return explicitName
            }
        }

        if
            let fallbackName =
                fallbackName,
            !fallbackIsBot
        {
            return fallbackName
        }

        if
            let explicitName =
                explicitName
        {
            return explicitName
        }

        if
            let fallbackName =
                fallbackName
        {
            return fallbackName
        }

        if
            let alias =
                alias
        {
            return alias
        }

        return roomId
    }

    private static func spaceChildren(
        _ room: [String: Any]
    ) -> Set<String> {
        var children =
            Set<String>()

        for event in stateEvents(room) {
            guard
                let type =
                    event["type"] as? String,
                type == "m.space.child",
                let roomId =
                    event["state_key"] as? String,
                !roomId.isEmpty,
                let content =
                    event["content"] as? [String: Any]
            else {
                continue
            }

            if content.isEmpty {
                children.remove(roomId)
            } else {
                children.insert(roomId)
            }
        }

        return children
    }

    private static func latestSummary(
        _ room: [String: Any]
    ) -> (
        text: String,
        timestamp: Double
    ) {
        guard
            let timeline =
                room["timeline"] as? [String: Any],
            let events =
                timeline["events"] as? [[String: Any]],
            !events.isEmpty
        else {
            return ("Conversation", 0.0)
        }

        var bestText =
            "Conversation"

        var bestTimestamp =
            0.0

        for event in events {
            let timestamp: Double

            if
                let number =
                    event["origin_server_ts"] as? NSNumber
            {
                timestamp =
                    number.doubleValue
            } else if
                let value =
                    event["origin_server_ts"] as? Double
            {
                timestamp = value
            } else {
                timestamp = 0.0
            }

            if timestamp < bestTimestamp {
                continue
            }

            let type =
                event["type"] as? String ?? ""

            let content =
                event["content"] as? [String: Any] ?? [:]

            var text =
                "Conversation"

            if
                type == "m.room.message" ||
                type == "m.sticker" ||
                type == "m.reaction"
            {
                text =
                    MagnistraMatrixMessagePresentation
                        .make(
                            eventType:
                                type,
                            content:
                                content
                        )
                        .text
            } else if
                type == "m.room.encrypted"
            {
                let eventId =
                    event["event_id"] as? String ??
                    ("time:" + String(timestamp))

                if
                    case .decrypted(let payload) =
                        MagnistraMatrixDecryptor.shared.decrypt(
                            eventId:
                                eventId,
                            content:
                                content
                        ),
                    let clearType =
                        payload["type"]
                            as? String,
                    let clear =
                        payload["content"]
                            as? [String: Any]
                {
                    text =
                        MagnistraMatrixMessagePresentation
                            .make(
                                eventType:
                                    clearType,
                                content:
                                    clear
                            )
                            .text
                } else {
                    text =
                        "Encrypted message"
                }
            } else if
                type == "m.reaction"
            {
                text = "Reaction"
            } else if
                type == "m.room.redaction"
            {
                text = "Message removed"
            }

            bestText =
                text

            bestTimestamp =
                timestamp
        }

        return (
            bestText,
            bestTimestamp
        )
    }

    private static func isUnread(
        _ room: [String: Any]
    ) -> Bool {
        guard
            let unread =
                room[
                    "unread_notifications"
                ] as? [String: Any]
        else {
            return false
        }

        if
            let number =
                unread[
                    "notification_count"
                ] as? NSNumber
        {
            return number.intValue > 0
        }

        if
            let count =
                unread[
                    "notification_count"
                ] as? Int
        {
            return count > 0
        }

        return false
    }

    static func loadInbox()
        throws -> MagnistraDirectInboxPage
    {
        guard
            MagnistraMatrixAccountStore
                .hasSession,
            let homeserver =
                MagnistraMatrixAccountStore
                    .homeserverURL,
            let accessToken =
                MagnistraMatrixAccountStore
                    .accessToken
        else {
            throw makeError(
                "Sign in to Matrix in Settings first.",
                code: 8401
            )
        }

        guard
            let selectedSpace =
                MagnistraMatrixAccountStore
                    .instagramSpaceId,
            !selectedSpace.isEmpty
        else {
            throw makeError(
                "Select an Instagram Space in Settings first.",
                code: 8402
            )
        }

        guard
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                )
        else {
            throw makeError(
                "Secure connection support is unavailable.",
                code: 8403
            )
        }

        let base =
            homeserver.hasSuffix("/")
                ? String(homeserver.dropLast())
                : homeserver

        let url =
            base +
            "/_matrix/client/v3/sync?timeout=0&filter=" +
            inboxFilter

        let curlCode: Int32 =
            caPath.withCString { ca in
                url.withCString { requestURL in
                    accessToken.withCString { token in
                        userAgent.withCString { ua in
                            Int32(
                                magnistra_matrix_space_get_json(
                                    ca,
                                    requestURL,
                                    token,
                                    ua
                                )
                            )
                        }
                    }
                }
            }

        let status =
            magnistra_matrix_space_http_status()

        let tls =
            magnistra_matrix_space_tls_verify_result()

        guard curlCode == 0 else {
            throw makeError(
                "Could not load Matrix conversations.",
                code: 8404
            )
        }

        guard tls == 0 else {
            throw makeError(
                "The secure connection could not be verified.",
                code: 8405
            )
        }

        let length =
            Int(
                magnistra_matrix_space_body_length()
            )

        guard
            length > 0,
            let pointer =
                magnistra_matrix_space_body()
        else {
            throw makeError(
                "The homeserver returned an empty response.",
                code: 8406
            )
        }

        let data =
            Data(
                bytes:
                    pointer,
                count:
                    length
            )

        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with:
                        data,
                    options:
                        []
                )

        guard
            let root =
                object as? [String: Any]
        else {
            throw makeError(
                "The homeserver returned an unexpected response.",
                code: 8407
            )
        }

        guard status >= 200 && status < 300 else {
            let message =
                (root["error"] as? String) ??
                "Matrix returned HTTP \(status)."

            throw makeError(
                message,
                code:
                    Int(status)
            )
        }

        guard
            let rooms =
                root["rooms"] as? [String: Any],
            let joined =
                rooms["join"] as? [String: Any]
        else {
            return MagnistraDirectInboxPage(
                threads:
                    [],
                endCursor:
                    nil,
                hasNextPage:
                    false
            )
        }

        guard
            let rawSpace =
                joined[
                    selectedSpace
                ] as? [String: Any]
        else {
            throw makeError(
                "The selected Space is no longer joined.",
                code: 8408
            )
        }

        let allowedRoomIds =
            spaceChildren(
                rawSpace
            )

        var threads:
            [MagnistraDirectThreadSummary] =
                []

        for roomId in allowedRoomIds {
            guard
                let room =
                    joined[
                        roomId
                    ] as? [String: Any]
            else {
                continue
            }

            let summary =
                latestSummary(
                    room
                )

            threads.append(
                MagnistraDirectThreadSummary(
                    threadFBID:
                        roomId,
                    minUQSeqID:
                        0,
                    title:
                        roomName(
                            roomId:
                                roomId,
                            room:
                                room
                        ),
                    username:
                        "",
                    snippet:
                        summary.text,
                    avatarURL:
                        nil,
                    lastActivityMilliseconds:
                        summary.timestamp,
                    isUnread:
                        isUnread(
                            room
                        ),
                    participantUserIDs:
                        [],
                    isGroupConversation:
                        true
                )
            )
        }

        threads.sort {
            if
                $0.lastActivityMilliseconds ==
                $1.lastActivityMilliseconds
            {
                return
                    $0.title.lowercased() <
                    $1.title.lowercased()
            }

            return
                $0.lastActivityMilliseconds >
                $1.lastActivityMilliseconds
        }

        return MagnistraDirectInboxPage(
            threads:
                threads,
            endCursor:
                nil,
            hasNextPage:
                false
        )
    }

    static func loadTimeline(roomId: String) throws -> [MagnistraMatrixTimelineMessage] {
        return try loadTimelinePage(roomId: roomId, before: nil).messages
    }

    static func loadTimelinePage(
        roomId: String, before: String?
    ) throws -> MagnistraMatrixTimelinePage {
        guard
            MagnistraMatrixAccountStore
                .hasSession,
            let homeserver =
                MagnistraMatrixAccountStore
                    .homeserverURL,
            let accessToken =
                MagnistraMatrixAccountStore
                    .accessToken
        else {
            throw makeError(
                "Sign in to Matrix in Settings first.",
                code: 8451
            )
        }

        guard !roomId.isEmpty else {
            throw makeError(
                "The Matrix room identifier is missing.",
                code: 8452
            )
        }

        guard
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                )
        else {
            throw makeError(
                "Secure connection support is unavailable.",
                code: 8453
            )
        }

        let base =
            homeserver.hasSuffix("/")
                ? String(homeserver.dropLast())
                : homeserver

        let escapedRoom = magnistraMatrixPercentEncode(roomId)
        var url = base + "/_matrix/client/v3/rooms/" + escapedRoom +
                  "/messages?dir=b&limit=30"
        if let from = before, !from.isEmpty {
            url += "&from=" + magnistraMatrixPercentEncode(from)
        }

        let curlCode: Int32 =
            caPath.withCString { ca in
                url.withCString { requestURL in
                    accessToken.withCString { token in
                        userAgent.withCString { ua in
                            Int32(
                                magnistra_matrix_space_get_json(
                                    ca,
                                    requestURL,
                                    token,
                                    ua
                                )
                            )
                        }
                    }
                }
            }

        let status =
            magnistra_matrix_space_http_status()

        let tls =
            magnistra_matrix_space_tls_verify_result()

        guard curlCode == 0 else {
            throw makeError(
                "Could not load this Matrix conversation.",
                code: 8454
            )
        }

        guard tls == 0 else {
            throw makeError(
                "The secure connection could not be verified.",
                code: 8455
            )
        }

        let length =
            Int(
                magnistra_matrix_space_body_length()
            )

        guard
            length > 0,
            let pointer =
                magnistra_matrix_space_body()
        else {
            throw makeError(
                "The homeserver returned an empty response.",
                code: 8456
            )
        }

        let data =
            Data(
                bytes:
                    pointer,
                count:
                    length
            )

        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with:
                        data,
                    options:
                        []
                )

        guard
            let root =
                object as? [String: Any]
        else {
            throw makeError(
                "The homeserver returned an unexpected response.",
                code: 8457
            )
        }

        guard status >= 200 && status < 300 else {
            let message =
                (root["error"] as? String) ??
                "Matrix returned HTTP \(status)."

            throw makeError(
                message,
                code:
                    Int(status)
            )
        }

        let chunk =
            root["chunk"]
                as? [[String: Any]] ??
            []

        let selfUserId =
            MagnistraMatrixAccountStore
                .userId

        var messages:
            [MagnistraMatrixTimelineMessage] =
                []

        var seen =
            Set<String>()

        for event in chunk {
            let type =
                event["type"] as? String ?? ""

            guard
                type == "m.room.message" ||
                type == "m.room.encrypted" ||
                type == "m.sticker" ||
                type == "m.reaction"
            else {
                continue
            }

            let timestamp: Double

            if
                let number =
                    event["origin_server_ts"]
                        as? NSNumber
            {
                timestamp =
                    number.doubleValue
            } else {
                timestamp =
                    0.0
            }

            let eventId =
                (
                    event["event_id"]
                        as? String
                ) ??
                (
                    "time:" +
                    String(timestamp)
                )

            if seen.contains(eventId) {
                continue
            }

            seen.insert(eventId)

            let sender =
                event["sender"]
                    as? String ??
                ""

            let encrypted =
                type == "m.room.encrypted"

            var unresolvedEncrypted =
                encrypted

            var resolvedEventType =
                type

            var resolvedContent =
                MagnistraMatrixDirectBackend
                    .shared
                    .normalizedContent(
                        event["content"]
                            as? [String: Any] ??
                        [:]
                    )

            var presentation =
                MagnistraMatrixMessagePresentation(
                    text:
                        encrypted
                            ? "Encrypted message"
                            : "Message",
                    detail:
                        nil
                )

            if encrypted {

                let outcome: MagnistraMatrixDecryptor.Outcome
                if let content = event["content"] as? [String: Any] {
                    outcome = MagnistraMatrixDecryptor.shared.decrypt(
                        eventId: eventId, content: content)
                } else {
                    outcome = .failed("missing event content")
                }
                if
                    case .decrypted(let payload) = outcome,
                    let clearType =
                        payload["type"]
                            as? String,
                    let clearContent =
                        payload["content"]
                            as? [String: Any]
                {
                    resolvedEventType =
                        clearType

                    resolvedContent =
                        MagnistraMatrixDirectBackend
                            .shared
                            .normalizedContent(
                                clearContent
                            )

                    presentation =
                        MagnistraMatrixMessagePresentation
                            .make(
                                eventType:
                                    resolvedEventType,
                                content:
                                    resolvedContent
                            )

                    unresolvedEncrypted =
                        false
                }
                if
                    unresolvedEncrypted,
                    let clearEvent =
                        MagnistraMatrixDirectBackend
                            .shared
                            .decryptOwnOutbound(
                                event:
                                    event
                            ),
                    let ownType =
                        clearEvent["type"]
                            as? String,
                    let ownContent =
                        clearEvent["content"]
                            as? [String: Any]
                {
                    resolvedEventType =
                        ownType

                    resolvedContent =
                        MagnistraMatrixDirectBackend
                            .shared
                            .normalizedContent(
                                ownContent
                            )

                    presentation =
                        MagnistraMatrixMessagePresentation
                            .make(
                                eventType:
                                    resolvedEventType,
                                content:
                                    resolvedContent
                            )

                    unresolvedEncrypted =
                        false
                }
                if
                    unresolvedEncrypted,
                    let liveEvent = MagnistraMatrixDirectBackend.shared.decryptWithLiveSession(
                        event: event, roomId: roomId),
                    let liveType = liveEvent["type"] as? String,
                    let liveContent = liveEvent["content"] as? [String: Any]
                {
                    resolvedEventType = liveType
                    resolvedContent = MagnistraMatrixDirectBackend.shared.normalizedContent(liveContent)
                    presentation = MagnistraMatrixMessagePresentation.make(
                        eventType: resolvedEventType, content: resolvedContent)
                    unresolvedEncrypted = false
                }
                if unresolvedEncrypted {

                    presentation = MagnistraMatrixMessagePresentation(
                        text: "Encrypted",
                        detail: nil)
                }
            } else if
                let clearContent =
                    event["content"]
                        as? [String: Any]
            {
                resolvedEventType =
                    type

                resolvedContent =
                    MagnistraMatrixDirectBackend
                        .shared
                        .normalizedContent(
                            clearContent
                        )

                presentation =
                    MagnistraMatrixMessagePresentation
                        .make(
                            eventType:
                                resolvedEventType,
                            content:
                                resolvedContent
                        )
            }

            messages.append(
                MagnistraMatrixTimelineMessage(
                    eventId:
                        eventId,
                    text:
                        presentation.text,
                    timestampMilliseconds:
                        timestamp,
                    isOutgoing:
                        !sender.isEmpty &&
                        sender == selfUserId,
                    isEncrypted:
                        unresolvedEncrypted,
                    detailText:
                        presentation.detail,
                    eventType:
                        resolvedEventType,
                    content:
                        resolvedContent,
                    senderUserId:
                        sender
                )
            )
        }

        messages.sort {
            if
                $0.timestampMilliseconds ==
                $1.timestampMilliseconds
            {
                return
                    $0.eventId <
                    $1.eventId
            }

            return
                $0.timestampMilliseconds <
                $1.timestampMilliseconds
        }

        let cursor = root["end"] as? String
        let hasOlder = !chunk.isEmpty && cursor != nil && cursor != before
        return MagnistraMatrixTimelinePage(messages: messages,
                                          nextCursor: cursor,
                                          hasOlder: hasOlder)
    }

}

struct MagnistraMatrixTimelinePage {
    let messages: [MagnistraMatrixTimelineMessage]
    let nextCursor: String?
    let hasOlder: Bool
}

private func magnistraMatrixPercentEncode(_ raw: String) -> String {
    var out = ""
    for byte in raw.utf8 {
        if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
           (byte >= 48 && byte <= 57) || byte == 45 || byte == 46 ||
           byte == 95 || byte == 126 {
            out.append(Character(UnicodeScalar(Int(byte))!))
        } else {
            out += String(format: "%%%02X", Int(byte))
        }
    }
    return out
}

private struct MagnistraMatrixDirectProvider:
    MagnistraDirectProvider
{
    let backendMode:
        MagnistraDirectBackendMode =
            .matrix

    func loadInbox()
        throws -> MagnistraDirectInboxPage
    {
        return
            try MagnistraMatrixDirectService
                .loadInbox()
    }
}

private struct MagnistraHybridDirectProvider:
    MagnistraDirectProvider
{
    let backendMode:
        MagnistraDirectBackendMode =
            .hybrid

    func loadInbox()
        throws -> MagnistraDirectInboxPage
    {
        throw NSError(
            domain:
                "MagnistraDirectHybrid",
            code:
                7101,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Matrix account is required for Hybrid mode."
            ]
        )
    }
}

enum MagnistraDirectProviderFactory {
    static func make(
        _ mode:
            MagnistraDirectBackendMode
    ) -> MagnistraDirectProvider {
        switch mode {
        case .web:
            return MagnistraWebDirectProvider()
        case .matrix:
            return MagnistraMatrixDirectProvider()
        case .hybrid:
            return MagnistraHybridDirectProvider()
        }
    }
}

