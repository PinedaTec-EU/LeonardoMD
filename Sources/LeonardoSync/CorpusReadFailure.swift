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
        self.reason = reason; self.path = path; self.observed = observed; self.limit = limit
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
