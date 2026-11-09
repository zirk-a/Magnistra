// Overview: Timing and counters used for feed diagnostics.
import Foundation
import UIKit

enum MagnistraFeedTiming {
    private static let lock = NSLock()
    private static var requestedAt: [String: TimeInterval] = [:]

    static func now() -> TimeInterval { return Date.timeIntervalSinceReferenceDate }

    static func mark(_ feed: String, _ phase: String, _ started: TimeInterval) {
        let elapsed = max(0.0, (now() - started) * 1000.0)
        NSLog("MAGNISTRA_FEED_TIMING feed=%@ phase=%@ elapsed_ms=%.1f", feed, phase, elapsed)
    }

    static func begin(_ feed: String) {
        lock.lock()
        requestedAt[feed] = now()
        lock.unlock()
        NSLog("MAGNISTRA_FEED_TIMING feed=%@ phase=REQUEST_BEGIN", feed)
    }

    static func apply(_ feed: String) {
        lock.lock()
        let started = requestedAt[feed]
        lock.unlock()
        if let value = started { mark(feed, "REQUEST_TO_APPLY", value) }
    }
}

enum MagnistraExploreCounters {
    private static let prefix = "magnistra.r36."
    private static let phases: [String] = [
        "META_TOTAL", "META_INDEX", "META_STRING", "META_INTEGER", "META_DICTIONARY",
        "META_REPOST", "DISPLAY_NORMALIZE", "IMAGE_SELECT", "CACHE_LOOKUP",
        "CACHE_PATH", "IMAGE_MATERIALIZE"
    ]
    static var active: Bool {
        return Thread.current.threadDictionary[prefix + "active"] != nil
    }
    static func begin() {
        let td = Thread.current.threadDictionary
        td[prefix + "active"] = true
        for phase in phases {
            td.removeObject(forKey: prefix + phase + ".ms")
            td.removeObject(forKey: prefix + phase + ".n")
        }
    }
    static func add(_ phase: String, _ started: TimeInterval) {
        let td = Thread.current.threadDictionary
        guard td[prefix + "active"] != nil else { return }
        let elapsed = max(0.0, (MagnistraFeedTiming.now() - started) * 1000.0)
        let sumKey = prefix + phase + ".ms"
        let numKey = prefix + phase + ".n"
        let oldMs = (td[sumKey] as? NSNumber)?.doubleValue ?? 0.0
        let oldN = (td[numKey] as? NSNumber)?.intValue ?? 0
        td[sumKey] = NSNumber(value: oldMs + elapsed)
        td[numKey] = NSNumber(value: oldN + 1)
    }
    static func finish() {
        let td = Thread.current.threadDictionary
        guard td[prefix + "active"] != nil else { return }
        for phase in phases {
            let sumKey = prefix + phase + ".ms"
            let numKey = prefix + phase + ".n"
            if let number = td[numKey] as? NSNumber, number.intValue > 0 {
                let ms = (td[sumKey] as? NSNumber)?.doubleValue ?? 0.0
                NSLog("MAGNISTRA_FEED_TIMING feed=EXPLORE phase=%@ elapsed_ms=%.1f", phase, ms)
                NSLog("MAGNISTRA_FEED_TIMING feed=EXPLORE phase=%@_COUNT elapsed_ms=%.1f", phase, Double(number.intValue))
            }
            td.removeObject(forKey: sumKey)
            td.removeObject(forKey: numKey)
        }
        td.removeObject(forKey: prefix + "active")
    }
}
