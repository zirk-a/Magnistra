// Overview: Factory that builds Matrix chat view controllers.
import Foundation
import UIKit

final class MagnistraMatrixChatFactory {
    private static var engines:
        [String: SyncEngine] = [:]

    static func make(
        summary:
            MagnistraDirectThreadSummary
    ) -> UIViewController {
        let client =
            MatrixSession.makeAPIClient()

        let engine:
            SyncEngine

        if
            let existing =
                engines[
                    summary.threadFBID
                ]
        {
            engine = existing
        } else {
            let created =
                SyncEngine(
                    api: client
                )

            engines[
                summary.threadFBID
            ] = created

            engine = created
            engine.start()
        }

        let room =
            Room(
                roomId:
                    summary.threadFBID,
                name:
                    summary.title,
                lastMessage:
                    "",
                lastMessageTimestamp:
                    0.0,
                prevBatch:
                    nil,
                timelineEvents:
                    [],
                avatarMxc:
                    nil,
                memberNames:
                    [:],
                memberAvatars:
                    [:],
                unreadCount:
                    0,
                roomType:
                    nil,
                spaceChildren:
                    Set<String>(),
                bridgeNetwork:
                    nil,
                bridgeAvatarMxc:
                    nil,
                topic:
                    nil
            )

        return
            RoomTimelineVC(
                room: room,
                client: client,
                syncEngine:
                    engine
            )
    }
}
