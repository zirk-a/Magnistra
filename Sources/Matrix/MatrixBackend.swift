// Overview: Background loop that polls the Matrix server for crypto-related events.
import Foundation
import UIKit

final class MagnistraMatrixCryptoSync {
    static let shared = MagnistraMatrixCryptoSync()
    private var api: MatrixAPIClient?
    private var accountID = ""
    private var storeKey = ""
    private var nextBatch: String?
    private var inFlight = false
    private var scheduled = false
    private var running = false
    private var generation = 0
    private init() {}

    func start(api: MatrixAPIClient) {
        guard let uid = MatrixSession.userId,
              let did = MatrixSession.deviceId,
              !uid.isEmpty, !did.isEmpty else { return }
        let account = uid + "|" + did
        if running && account == accountID { return }
        generation += 1
        accountID = account
        storeKey = "magnistra_matrix.crypto_sync." + uid + "." + did
        nextBatch = MagnistraPrivateState.shared.string(forKey: storeKey)
        self.api = api
        running = true
        inFlight = false
        scheduled = false
        schedule(after: 0.3)
    }

    func stop() {
        generation += 1
        running = false
        inFlight = false
        scheduled = false
        api = nil
        accountID = ""
        nextBatch = nil
    }

    private func schedule(after delay: TimeInterval) {
        guard running, !scheduled else { return }
        scheduled = true
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.generation == g else { return }
            self.scheduled = false
            self.poll()
        }
    }

    private func queryEscape(_ text: String) -> String {
        let allowed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        var result = ""
        for char in text.utf8 {
            if allowed.contains(char) {
                result += String(UnicodeScalar(Int(char))!)
            } else {
                result += String(format: "%%%02X", Int(char))
            }
        }
        return result
    }

    private func poll() {
        guard running, !inFlight, let client = api else { return }
        guard DeviceVerificationManager.shared.magnistraCryptoIdentityReady else {
            schedule(after: 2.0)
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            schedule(after: 8.0)
            return
        }

        let filter = "%7B%22room%22%3A%7B%22rooms%22%3A%5B%5D%7D%2C%22presence%22%3A%7B%22types%22%3A%5B%5D%7D%2C%22account_data%22%3A%7B%22types%22%3A%5B%5D%7D%7D"
        var path = "/_matrix/client/v3/sync?set_presence=offline&timeout=20000"
        if let batch = nextBatch, !batch.isEmpty { path += "&since=" + queryEscape(batch) }
        inFlight = true
        let g = generation
        client.get(path, timeout: 40) { [weak self] json, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == g else { return }
                self.inFlight = false
                guard error == nil,
                      let json = json,
                      json["errcode"] == nil,
                      let batch = json["next_batch"] as? String,
                      !batch.isEmpty else {
                    print("[MatrixCryptoSync] sync failed; token unchanged")
                    self.schedule(after: 10.0)
                    return
                }

                DeviceVerificationManager.shared.handleSync(json)
                if let rooms = json["rooms"] as? [String: Any],
                   let joined = rooms["join"] as? [String: Any] {
                    var changed: [String] = []
                    for (roomId, record) in joined {
                        guard let room = record as? [String: Any],
                              let timeline = room["timeline"] as? [String: Any],
                              let events = timeline["events"] as? [[String: Any]],
                              !events.isEmpty else { continue }
                        changed.append(roomId)
                    }
                    if !changed.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("MagnistraMatrixRoomsUpdated"),
                            object: nil,
                            userInfo: ["roomIds": changed])
                    }
                }
                self.nextBatch = batch
                MagnistraPrivateState.shared.set(batch, forKey: self.storeKey)
                MagnistraPrivateState.shared.synchronize()

                self.schedule(after: 2.0)
            }
        }
    }
}
