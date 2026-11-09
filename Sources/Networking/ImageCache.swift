// Overview: Disk image cache: paths, hashing and cache limits.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


    static func documentsPath()
        -> String? {
        let dirs =
            NSSearchPathForDirectoriesInDomains(
                .documentDirectory,
                .userDomainMask,
                true
            )

        return dirs.first
    }

    static func cacheRoot()
        -> String? {
        let dirs =
            NSSearchPathForDirectoriesInDomains(
                .cachesDirectory,
                .userDomainMask,
                true
            )

        guard let root = dirs.first else {
            return nil
        }

        let path =
            (root as NSString)
                .appendingPathComponent(
                    "MagnistraMedia"
                )

        if !FileManager.default.fileExists(
            atPath: path
        ) {
            try? FileManager.default
                .createDirectory(
                    atPath: path,
                    withIntermediateDirectories:
                        true,
                    attributes: nil
                )
        }

        return path
    }

    static func cacheDirectory(
        kind: MagnistraMediaCacheKind
    ) -> String? {
        guard let root =
            cacheRoot()
        else {
            return nil
        }

        let leaf: String

        switch kind {
        case .avatar:
            leaf = "avatars"
        case .post:
            leaf = "posts"
        }

        let path =
            (root as NSString)
                .appendingPathComponent(
                    leaf
                )

        if !FileManager.default.fileExists(
            atPath: path
        ) {
            try? FileManager.default
                .createDirectory(
                    atPath: path,
                    withIntermediateDirectories:
                        true,
                    attributes: nil
                )
        }

        return path
    }

    static func stableHash(
        _ value: String
    ) -> String {
        var hash:
            UInt64 =
                1469598103934665603

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &*
                1099511628211
        }

        var result =
            String(
                hash,
                radix: 16,
                uppercase: false
            )

        while result.count < 16 {
            result = "0" + result
        }

        return result
    }

    static func cachePath(
        kind: MagnistraMediaCacheKind,
        stableKey: String
    ) -> String? {
        let isMetricTrackingEnabled = MagnistraExploreCounters.active
        let metricStartedAt: TimeInterval = isMetricTrackingEnabled ? MagnistraFeedTiming.now() : 0.0
        defer { if isMetricTrackingEnabled { MagnistraExploreCounters.add("CACHE_PATH", metricStartedAt) } }

        guard let root =
            cacheDirectory(
                kind: kind
            )
        else {
            return nil
        }

        let name =
            stableHash(
                stableKey
            ) + ".img"

        return
            (root as NSString)
                .appendingPathComponent(
                    name
                )
    }

    static func cacheLimits(
        kind: MagnistraMediaCacheKind
    ) -> (
        maxBytes: Int,
        maxEntries: Int,
        ttl: TimeInterval
    ) {
        switch kind {
        case .avatar:
            return (
                avatarCacheMaxBytes,
                avatarCacheMaxEntries,
                avatarTTL
            )

        case .post:
            return (
                postCacheMaxBytes,
                postCacheMaxEntries,
                0.0
            )
        }
    }

    static func touchCacheFile(
        _ path: String
    ) {
        try? FileManager.default
            .setAttributes(
                [
                    .modificationDate:
                        Date()
                ],
                ofItemAtPath: path
            )
    }

    static func cachedImageIsUsable(
        _ path: String
    ) -> Bool {
        guard let image =
            UIImage(
                contentsOfFile: path
            )
        else {
            return false
        }

        return
            image.size.width > 0 &&
            image.size.height > 0
    }

    static func freshCachePath(
        path: String,
        ttl: TimeInterval
    ) -> String? {
        guard
            FileManager.default.fileExists(
                atPath: path
            ),
            cachedImageIsUsable(path)
        else {
            return nil
        }

        if ttl > 0 {
            let attrs =
                try? FileManager.default
                    .attributesOfItem(
                        atPath: path
                    )

            let created =
                attrs?[.creationDate]
                    as? Date

            if
                let created = created,
                Date()
                    .timeIntervalSince(
                        created
                    ) > ttl
            {
                return nil
            }
        }

        touchCacheFile(path)

        return path
    }

    static func staleCachePath(
        path: String
    ) -> String? {
        guard
            FileManager.default.fileExists(
                atPath: path
            ),
            cachedImageIsUsable(path)
        else {
            return nil
        }

        touchCacheFile(path)

        return path
    }

    static func enforceCacheBudget(
        kind: MagnistraMediaCacheKind
    ) {
        guard let root =
            cacheDirectory(
                kind: kind
            )
        else {
            return
        }

        let limits =
            cacheLimits(
                kind: kind
            )

        guard let names =
            try? FileManager.default
                .contentsOfDirectory(
                    atPath: root
                )
        else {
            return
        }

        var rows:
            [
                (
                    path: String,
                    size: Int,
                    lastUse: Date
                )
            ] = []

        var totalBytes = 0

        for name in names {
            if !name.hasSuffix(".img") {
                continue
            }

            let path =
                (root as NSString)
                    .appendingPathComponent(
                        name
                    )

            guard let attrs =
                try? FileManager.default
                    .attributesOfItem(
                        atPath: path
                    )
            else {
                continue
            }

            let size =
                (
                    attrs[.size]
                        as? NSNumber
                )?.intValue ?? 0

            let lastUse =
                (
                    attrs[.modificationDate]
                        as? Date
                ) ?? Date(
                    timeIntervalSince1970: 0
                )

            totalBytes += size

            rows.append(
                (
                    path: path,
                    size: size,
                    lastUse: lastUse
                )
            )
        }

        rows.sort {
            $0.lastUse < $1.lastUse
        }

        var entryCount =
            rows.count

        var index = 0

        while
            (
                totalBytes >
                    limits.maxBytes ||
                entryCount >
                    limits.maxEntries
            ) &&
            index < rows.count
        {
            let row =
                rows[index]

            try? FileManager.default
                .removeItem(
                    atPath: row.path
                )

            totalBytes -= row.size
            entryCount -= 1
            index += 1
        }
    }
}
