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

    struct ReferenceDefinition {
        let range: NSRange
        let label: String
        let destinationRange: NSRange
        let destination: String
    }

    private static let definitionLine = try! NSRegularExpression(
        pattern: #"(?m)^ {0,3}\[((?:\\.|[^\]\\\r\n])+)\]:[ \t]*([^\r\n]*)(?:\r?\n|$)"#
    )

    static func referenceDefinitions(in source: String, masked: String) -> [ReferenceDefinition] {
        Scanner(source: source as NSString, units: Array(masked.utf16)).referenceDefinitions(in: masked)
    }

    static func images(in source: String, masked: String) -> [Image] {
        Scanner(source: source as NSString, units: Array(masked.utf16)).images()
    }

    static func referenceLabels(in source: String) -> [String] {
        Scanner(source: source as NSString, units: Array(source.utf16)).referenceLabels()
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
                if units[index] == 60, let end = htmlTagEnd(from: index) { index = end; continue }
                guard units[index] == 33, units[index + 1] == 91,
                      let image = image(at: index) else { index += 1; continue }
                result.append(image)
                index = NSMaxRange(image.range)
            }
            return result
        }

        func referenceDefinitions(in masked: String) -> [ReferenceDefinition] {
            LeonardoMarkdownImageScanner.definitionLine.matches(in: masked, range: NSRange(masked.startIndex..., in: masked)).compactMap { match in
                let remainder = match.range(at: 2)
                guard let value = destination(from: remainder.location, limit: NSMaxRange(remainder), requiresClosingParenthesis: false) else { return nil }
                return ReferenceDefinition(range: match.range, label: source.substring(with: match.range(at: 1)),
                                           destinationRange: value.range,
                                           destination: LeonardoMarkdownImageScanner.unescape(source.substring(with: value.range)))
            }
        }

        func referenceLabels() -> [String] {
            var result: [String] = []
            var index = 0
            while index < units.count {
                if units[index] == 92 { index += 2; continue }
                if units[index] == 60, let end = htmlTagEnd(from: index) { index = end; continue }
                guard units[index] == 91, let link = syntax(bracket: index, start: index) else { index += 1; continue }
                if let label = link.referenceLabel { result.append(label) }
                index = NSMaxRange(link.range)
            }
            return result
        }

        private func htmlTagEnd(from start: Int) -> Int? {
            LeonardoHTMLImageScanner.tag(at: start, units: units)?.end
        }

        private func image(at start: Int) -> Image? { syntax(bracket: start + 1, start: start) }

        private func syntax(bracket: Int, start: Int) -> Image? {
            guard let close = closingBracket(from: bracket) else { return nil }
            let afterLabel = close + 1
            if afterLabel < units.count, units[afterLabel] == 40,
               let inline = destination(from: afterLabel + 1, limit: units.count, requiresClosingParenthesis: true) {
                return Image(range: NSRange(location: start, length: inline.end - start),
                             destinationRange: inline.range,
                             destination: LeonardoMarkdownImageScanner.unescape(source.substring(with: inline.range)),
                             referenceLabel: nil)
            }
            var end = afterLabel
            var labelRange = NSRange(location: bracket + 1, length: close - bracket - 1)
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

        private func destination(from start: Int, limit: Int, requiresClosingParenthesis: Bool) -> (range: NSRange, end: Int)? {
            var index = skipWhitespace(from: start, limit: limit)
            guard index < limit else { return nil }
            let range: NSRange
            if units[index] == 60 {
                let begin = index + 1
                index = begin
                while index < limit, units[index] != 62 {
                    if units[index] == 60 || units[index] == 10 || units[index] == 13 { return nil }
                    if units[index] == 92, index + 1 < limit { index += 2 } else { index += 1 }
                }
                guard index < limit else { return nil }
                range = NSRange(location: begin, length: index - begin)
                index += 1
            } else {
                let begin = index
                var depth = 0
                while index < limit {
                    let unit = units[index]
                    if unit == 92, index + 1 < limit, LeonardoMarkdownImageScanner.isPunctuation(units[index + 1]) {
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
            guard let end = destinationEnd(after: index, limit: limit, requiresClosingParenthesis: requiresClosingParenthesis) else { return nil }
            return (range, end)
        }

        private func destinationEnd(after destination: Int, limit: Int, requiresClosingParenthesis: Bool) -> Int? {
            var index = skipWhitespace(from: destination, limit: limit)
            if !requiresClosingParenthesis, index == limit { return index }
            guard index < limit else { return nil }
            if !requiresClosingParenthesis || units[index] != 41 {
                guard index > destination, let end = titleEnd(from: index, limit: limit) else { return nil }
                index = skipWhitespace(from: end, limit: limit)
            }
            if requiresClosingParenthesis {
                return index < limit && units[index] == 41 ? index + 1 : nil
            }
            return index == limit ? index : nil
        }

        private func titleEnd(from start: Int, limit: Int) -> Int? {
            let opening = units[start]
            guard opening == 34 || opening == 39 || opening == 40 else { return nil }
            let closing: UInt16 = opening == 40 ? 41 : opening
            var index = start + 1
            while index < limit {
                if units[index] == 92, index + 1 < limit { index += 2; continue }
                if units[index] == closing { return index + 1 }
                index += 1
            }
            return nil
        }

        private func skipWhitespace(from start: Int, limit: Int) -> Int {
            var index = start
            while index < limit, isWhitespace(units[index]) { index += 1 }
            return index
        }

        private func isWhitespace(_ unit: UInt16) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 13 }
    }
}
