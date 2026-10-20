import Foundation

/// Locates whole Markdown images and their destinations without truncating
/// balanced or escaped parentheses. Masked source preserves UTF-16 offsets.
enum LeonardoMarkdownImageScanner {
    struct Image {
        let range: NSRange
        let destinationRange: NSRange?
        let destination: String?
        let referenceLabel: String?
    }

    static func images(in source: String, masked: String) -> [Image] {
        Scanner(source: source as NSString, units: Array(masked.utf16)).images()
    }

    static func unescape(_ text: String) -> String {
        let units = Array(text.utf16)
        var result: [UInt16] = []
        var index = 0
        while index < units.count {
            if units[index] == 92, index + 1 < units.count, isPunctuation(units[index + 1]) { index += 1 }
            result.append(units[index])
            index += 1
        }
        return String(decoding: result, as: UTF16.self)
    }

    private static func isPunctuation(_ unit: UInt16) -> Bool {
        (33...47).contains(unit) || (58...64).contains(unit) ||
        (91...96).contains(unit) || (123...126).contains(unit)
    }

    private struct Scanner {
        let source: NSString
        let units: [UInt16]

        func images() -> [Image] {
            var result: [Image] = []
            var index = 0
            while index + 1 < units.count {
                if units[index] == 92 { index += 2; continue }
                guard units[index] == 33, units[index + 1] == 91,
                      let image = image(at: index) else { index += 1; continue }
                result.append(image)
                index = NSMaxRange(image.range)
            }
            return result
        }

        private func image(at start: Int) -> Image? {
            guard let close = closingBracket(from: start + 1) else { return nil }
            let afterLabel = close + 1
            if afterLabel < units.count, units[afterLabel] == 40,
               let inline = inlineDestination(from: afterLabel + 1) {
                return Image(range: NSRange(location: start, length: inline.end - start),
                             destinationRange: inline.range,
                             destination: LeonardoMarkdownImageScanner.unescape(source.substring(with: inline.range)),
                             referenceLabel: nil)
            }
            var end = afterLabel
            var labelRange = NSRange(location: start + 2, length: close - start - 2)
            if afterLabel < units.count, units[afterLabel] == 91,
               let referenceClose = closingBracket(from: afterLabel) {
                end = referenceClose + 1
                if referenceClose > afterLabel + 1 {
                    labelRange = NSRange(location: afterLabel + 1, length: referenceClose - afterLabel - 1)
                }
            }
            return Image(range: NSRange(location: start, length: end - start),
                         destinationRange: nil, destination: nil, referenceLabel: source.substring(with: labelRange))
        }

        private func closingBracket(from start: Int) -> Int? {
            var depth = 1
            var index = start + 1
            while index < units.count {
                if units[index] == 92 { index += 2; continue }
                if units[index] == 91 { depth += 1 }
                if units[index] == 93 {
                    depth -= 1
                    if depth == 0 { return index }
                }
                index += 1
            }
            return nil
        }

        private func inlineDestination(from start: Int) -> (range: NSRange, end: Int)? {
            var index = skipWhitespace(from: start)
            guard index < units.count else { return nil }
            let range: NSRange
            if units[index] == 60 {
                let begin = index + 1
                index = begin
                while index < units.count, units[index] != 62 {
                    if units[index] == 60 || units[index] == 10 || units[index] == 13 { return nil }
                    if units[index] == 92, index + 1 < units.count { index += 2 } else { index += 1 }
                }
                guard index < units.count else { return nil }
                range = NSRange(location: begin, length: index - begin)
                index += 1
            } else {
                let begin = index
                var depth = 0
                while index < units.count {
                    let unit = units[index]
                    if unit == 92, index + 1 < units.count, LeonardoMarkdownImageScanner.isPunctuation(units[index + 1]) {
                        index += 2; continue
                    }
                    if isWhitespace(unit) || (unit == 41 && depth == 0) { break }
                    if unit == 60 { return nil }
                    if unit == 40 { depth += 1 }
                    if unit == 41 { depth -= 1 }
                    index += 1
                }
                guard depth == 0 else { return nil }
                range = NSRange(location: begin, length: index - begin)
            }
            let afterDestination = index
            index = skipWhitespace(from: index)
            guard index < units.count else { return nil }
            if units[index] != 41 {
                guard index > afterDestination, let titleEnd = titleEnd(from: index) else { return nil }
                index = skipWhitespace(from: titleEnd)
            }
            guard index < units.count, units[index] == 41 else { return nil }
            return (range, index + 1)
        }

        private func titleEnd(from start: Int) -> Int? {
            let opening = units[start]
            guard opening == 34 || opening == 39 || opening == 40 else { return nil }
            let closing: UInt16 = opening == 40 ? 41 : opening
            var index = start + 1
            while index < units.count {
                if units[index] == 92, index + 1 < units.count { index += 2; continue }
                if units[index] == closing { return index + 1 }
                index += 1
            }
            return nil
        }

        private func skipWhitespace(from start: Int) -> Int {
            var index = start
            while index < units.count, isWhitespace(units[index]) { index += 1 }
            return index
        }

        private func isWhitespace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 13 }
    }
}
