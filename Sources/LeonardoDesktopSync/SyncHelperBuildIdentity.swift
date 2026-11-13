#if os(macOS)
import Foundation

/// Captured once when the process starts, rather than reading an updated bundle
/// later and mistaking the still-running old executable for the replacement.
public struct SyncHelperBuildIdentity: Codable, Equatable, Sendable {
    public let build: Int
    public let bundlePath: String
    public init(build: Int, bundlePath: String) {
        self.build = build
        self.bundlePath = bundlePath
    }
    public init?(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL),
              let text = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let build = Int(text), build > 0 else { return nil }
        self.init(build: build, bundlePath: bundleURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }
    public func needsReplacement(by expected: Self) -> Bool {
        // Opening an older editor must never downgrade a newer running helper.
        build < expected.build || (build == expected.build && bundlePath != expected.bundlePath)
    }
}
#endif
