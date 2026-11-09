// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix sync engine with update and error listeners.
import Foundation
import UIKit

class SyncEngine {

    private let api: MatrixAPIClient
    private var since: String?
    private var isRunning = false
    private var isRequestInFlight = false

    private var isUnvalidatedResumeToken = false

    private var isFirstPoll = true

    private let serverTimeoutMs = 30000
    private var clientTimeoutSeconds: Int { (serverTimeoutMs / 1000) + 10 }

    private let initialSyncTimeoutSeconds = 180

    private let retryDelaySeconds: TimeInterval = 5

    private let minPollIntervalSeconds: TimeInterval = 0.25

    private var updateListeners: [(token: Int, fn: ([String: Any], Bool) -> Void)] = []
    private var errorListeners: [(token: Int, fn: (Error) -> Void)] = []
    private var nextListenerToken = 0

    private var pollGeneration = 0

    private static let unreservedBytes: Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    private static let hexDigits = Array("0123456789ABCDEF")

    private static func percentEncode(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if unreservedBytes.contains(byte) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result.append("%")
                result.append(hexDigits[Int(byte >> 4)])
                result.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return result
    }

    init(api: MatrixAPIClient) {
        self.api = api
        DeviceVerificationManager.shared.attach(api: api)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                                name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                                name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @discardableResult
    func addUpdateListener(_ listener: @escaping ([String: Any], Bool) -> Void) -> Int {
        let token = nextListenerToken
        nextListenerToken += 1
        updateListeners.append((token, listener))
        return token
    }

    @discardableResult
    func addErrorListener(_ listener: @escaping (Error) -> Void) -> Int {
        let token = nextListenerToken
        nextListenerToken += 1
        errorListeners.append((token, listener))
        return token
    }

    func removeUpdateListener(_ token: Int) {
        updateListeners.removeAll { $0.token == token }
    }

    func removeErrorListener(_ token: Int) {
        errorListeners.removeAll { $0.token == token }
    }

    @objc private func appDidBecomeActive() {
        start()
    }

    @objc private func appDidEnterBackground() {

        if !NotificationManager.isEnabled { stop() }
    }

    func resume(since token: String) {
        guard !isRunning, since == nil, !token.isEmpty else { return }
        since = token
        isUnvalidatedResumeToken = true
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollOnce()
    }

    func stop() {
        isRunning = false
    }

    @discardableResult
    func refreshNow() -> Bool {
        guard isRunning else {
            start()
            return true
        }
        guard !isRequestInFlight else { return false }
        pollGeneration += 1
        pollOnce()
        return true
    }

    private func pollOnce() {
        guard isRunning, !isRequestInFlight else { return }
        isRequestInFlight = true
        let generation = pollGeneration

        let isInitial = since == nil

        var path = "/_matrix/client/v3/sync?timeout=\(serverTimeoutMs)"
        if let since = since {
            let encoded = SyncEngine.percentEncode(since)
            path += "&since=\(encoded)"
        }

        let timeout = (isInitial || isFirstPoll) ? initialSyncTimeoutSeconds : clientTimeoutSeconds
        api.get(path, timeout: timeout) { [weak self] json, error in
            guard let self = self else { return }
            self.isRequestInFlight = false

            if let error = error {
                if self.isUnvalidatedResumeToken {

                    self.isUnvalidatedResumeToken = false
                    self.since = nil
                    RoomStore.shared.discard()
                }
                self.errorListeners.forEach { $0.fn(error) }
                guard self.isRunning else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelaySeconds) { [weak self] in
                    guard let self = self, self.pollGeneration == generation else { return }
                    self.pollOnce()
                }
                return
            }

            if let json = json {
                self.isUnvalidatedResumeToken = false
                self.isFirstPoll = false
                if let nextBatch = json["next_batch"] as? String {
                    self.since = nextBatch
                }
                DeviceVerificationManager.shared.handleSync(json)
                self.updateListeners.forEach { $0.fn(json, isInitial) }
            }

            guard self.isRunning else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.minPollIntervalSeconds) { [weak self] in
                guard let self = self, self.pollGeneration == generation else { return }
                self.pollOnce()
            }
        }
    }
}
