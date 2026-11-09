// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Sticker store: saved stickers and migration of legacy records.
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



let MagnistraStickerLibraryDidChange = NSNotification.Name(
    rawValue: "MagnistraStickerLibraryDidChange"
)

struct MagnistraSavedSticker {
    let id: String
    let origin: String
    let mxc: String
    let sourceKind: String
    let filename: String
    let mimeType: String
    let path: String
    let displayPath: String
    let previewPath: String
    let width: Int
    let height: Int
}

struct MagnistraStickerPendingImport {
    let key: String
    let target: String
    let progress: Float
}

final class MagnistraStickerLibrary {

    static let shared = MagnistraStickerLibrary()

    private let defaultsKey = "MagnistraStickerLibrary.v1"
    private let rootPath: String
    private let recordsPath: String
    private let storageIsGlobal: Bool
    private var pending = Set<String>()

    private let pendingImportLock = NSLock()
    private var pendingImportProgress: [String: Float] = [:]
    private var pendingImportTarget: [String: String] = [:]

    private init() {
        let fm = FileManager.default
        let globalRoot = "/var/mobile/Library/Magnistra/Stickers"
        var selectedRoot = globalRoot
        var globalOK = false

        do {
            try fm.createDirectory(
                atPath: globalRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            globalOK = true
        } catch {
            let documents = NSSearchPathForDirectoriesInDomains(
                .documentDirectory, .userDomainMask, true
            ).first ?? NSTemporaryDirectory()
            selectedRoot = (documents as NSString)
                .appendingPathComponent("magnistra-stickers")
            try? fm.createDirectory(
                atPath: selectedRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        rootPath = selectedRoot
        recordsPath = (selectedRoot as NSString)
            .appendingPathComponent("library.plist")
        storageIsGlobal = globalOK

        try? fm.createDirectory(
            atPath: (rootPath as NSString).appendingPathComponent("whatsapp"),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? fm.createDirectory(
            atPath: (rootPath as NSString).appendingPathComponent("telegram"),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if globalOK {
            migrateLegacyContainerRecordsIfNeeded()
        }
    }

    private func legacyContainerRecords() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: defaultsKey)
            as? [[String: Any]] ?? []
    }

    private func migrateLegacyContainerRecordsIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: recordsPath) else { return }

        let legacy = legacyContainerRecords()
        guard !legacy.isEmpty else { return }

        var migrated: [[String: Any]] = []
        for original in legacy {
            var record = original
            let target = (((record["target"] as? String)
                ?? (record["origin"] as? String)
                ?? "whatsapp").lowercased() == "telegram")
                ? "telegram"
                : "whatsapp"
            let folder = (rootPath as NSString).appendingPathComponent(target)

            guard let oldPath = record["path"] as? String,
                  fm.fileExists(atPath: oldPath) else {
                continue
            }

            let pathName = (oldPath as NSString).lastPathComponent
            let newPath = (folder as NSString).appendingPathComponent(pathName)
            if oldPath != newPath && !fm.fileExists(atPath: newPath) {
                do { try fm.copyItem(atPath: oldPath, toPath: newPath) }
                catch { continue }
            }
            record["path"] = newPath

            if let oldDisplay = record["displayPath"] as? String,
               fm.fileExists(atPath: oldDisplay) {
                let displayName = (oldDisplay as NSString).lastPathComponent
                let newDisplay = (folder as NSString)
                    .appendingPathComponent(displayName)
                if oldDisplay != newDisplay && !fm.fileExists(atPath: newDisplay) {
                    try? fm.copyItem(atPath: oldDisplay, toPath: newDisplay)
                }
                record["displayPath"] = newDisplay
            } else {
                record["displayPath"] = newPath
            }

            if let oldPreview = record["preview"] as? String,
               fm.fileExists(atPath: oldPreview) {
                let previewName = (oldPreview as NSString).lastPathComponent
                let newPreview = (folder as NSString)
                    .appendingPathComponent(previewName)
                if oldPreview != newPreview && !fm.fileExists(atPath: newPreview) {
                    try? fm.copyItem(atPath: oldPreview, toPath: newPreview)
                }
                record["preview"] = newPreview
            }

            record["target"] = target
            migrated.append(record)
        }

        if !migrated.isEmpty {
            _ = (migrated as NSArray).write(
                toFile: recordsPath,
                atomically: true
            )
        }
    }

    private func records() -> [[String: Any]] {
        if let stored = NSArray(contentsOfFile: recordsPath)
            as? [[String: Any]] {
            return stored
        }

        return storageIsGlobal ? [] : legacyContainerRecords()
    }

    private func saveRecords(_ records: [[String: Any]]) {
        _ = (records as NSArray).write(
            toFile: recordsPath,
            atomically: true
        )

        if !storageIsGlobal {
            UserDefaults.standard.set(records, forKey: defaultsKey)
            UserDefaults.standard.synchronize()
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: MagnistraStickerLibraryDidChange,
                object: nil
            )
        }
    }

    private func origin(
        bridgeNetwork: String?,
        filename: String,
        mimeType: String
    ) -> String {
        let network = (bridgeNetwork ?? "").lowercased()
        if network.contains("whatsapp") { return "whatsapp" }
        if network.contains("telegram") { return "telegram" }

        let lowerMime = mimeType.lowercased()
        let ext = (filename.lowercased() as NSString).pathExtension
        if lowerMime.contains("tgsticker")
            || lowerMime.contains("lottie")
            || ext == "tgs"
            || ext == "json" {
            return "telegram"
        }
        return "whatsapp"
    }

    private func fileExtension(filename: String, mimeType: String) -> String {
        let ext = (filename.lowercased() as NSString).pathExtension
        if !ext.isEmpty { return ext }
        let mime = mimeType.lowercased()
        if mime.contains("tgsticker") || mime.contains("lottie") { return "tgs" }
        if mime == "image/webp" { return "webp" }
        if mime == "image/gif" { return "gif" }
        if mime == "application/json" { return "json" }
        return "bin"
    }

    private func effectiveMime(filename: String, mimeType: String) -> String {
        if !mimeType.isEmpty { return mimeType }
        switch fileExtension(filename: filename, mimeType: mimeType) {
        case "tgs": return "application/x-tgsticker"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    private func recordKey(origin: String, mxc: String) -> String {
        return origin + "|" + mxc
    }

    private func setPendingImportProgress(
        key: String,
        target: String,
        progress: Float
    ) {
        let clamped = max(Float(0), min(Float(1), progress))
        pendingImportLock.lock()
        let previous = pendingImportProgress[key]
        let previousTarget = pendingImportTarget[key]
        pendingImportProgress[key] = clamped
        pendingImportTarget[key] = target
        var changed = previous == nil || previousTarget != target
        if let previous = previous {
            if abs(previous - clamped) >= 0.075 || clamped >= 0.999 {
                changed = true
            }
        }
        pendingImportLock.unlock()

        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: MagnistraStickerLibraryDidChange,
                    object: nil
                )
            }
        }
    }

    private func finishPendingImport(key: String) {
        pendingImportLock.lock()
        let removedProgress = pendingImportProgress.removeValue(forKey: key)
        let removedTarget = pendingImportTarget.removeValue(forKey: key)
        let changed = removedProgress != nil || removedTarget != nil
        pendingImportLock.unlock()
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: MagnistraStickerLibraryDidChange,
                    object: nil
                )
            }
        }
    }

    func pendingImports(target: String) -> [MagnistraStickerPendingImport] {
        pendingImportLock.lock()
        var out: [MagnistraStickerPendingImport] = []
        for (key, progress) in pendingImportProgress {
            guard pendingImportTarget[key] == target else { continue }
            out.append(MagnistraStickerPendingImport(
                key: key,
                target: target,
                progress: progress
            ))
        }
        pendingImportLock.unlock()
        return out.sorted { $0.key < $1.key }
    }

    private func prepareNativeStickerSaveSlot(origin: String, mxc: String) -> Bool {
        let current = records()
        var cleaned: [[String: Any]] = []
        var usableDuplicate = false
        var changed = false

        for record in current {
            let matches = ((record["origin"] as? String) ?? "") == origin
                && (record["mxc"] as? String) == mxc
                && (record["sourceKind"] as? String) != "semantic-gif-to-real-sticker"
            if matches {
                guard let sendPath = record["path"] as? String else {
                    removeSavedStickerRecordAssets(record)
                    changed = true
                    continue
                }
                let displayPath = (record["displayPath"] as? String) ?? sendPath
                if FileManager.default.fileExists(atPath: sendPath)
                    && FileManager.default.fileExists(atPath: displayPath) {
                    usableDuplicate = true
                    cleaned.append(record)
                } else {
                    removeSavedStickerRecordAssets(record)
                    changed = true
                }
            } else {
                cleaned.append(record)
            }
        }

        if changed { saveRecords(cleaned) }
        return usableDuplicate
    }

    func save(
        mxc: String,
        bridgeNetwork: String?,
        width: Int,
        height: Int
    ) {
        guard let info = MediaCache.shared.stickerInfo(for: mxc) else { return }

        let sourceOrigin = origin(
            bridgeNetwork: bridgeNetwork,
            filename: info.filename,
            mimeType: info.mimeType
        )
        let key = recordKey(origin: sourceOrigin, mxc: mxc)

        if pending.contains(key) { return }
        if prepareNativeStickerSaveSlot(origin: sourceOrigin, mxc: mxc) {
            return
        }

        pending.insert(key)
        setPendingImportProgress(
            key: key,
            target: sourceOrigin,
            progress: 0.12
        )

        let ext = fileExtension(filename: info.filename, mimeType: info.mimeType)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let diskName = "sticker-\(now)-\(Int.random(in: 0..<1_000_000)).\(ext)"
        let folder = (rootPath as NSString).appendingPathComponent(sourceOrigin)
        let destination = (folder as NSString).appendingPathComponent(diskName)
        let preview = destination + ".preview.png"

        setPendingImportProgress(
            key: key,
            target: sourceOrigin,
            progress: 0.30
        )
        MediaCache.shared.exportStickerOriginal(
            mxc: mxc,
            destinationPath: destination
        ) { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                self.pending.remove(key)
                self.finishPendingImport(key: key)
                return
            }
            self.setPendingImportProgress(
                key: key,
                target: sourceOrigin,
                progress: 0.82
            )

            if let image = MediaCache.stickerLibraryPreview(path: destination),
               let png = image.pngData() {
                (png as NSData).write(toFile: preview, atomically: true)
            }

            if self.prepareNativeStickerSaveSlot(origin: sourceOrigin, mxc: mxc) {
                try? FileManager.default.removeItem(atPath: destination)
                try? FileManager.default.removeItem(atPath: preview)
                self.pending.remove(key)
                self.finishPendingImport(key: key)
                return
            }
            var all = self.records()

            let mime = self.effectiveMime(
                filename: info.filename,
                mimeType: info.mimeType
            )
            let lowerMimeForKind = mime.lowercased()
            let extForKind = (info.filename.lowercased() as NSString).pathExtension
            let sourceKind = sourceOrigin == "telegram"
                && (lowerMimeForKind.contains("tgsticker")
                    || lowerMimeForKind.contains("lottie")
                    || lowerMimeForKind == "application/json"
                    || extForKind == "tgs"
                    || extForKind == "json")
                ? "telegram-original"
                : "native-sticker"

            let record: [String: Any] = [
                "id": "\(sourceOrigin)-\(now)-\(Int.random(in: 0..<1_000_000))",
                "origin": sourceOrigin,
                "target": sourceOrigin,
                "sourceKind": sourceKind,
                "mxc": mxc,
                "filename": info.filename.isEmpty ? "sticker.\(ext)" : info.filename,
                "mime": mime,
                "path": destination,
                "displayPath": destination,
                "preview": preview,
                "w": width,
                "h": height,
                "savedAt": Double(Date().timeIntervalSince1970)
            ]
            all.append(record)
            self.setPendingImportProgress(
                key: key,
                target: sourceOrigin,
                progress: 1.0
            )
            self.pending.remove(key)
            self.saveRecords(all)
            self.finishPendingImport(key: key)
        }
    }

    private func semanticGIFRecordMatches(
        _ record: [String: Any],
        target: String,
        mxc: String
    ) -> Bool {
        let recordTarget = ((record["target"] as? String)
            ?? (record["origin"] as? String)
            ?? "").lowercased()
        return recordTarget == target
            && (record["mxc"] as? String) == mxc
            && (record["sourceKind"] as? String)
                == "semantic-gif-to-real-sticker"
    }

    private func savedStickerRecordAssetsExist(
        _ record: [String: Any],
        target: String
    ) -> Bool {
        guard let sendPath = record["path"] as? String,
              FileManager.default.fileExists(atPath: sendPath) else {
            return false
        }
        let displayPath = (record["displayPath"] as? String) ?? sendPath
        guard FileManager.default.fileExists(atPath: displayPath) else {
            return false
        }

        if target == "telegram" {
            let mime = ((record["mime"] as? String) ?? "").lowercased()
            let ext = (sendPath.lowercased() as NSString).pathExtension

            return mime == "video/mp4" && ext == "mp4"
        }
        return true
    }

    private func removeSavedStickerRecordAssets(_ record: [String: Any]) {
        if let path = record["path"] as? String {
            try? FileManager.default.removeItem(atPath: path)
        }
        if let display = record["displayPath"] as? String {
            try? FileManager.default.removeItem(atPath: display)
        }
        if let preview = record["preview"] as? String {
            try? FileManager.default.removeItem(atPath: preview)
        }
    }

    private func prepareSemanticGIFSaveSlot(target: String, mxc: String) -> Bool {
        let current = records()
        var cleaned: [[String: Any]] = []
        var usableDuplicate = false
        var changed = false

        for record in current {
            if semanticGIFRecordMatches(record, target: target, mxc: mxc) {
                if savedStickerRecordAssetsExist(record, target: target) {
                    usableDuplicate = true
                    cleaned.append(record)
                } else {
                    removeSavedStickerRecordAssets(record)
                    changed = true
                }
            } else {
                cleaned.append(record)
            }
        }

        if changed { saveRecords(cleaned) }
        return usableDuplicate
    }

    func saveSemanticGIFAsSticker(
        mxc: String,
        target: String,
        width: Int,
        height: Int
    ) {
        let normalizedTarget = target.lowercased() == "telegram"
            ? "telegram"
            : "whatsapp"
        let key = recordKey(origin: normalizedTarget, mxc: mxc)

        if pending.contains(key) { return }
        if prepareSemanticGIFSaveSlot(target: normalizedTarget, mxc: mxc) {
            return
        }

        pending.insert(key)
        setPendingImportProgress(
            key: key,
            target: normalizedTarget,
            progress: 0.08
        )

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let token = "\(now)-\(Int.random(in: 0..<1_000_000))"
        let folder = (rootPath as NSString)
            .appendingPathComponent(normalizedTarget)
        let displayName = "gif-\(normalizedTarget)-display-\(token).webp"
        let displayPath = (folder as NSString)
            .appendingPathComponent(displayName)

        let sendName = normalizedTarget == "telegram"
            ? "gif-telegram-\(token).gif.mp4"
            : displayName
        let sendPath = normalizedTarget == "telegram"
            ? (folder as NSString).appendingPathComponent(sendName)
            : displayPath
        let preview = displayPath + ".preview.png"

        func discardNewAssets() {
            if sendPath != displayPath {
                try? FileManager.default.removeItem(atPath: sendPath)
            }
            try? FileManager.default.removeItem(atPath: displayPath)
            try? FileManager.default.removeItem(atPath: preview)
        }

        func failImport() {
            discardNewAssets()
            self.pending.remove(key)
            self.finishPendingImport(key: key)
        }

        func commitRecord(mime: String) {
            self.setPendingImportProgress(
                key: key,
                target: normalizedTarget,
                progress: 0.94
            )

            if let image = MediaCache.stickerLibraryPreview(path: displayPath),
               let png = image.pngData() {
                (png as NSData).write(toFile: preview, atomically: true)
            }

            if self.prepareSemanticGIFSaveSlot(
                target: normalizedTarget,
                mxc: mxc
            ) {
                failImport()
                return
            }

            var all = self.records()
            let record: [String: Any] = [
                "id": "\(normalizedTarget)-gif-\(token)",
                "origin": normalizedTarget,
                "target": normalizedTarget,
                "sourceKind": "semantic-gif-to-real-sticker",
                "mxc": mxc,
                "filename": sendName,
                "mime": mime,
                "path": sendPath,
                "displayPath": displayPath,
                "preview": preview,
                "w": width,
                "h": height,
                "savedAt": Double(Date().timeIntervalSince1970)
            ]
            all.append(record)
            self.setPendingImportProgress(
                key: key,
                target: normalizedTarget,
                progress: 1.0
            )
            self.pending.remove(key)
            self.saveRecords(all)
            self.finishPendingImport(key: key)
        }

        setPendingImportProgress(
            key: key,
            target: normalizedTarget,
            progress: 0.18
        )
        MediaCache.shared.exportVideoBackedAnimatedWebPAsSticker(
            mxc: mxc,
            destinationPath: displayPath
        ) { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                self.pending.remove(key)
                self.finishPendingImport(key: key)
                return
            }

            self.setPendingImportProgress(
                key: key,
                target: normalizedTarget,
                progress: 0.56
            )

            guard normalizedTarget == "telegram" else {
                commitRecord(mime: "image/webp")
                return
            }

            guard let transport = MediaCache.shared.videoBackedAnimatedInfo(for: mxc) else {
                failImport()
                return
            }

            let originalExt = (transport.filename.lowercased() as NSString).pathExtension
            let originalMime = transport.mimeType.lowercased()
            guard originalMime == "video/mp4" || originalExt == "mp4" else {
                failImport()
                return
            }

            MediaCache.shared.downloadFile(
                mxc: mxc,
                filename: transport.filename,
                mimeType: transport.mimeType,
                progress: { [weak self] fraction in
                    guard let self = self else { return }
                    self.setPendingImportProgress(
                        key: key,
                        target: normalizedTarget,
                        progress: 0.56 + min(Float(1), max(Float(0), fraction)) * 0.32
                    )
                }
            ) { [weak self] sourcePath in
                guard let self = self else { return }
                guard let sourcePath = sourcePath else {
                    failImport()
                    return
                }

                do {
                    try? FileManager.default.removeItem(atPath: sendPath)
                    try FileManager.default.copyItem(atPath: sourcePath, toPath: sendPath)
                    let attrs = try FileManager.default.attributesOfItem(atPath: sendPath)
                    let bytes = (attrs[.size] as? NSNumber)?.intValue ?? 0
                    guard bytes > 0 else {
                        failImport()
                        return
                    }
                    self.setPendingImportProgress(
                        key: key,
                        target: normalizedTarget,
                        progress: 0.90
                    )
                    commitRecord(mime: "video/mp4")
                } catch {
                    failImport()
                }
            }
        }
    }

    func items() -> [MagnistraSavedSticker] {
        var out: [MagnistraSavedSticker] = []
        for record in records().reversed() {
            guard let id = record["id"] as? String,
                  let mxc = record["mxc"] as? String,
                  let filename = record["filename"] as? String,
                  let mime = record["mime"] as? String,
                  let path = record["path"] as? String,
                  let preview = record["preview"] as? String else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let target = ((record["target"] as? String)
                ?? (record["origin"] as? String)
                ?? "whatsapp").lowercased() == "telegram"
                ? "telegram"
                : "whatsapp"

            let lowerMime = mime.lowercased()
            let ext = (filename.lowercased() as NSString).pathExtension
            let inferredTelegramOriginal = target == "telegram"
                && (lowerMime.contains("tgsticker")
                    || lowerMime.contains("lottie")
                    || lowerMime == "application/json"
                    || ext == "tgs"
                    || ext == "json")
            let sourceKind = (record["sourceKind"] as? String)
                ?? (inferredTelegramOriginal ? "telegram-original" : "native-sticker")
            let displayPath = (record["displayPath"] as? String) ?? path

            out.append(MagnistraSavedSticker(
                id: id,
                origin: target,
                mxc: mxc,
                sourceKind: sourceKind,
                filename: filename,
                mimeType: mime,
                path: path,
                displayPath: displayPath,
                previewPath: preview,
                width: (record["w"] as? NSNumber)?.intValue ?? 0,
                height: (record["h"] as? NSNumber)?.intValue ?? 0
            ))
        }
        return out
    }

    func remove(_ item: MagnistraSavedSticker) {
        var all = records()
        all.removeAll { ($0["id"] as? String) == item.id }
        saveRecords(all)

        try? FileManager.default.removeItem(atPath: item.path)
        if item.displayPath != item.path {
            try? FileManager.default.removeItem(atPath: item.displayPath)
        }
        try? FileManager.default.removeItem(atPath: item.previewPath)
    }
}