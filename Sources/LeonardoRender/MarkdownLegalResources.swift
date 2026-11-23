import Foundation

/// Offline disclosures from the same resource bundle as the rendering engines.
/// Consumers reuse these files instead of maintaining a second vendored copy.
public enum MarkdownLegalResources {
    public static var noticesURL: URL? {
        Bundle.module.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt")
    }

    public static var licenseURLs: [URL] {
        let flattened = Bundle.module.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []
        let nested = Bundle.module.urls(forResourcesWithExtension: "txt", subdirectory: "licenses") ?? []
        return Array(Set((flattened + nested).map { $0 as URL }))
            .filter { $0.lastPathComponent != "THIRD_PARTY_NOTICES.txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
