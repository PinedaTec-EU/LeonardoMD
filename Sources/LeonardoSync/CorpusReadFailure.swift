import Foundation

/// Safe snapshot diagnostics shared with an already-authorized project recipient.
/// Paths are relative to the granted selection; filesystem messages and absolute roots never cross HTTP.
public struct CorpusReadFailure: Error, Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case corpusTooLarge, fileTooLarge, tooManyFiles, sourceUnavailable
    }
    public let reason: Reason
    public let path: String?
    public let observed: Int?
    public let limit: Int?

    public init(reason: Reason, path: String? = nil, observed: Int? = nil, limit: Int? = nil) {
        self.reason = reason
        self.path = path.flatMap { candidate in
            (try? CorpusScope(folder: "").validate(candidate)) != nil ? candidate : nil
        }
        self.observed = observed.flatMap { $0 >= 0 ? $0 : nil }
        self.limit = limit.flatMap { $0 >= 0 ? $0 : nil }
    }

    private enum CodingKeys: String, CodingKey { case reason, path, observed, limit }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(reason: try container.decode(Reason.self, forKey: .reason),
                  path: try container.decodeIfPresent(String.self, forKey: .path),
                  observed: try container.decodeIfPresent(Int.self, forKey: .observed),
                  limit: try container.decodeIfPresent(Int.self, forKey: .limit))
    }

    static func check(size: Int, path: String, count: Int, bytes: Int, limits: CorpusLimits) throws {
        if size > limits.maximumFileBytes {
            throw Self(reason: .fileTooLarge, path: path, observed: size, limit: limits.maximumFileBytes)
        }
        if size > limits.maximumCorpusBytes - bytes {
            throw Self(reason: .corpusTooLarge, path: path, observed: bytes + size, limit: limits.maximumCorpusBytes)
        }
        if count >= limits.maximumFiles {
            throw Self(reason: .tooManyFiles, path: path, observed: count + 1, limit: limits.maximumFiles)
        }
    }
}
