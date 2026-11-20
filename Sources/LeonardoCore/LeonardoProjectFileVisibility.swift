import Foundation

/// Shared file-list policy for the formats Leonardo can present as documents.
public enum LeonardoProjectFileVisibility {
    public enum Surface: Hashable, Sendable {
        case macOS
        case littleLeonardo
    }

    public static let showNonDocumentFilesPreferenceKey = "showNonDocumentFiles"

    private static let macOSDocumentExtensions: Set<String> = [
        "md", "markdown", "txt", "mdlf", "mdlr", "mdlz"
    ]
    private static let littleLeonardoDocumentExtensions: Set<String> = [
        "md", "markdown", "txt", "mdlf", "mdlr"
    ]

    public static func isSupportedDocumentExtension(_ fileExtension: String, on surface: Surface = .macOS) -> Bool {
        let supportedExtensions = surface == .littleLeonardo
            ? littleLeonardoDocumentExtensions
            : macOSDocumentExtensions
        return supportedExtensions.contains(fileExtension.lowercased())
    }

    public static func shouldShowFile(
        at path: String,
        showNonDocumentFiles: Bool,
        on surface: Surface = .macOS
    ) -> Bool {
        showNonDocumentFiles || isSupportedDocumentExtension((path as NSString).pathExtension, on: surface)
    }
}
