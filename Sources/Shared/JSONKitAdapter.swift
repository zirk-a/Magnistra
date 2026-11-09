// Overview: Adapter exposing JSONKit for JSON parsing.
import Foundation

enum MagnistraJSONKit {
    struct ReadingOptions: OptionSet {
        let rawValue: UInt
        init(rawValue: UInt) { self.rawValue = rawValue }
        static let mutableContainers = ReadingOptions(rawValue: 1 << 0)
        static let mutableLeaves = ReadingOptions(rawValue: 1 << 1)
        static let fragmentsAllowed = ReadingOptions(rawValue: 1 << 2)
    }

    struct WritingOptions: OptionSet {
        let rawValue: UInt
        init(rawValue: UInt) { self.rawValue = rawValue }
        static let prettyPrinted = WritingOptions(rawValue: 1 << 0)
        static let sortedKeys = WritingOptions(rawValue: 1 << 1)
        static let fragmentsAllowed = WritingOptions(rawValue: 1 << 2)
        static let withoutEscapingSlashes = WritingOptions(rawValue: 1 << 3)
    }

    private static func unsupported(_ name: String) -> NSError {
        return NSError(domain: "MagnistraJSONKit", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Unsupported JSONKit compatibility option: " + name])
    }

    static func jsonObject(with data: Data, options: ReadingOptions = []) throws -> Any {
        if options.contains(.mutableLeaves) { throw unsupported("mutableLeaves") }
        if (options.rawValue & ~UInt(5)) != 0 { throw unsupported("unknown ReadingOptions") }
        var failure: NSError? = nil
        if let value = magnistra_jsonkit_decode(data,
               options.contains(.mutableContainers), options.contains(.fragmentsAllowed), &failure) {
            return value
        }
        throw failure ?? NSError(domain: "MagnistraJSONKit", code: 1,
           userInfo: [NSLocalizedDescriptionKey: "JSONKit decoding failed"])
    }

    static func data(withJSONObject value: Any, options: WritingOptions = []) throws -> Data {
        if options.contains(.sortedKeys) { throw unsupported("sortedKeys") }
        if (options.rawValue & ~UInt(13)) != 0 { throw unsupported("unknown WritingOptions") }
        var failure: NSError? = nil
        if let bytes = magnistra_jsonkit_encode(value as AnyObject,
             options.contains(.prettyPrinted), options.contains(.fragmentsAllowed), &failure) {
            return bytes as Data
        }
        throw failure ?? NSError(domain: "MagnistraJSONKit", code: 1,
           userInfo: [NSLocalizedDescriptionKey: "JSONKit serialization failed"])
    }

    static func isValidJSONObject(_ value: Any) -> Bool {
        guard value is [Any] || value is [String: Any] else { return false }
        return (try? data(withJSONObject: value)) != nil
    }
}
