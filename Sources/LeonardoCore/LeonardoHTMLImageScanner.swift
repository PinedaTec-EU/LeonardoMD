import Foundation

/// Reads HTML image tags and attributes while respecting quoted delimiters.
enum LeonardoHTMLImageScanner {
    struct Image {
        let range: NSRange
        let destinationRange: NSRange?
        let destination: String?
    }

    struct Tag {
        let name: String?
        let nameEnd: Int
        let end: Int
        let isClosing: Bool
    }

    static func images(in source: String, masked: String) -> [Image] {
        let units = Array(masked.utf16)
        let original = source as NSString
        var result: [Image] = []
        var index = 0
        while index + 1 < units.count {
            guard units[index] == 60 else { index += 1; continue }
            guard let tag = tag(at: index, units: units) else { index += 1; continue }
            if !tag.isClosing, tag.name == "img" {
                let destination = sourceRange(from: tag.nameEnd, to: tag.end - 1, units: units)
                result.append(Image(range: NSRange(location: index, length: tag.end - index),
                                    destinationRange: destination,
                                    destination: destination.map { decodeEntities(original.substring(with: $0)) }))
            }
            index = tag.end
        }
        return result
    }

    static func tag(at start: Int, units: [UInt16]) -> Tag? {
        guard start + 1 < units.count, units[start] == 60 else { return nil }
        if start + 3 < units.count, Array(units[start..<(start + 4)]) == [60, 33, 45, 45] {
            var end = start + 4
            while end + 2 < units.count {
                if units[end] == 45, units[end + 1] == 45, units[end + 2] == 62 {
                    return Tag(name: nil, nameEnd: start + 4, end: end + 3, isClosing: false)
                }
                end += 1
            }
            return Tag(name: nil, nameEnd: start + 4, end: units.count, isClosing: false)
        }
        var begin = start + 1
        let closing = units[begin] == 47
        if closing { begin += 1 }
        guard begin < units.count, (65...90).contains(units[begin]) || (97...122).contains(units[begin]) else { return nil }
        var nameEnd = begin
        while nameEnd < units.count, !isWhitespace(units[nameEnd]), units[nameEnd] != 47, units[nameEnd] != 62 { nameEnd += 1 }
        guard let end = tagEnd(from: nameEnd, units: units) else { return nil }
        return Tag(name: String(decoding: units[begin..<nameEnd], as: UTF16.self).lowercased(),
                   nameEnd: nameEnd, end: end + 1, isClosing: closing)
    }

    private static func tagEnd(from start: Int, units: [UInt16]) -> Int? {
        var quote: UInt16?
        for index in start..<units.count {
            let unit = units[index]
            if let current = quote {
                if unit == current { quote = nil }
            } else if unit == 34 || unit == 39 { quote = unit }
            else if unit == 62 { return index }
        }
        return nil
    }

    private static func sourceRange(from start: Int, to end: Int, units: [UInt16]) -> NSRange? {
        var index = start
        while index < end {
            while index < end, isWhitespace(units[index]) || units[index] == 47 { index += 1 }
            let nameStart = index
            while index < end, !isWhitespace(units[index]), units[index] != 61, units[index] != 47 { index += 1 }
            let name = String(decoding: units[nameStart..<index], as: UTF16.self).lowercased()
            while index < end, isWhitespace(units[index]) { index += 1 }
            guard index < end else { break }
            guard units[index] == 61 else { continue }
            index += 1
            while index < end, isWhitespace(units[index]) { index += 1 }
            guard index < end else { break }
            let range: NSRange
            if units[index] == 34 || units[index] == 39 {
                let quote = units[index]
                index += 1
                let begin = index
                while index < end, units[index] != quote { index += 1 }
                range = NSRange(location: begin, length: index - begin)
                if index < end { index += 1 }
            } else {
                let begin = index
                while index < end, !isWhitespace(units[index]) { index += 1 }
                range = NSRange(location: begin, length: index - begin)
            }
            if name == "src" { return range }
        }
        return nil
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9 || unit == 10 || unit == 13 || unit == 12
    }

    private static func decodeEntities(_ text: String) -> String {
        let entities = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "colon": ":", "AMP": "&", "QUOT": "\"", "LT": "<", "GT": ">"]
        let expression = try! NSRegularExpression(pattern: #"&(#(?:x|X)[0-9a-fA-F]+|#[0-9]+|amp|quot|apos|lt|gt|colon|AMP|QUOT|LT|GT);"#)
        let result = NSMutableString(string: text)
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let value = (text as NSString).substring(with: match.range(at: 1))
            let replacement: String?
            if (value.hasPrefix("#x") || value.hasPrefix("#X")), let number = UInt32(value.dropFirst(2), radix: 16), let scalar = UnicodeScalar(number) {
                replacement = String(scalar)
            } else if value.hasPrefix("#"), let number = UInt32(value.dropFirst()), let scalar = UnicodeScalar(number) {
                replacement = String(scalar)
            } else { replacement = entities[value] }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }
}
