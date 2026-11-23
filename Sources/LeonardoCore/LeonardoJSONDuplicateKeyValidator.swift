import Foundation

/// Finds duplicate JSON object members before Foundation converts objects to
/// dictionaries.  JSONSerialization and JSONDecoder are deliberately still
/// authoritative for the complete JSON grammar; this scanner only walks far
/// enough to identify object keys and their nested values.
enum LeonardoJSONDuplicateKeyValidator {
    private static let maximumNesting = 512

    static func validate(_ source: String) throws {
        var scanner = Scanner(bytes: Array(source.utf8))
        try scanner.validate()
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        mutating func validate() throws {
            skipWhitespace()
            guard try scanValue(depth: 0) else { throw LeonardoFormatError.invalidMetadataJSON }
            skipWhitespace()
            // Do not let a Foundation-specific grammar extension bypass
            // the traversal of every object and its keys.
            guard index == bytes.count else { throw LeonardoFormatError.invalidMetadataJSON }
        }

        private mutating func scanValue(depth: Int) throws -> Bool {
            guard depth <= LeonardoJSONDuplicateKeyValidator.maximumNesting else {
                throw LeonardoFormatError.invalidMetadataJSON
            }
            skipWhitespace()
            guard index < bytes.count else { return false }
            switch bytes[index] {
            case 0x22: // string
                return scanString(decode: false) != nil
            case 0x7B: // object
                return try scanObject(depth: depth + 1)
            case 0x5B: // array
                return try scanArray(depth: depth + 1)
            case 0x2D, 0x30...0x39:
                return scanNumber()
            case 0x74:
                return consume([0x74, 0x72, 0x75, 0x65]) // true
            case 0x66:
                return consume([0x66, 0x61, 0x6C, 0x73, 0x65]) // false
            case 0x6E:
                return consume([0x6E, 0x75, 0x6C, 0x6C]) // null
            default:
                return false
            }
        }

        private mutating func scanObject(depth: Int) throws -> Bool {
            guard depth <= LeonardoJSONDuplicateKeyValidator.maximumNesting else {
                throw LeonardoFormatError.invalidMetadataJSON
            }
            guard consume(0x7B) else { return false }
            var keys = Set<String>()
            skipWhitespace()
            if consume(0x7D) { return true }

            while true {
                skipWhitespace()
                guard let key = scanString(decode: true) else { return false }
                guard keys.insert(key).inserted else {
                    throw LeonardoFormatError.invalidMetadataJSON
                }
                skipWhitespace()
                guard consume(0x3A) else { return false }
                guard try scanValue(depth: depth) else { return false }
                skipWhitespace()
                if consume(0x7D) { return true }
                guard consume(0x2C) else { return false }
            }
        }

        private mutating func scanArray(depth: Int) throws -> Bool {
            guard depth <= LeonardoJSONDuplicateKeyValidator.maximumNesting else {
                throw LeonardoFormatError.invalidMetadataJSON
            }
            guard consume(0x5B) else { return false }
            skipWhitespace()
            if consume(0x5D) { return true }

            while true {
                guard try scanValue(depth: depth) else { return false }
                skipWhitespace()
                if consume(0x5D) { return true }
                guard consume(0x2C) else { return false }
            }
        }

        /// Scans a JSON string without interpreting its contents unless it is
        /// an object key. This keeps escaped quotes and unicode escapes from
        /// being mistaken for delimiters while leaving grammar validation to
        /// Foundation.
        private mutating func scanString(decode: Bool) -> String? {
            guard consume(0x22) else { return nil }
            let start = index - 1
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case 0x22:
                    index += 1
                    guard decode else { return "" }
                    let raw = Data(bytes[start..<index])
                    do {
                        let value = try JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed])
                        return value as? String
                    } catch {
                        return nil
                    }
                case 0x5C:
                    index += 1
                    guard index < bytes.count else { return nil }
                    switch bytes[index] {
                    case 0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74:
                        index += 1
                    case 0x75:
                        index += 1
                        guard index + 4 <= bytes.count else { return nil }
                        guard bytes[index..<(index + 4)].allSatisfy(Self.isHexDigit) else { return nil }
                        index += 4
                    default:
                        return nil
                    }
                default:
                    guard byte >= 0x20 else { return nil }
                    index += 1
                }
            }
            return nil
        }

        private mutating func scanNumber() -> Bool {
            let start = index
            _ = consume(0x2D)
            guard index < bytes.count else { return false }
            if consume(0x30) {
                // A leading zero cannot be followed by another integer digit.
                if index < bytes.count, bytes[index].isASCIIDigit { return false }
            } else {
                guard index < bytes.count, bytes[index] >= 0x31, bytes[index] <= 0x39 else { return false }
                repeat { index += 1 } while index < bytes.count && bytes[index].isASCIIDigit
            }
            if consume(0x2E) {
                guard index < bytes.count, bytes[index].isASCIIDigit else { return false }
                repeat { index += 1 } while index < bytes.count && bytes[index].isASCIIDigit
            }
            if index < bytes.count, (bytes[index] == 0x65 || bytes[index] == 0x45) {
                index += 1
                _ = consume(0x2B) || consume(0x2D)
                guard index < bytes.count, bytes[index].isASCIIDigit else { return false }
                repeat { index += 1 } while index < bytes.count && bytes[index].isASCIIDigit
            }
            return index > start
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        private mutating func consume(_ expected: [UInt8]) -> Bool {
            guard index + expected.count <= bytes.count,
                  bytes[index..<(index + expected.count)].elementsEqual(expected) else { return false }
            index += expected.count
            return true
        }

        private mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D: index += 1
                default: return
                }
            }
        }

        private static func isHexDigit(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39) ||
            (byte >= 0x41 && byte <= 0x46) ||
            (byte >= 0x61 && byte <= 0x66)
        }
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { self >= 0x30 && self <= 0x39 }
}
