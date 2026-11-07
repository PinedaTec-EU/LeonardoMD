import Foundation
import LeonardoCore

/// Personal practice is intentionally outside the authenticated corpus/cache.
struct MobileDemoStore {
    enum Language: String, CaseIterable, Identifiable {
        case es, en
        var id: String { rawValue }
        var title: String { self == .es ? "Español" : "English" }
    }

    let root: URL
    let resources: URL

    init(root: URL? = nil, resources: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Demo/v1", isDirectory: true)
        self.resources = resources ?? Bundle.main.bundleURL.appendingPathComponent("Demo", isDirectory: true)
    }

    func url(for language: Language) -> URL {
        root.appendingPathComponent("Demo-\(language.rawValue).mdlr")
    }

    func template(_ language: Language) throws -> String {
        let text = try String(contentsOf: resources.appendingPathComponent("Demo-\(language.rawValue).mdlr"), encoding: .utf8)
        _ = try LeonardoFormatParser.parse(text)
        return text
    }

    /// Bootstrap only missing copies; malformed personal data is never overwritten.
    func load(_ language: Language) throws -> String {
        let destination = url(for: language)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try save(template(language), language: language)
        }
        let text = try String(contentsOf: destination, encoding: .utf8)
        _ = try LeonardoFormatParser.parse(text)
        return text
    }

    func save(_ text: String, language: Language) throws {
        _ = try LeonardoFormatParser.parse(text)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try text.write(to: url(for: language), atomically: true, encoding: .utf8)
    }

    func reset(_ language: Language) throws -> String {
        let text = try template(language)
        try save(text, language: language)
        return text
    }
}
