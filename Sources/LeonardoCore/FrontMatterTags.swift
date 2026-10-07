import Foundation

/// The string/list subset of YAML used for document tags. Nested metadata
/// cannot supply tags; malformed lists are ignored rather than searched as text.
enum FrontMatterTags {
    static func parse(_ lines: [String]) -> [String] {
        var rawValues: [String] = []
        var collecting = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if collecting, trimmed.hasPrefix("- ") {
                rawValues.append(String(trimmed.dropFirst(2)))
                continue
            }
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                collecting = false
                guard trimmed.hasPrefix("tags:") else { continue }
                let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                rawValues = []
                if value.isEmpty || value.hasPrefix("#") { collecting = true }
                else if value.hasPrefix("[") { rawValues = inlineList(value) ?? [] }
                else { rawValues = [value] }
            } else if collecting {
                guard trimmed.hasPrefix("- ") else { collecting = false; continue }
                rawValues.append(String(trimmed.dropFirst(2)))
            }
        }
        var seen = Set<String>()
        return rawValues.compactMap { raw in
            guard let value = scalar(raw), !value.isEmpty,
                  seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }
    }

    private static func inlineList(_ raw: String) -> [String]? {
        var values: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        var closed = false
        for character in raw.dropFirst() {
            if closed {
                if character == "#" { break }
                guard character.isWhitespace else { return nil }
            } else if escaped {
                token.append(character)
                escaped = false
            } else if character == "\\", quote == "\"" {
                token.append(character)
                escaped = true
            } else if let current = quote {
                token.append(character)
                if character == current { quote = nil }
            } else if character == "'", token.trimmingCharacters(in: .whitespaces).hasPrefix("'"), token.last == "'" {
                // Doubled apostrophes escape a quote inside YAML single-quoted scalars.
                token.append(character)
                quote = character
            } else if (character == "\"" || character == "'"), token.trimmingCharacters(in: .whitespaces).isEmpty {
                token.append(character)
                quote = character
            } else if character == "," || character == "]" {
                values.append(token)
                token = ""
                closed = character == "]"
            } else { token.append(character) }
        }
        return closed && quote == nil ? values : nil
    }

    private static func scalar(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") {
            // YAML's usual double-quoted string escapes are also JSON escapes.
            // Find the closing quote before an optional YAML comment.
            var escaped = false
            for index in value.indices.dropFirst() {
                let character = value[index]
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" {
                    guard validTail(String(value[value.index(after: index)...])) else { return nil }
                    return try? JSONDecoder().decode(String.self, from: Data(value[...index].utf8))
                }
            }
            return nil
        }
        if value.hasPrefix("'") {
            var result = ""
            var index = value.index(after: value.startIndex)
            while index < value.endIndex {
                let character = value[index]
                let next = value.index(after: index)
                if character == "'" {
                    if next < value.endIndex, value[next] == "'" {
                        result.append("'"); index = value.index(after: next); continue
                    }
                    return validTail(String(value[next...])) ? result : nil
                }
                result.append(character)
                index = next
            }
            return nil
        }
        guard !value.hasPrefix("[") && !value.hasPrefix("{") else { return nil }
        let plain = value.components(separatedBy: " #").first ?? value
        return plain.trimmingCharacters(in: .whitespaces)
    }

    private static func validTail(_ tail: String) -> Bool {
        let trimmed = tail.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("#")
    }
}
