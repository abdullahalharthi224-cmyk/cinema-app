import Foundation

/// Addons in the wild are written by many different people and their JSON is
/// not always tidy. These helpers make decoding forgiving: a single malformed
/// field or array element never makes a whole addon unusable.

struct SkipDecodable: Decodable {
    init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// Decodes an optional value, treating type mismatches as `nil`.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Decodes an array, silently dropping elements that fail to decode.
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard contains(key), var container = try? nestedUnkeyedContainer(forKey: key) else {
            return nil
        }
        var result: [T] = []
        while !container.isAtEnd {
            if let value = try? container.decode(T.self) {
                result.append(value)
            } else if (try? container.decode(SkipDecodable.self)) == nil {
                break
            }
        }
        return result
    }

    /// Decodes a value that may be sent as a string or a number (e.g. `"7.4"` or `7.4`).
    func flexibleString(forKey key: Key) -> String? {
        if let string = lenient(String.self, forKey: key) { return string }
        if let int = lenient(Int.self, forKey: key) { return String(int) }
        if let double = lenient(Double.self, forKey: key) { return String(double) }
        return nil
    }

    /// Decodes a boolean that may be sent as `true`, `1` or `"true"`.
    func flexibleBool(forKey key: Key) -> Bool? {
        if let bool = lenient(Bool.self, forKey: key) { return bool }
        if let int = lenient(Int.self, forKey: key) { return int != 0 }
        if let string = lenient(String.self, forKey: key) { return string.lowercased() == "true" }
        return nil
    }
}
