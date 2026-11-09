// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Parsing of Matrix room invitations.
import Foundation

struct Invitation {
    let roomId: String
    let name: String
    let inviter: String?

    static func parse(roomId: String, json: [String: Any], selfUserId: String?) -> Invitation {
        var name: String?
        var inviter: String?
        var fallbackMemberName: String?

        if let inviteState = json["invite_state"] as? [String: Any],
           let events = inviteState["events"] as? [[String: Any]] {
            for event in events {
                guard let type = event["type"] as? String,
                      let content = event["content"] as? [String: Any] else { continue }
                switch type {
                case "m.room.name":
                    if let roomName = content["name"] as? String, !roomName.isEmpty {
                        name = roomName
                    }
                case "m.room.member":
                    let membership = content["membership"] as? String
                    let stateKey = event["state_key"] as? String
                    if membership == "invite", stateKey == selfUserId,
                       let sender = event["sender"] as? String {

                        inviter = (content["displayname"] as? String) ?? sender
                    } else if membership == "join",
                              let sender = event["sender"] as? String, sender != selfUserId,
                              fallbackMemberName == nil {

                        fallbackMemberName = (content["displayname"] as? String) ?? sender
                    }
                default:
                    break
                }
            }
        }

        let displayName = name ?? fallbackMemberName ?? inviter ?? roomId
        return Invitation(roomId: roomId, name: displayName, inviter: inviter)
    }
}
