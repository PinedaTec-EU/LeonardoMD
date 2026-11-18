import Foundation

/// Bundled descriptions of merged repository changes through PR #207.
public struct HistoricalReleaseNote: Decodable, Identifiable, Sendable {
    public let pr: Int
    public let en: String
    public let es: String

    public var id: Int { pr }
    public var url: URL {
        URL(string: "https://github.com/PinedaTec-EU/LeonardoMD/pull/\(pr)")!
    }

    public static let all: [Self] = {
        guard let url = Bundle.module.url(forResource: "HistoricalReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return notes
    }()

    public static let byPR = Dictionary(all.map { ($0.pr, $0) }, uniquingKeysWith: { first, _ in first })
}
