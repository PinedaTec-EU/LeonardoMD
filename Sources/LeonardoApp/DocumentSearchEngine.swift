import Foundation

struct DocumentSearchSource: Sendable {
    let tabID: UUID
    let documentTitle: String
    let text: String
}

struct DocumentSearchInput: Sendable {
    let query: String
    let usesRegularExpression: Bool
    let matchCase: Bool
    let sources: [DocumentSearchSource]
}

struct DocumentSearchResult: Sendable {
    let matches: [DocumentSearchMatch]
    let hasInvalidRegularExpression: Bool
}

actor DocumentSearchExecutor {
    static let shared = DocumentSearchExecutor()

    func search(_ input: DocumentSearchInput) -> DocumentSearchResult {
        DocumentSearchEngine.search(input)
    }
}

enum DocumentSearchEngine {
    static func search(_ input: DocumentSearchInput) -> DocumentSearchResult {
        let pattern = input.usesRegularExpression
            ? input.query
            : NSRegularExpression.escapedPattern(for: input.query)
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !input.matchCase { options.insert(.caseInsensitive) }

        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return DocumentSearchResult(matches: [], hasInvalidRegularExpression: input.usesRegularExpression)
        }

        var matches: [DocumentSearchMatch] = []
        for source in input.sources {
            if Task.isCancelled { return DocumentSearchResult(matches: [], hasInvalidRegularExpression: false) }
            let fullRange = NSRange(location: 0, length: (source.text as NSString).length)
            expression.enumerateMatches(in: source.text, range: fullRange) { result, _, stop in
                guard !Task.isCancelled else {
                    stop.pointee = true
                    return
                }
                guard let result else { return }
                matches.append(DocumentSearchMatch(
                    id: .init(tabID: source.tabID, location: result.range.location, length: result.range.length),
                    tabID: source.tabID,
                    documentTitle: source.documentTitle,
                    location: result.range.location,
                    length: result.range.length
                ))
            }
        }
        return DocumentSearchResult(matches: matches, hasInvalidRegularExpression: false)
    }
}
