import AppKit
import UniformTypeIdentifiers

@MainActor
protocol MarkdownAssociationDriver {
    var isAvailable: Bool { get }
    func isDefault() throws -> Bool
    func makeDefault() async throws
}

/// Launch Services is accessed only here; tests never change the user's defaults.
@MainActor
struct WorkspaceMarkdownAssociationDriver: MarkdownAssociationDriver {
    static let bundleIdentifier = "eu.pinedatec.LeonardoMD"
    static let documentTypes = [
        (fileExtension: "md", identifier: "net.daringfireball.markdown"),
        (fileExtension: "markdown", identifier: "net.daringfireball.markdown"),
        (fileExtension: "mdlf", identifier: "eu.pinedatec.leonardomd.mdlf"),
        (fileExtension: "mdlr", identifier: "eu.pinedatec.leonardomd.mdlr"),
        (fileExtension: "mdlz", identifier: "eu.pinedatec.leonardomd.mdlz")
    ]
    static var extensions: [String] { documentTypes.map(\.fileExtension) }
    let bundle: Bundle
    let workspace: NSWorkspace

    init(bundle: Bundle = .main, workspace: NSWorkspace = .shared) {
        self.bundle = bundle
        self.workspace = workspace
    }

    var isAvailable: Bool {
        bundle.bundleURL.pathExtension == "app"
            && bundle.bundleIdentifier == Self.bundleIdentifier
            && bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "LeonardoMD"
    }

    func isDefault() throws -> Bool {
        try Self.contentTypes().allSatisfy { type in
            guard let url = workspace.urlForApplication(toOpen: type) else { return false }
            return Bundle(url: url)?.bundleIdentifier == Self.bundleIdentifier
        }
    }

    func makeDefault() async throws {
        for type in try Self.contentTypes() {
            // A failed/cancelled type leaves the actual state to the subsequent refresh.
            try await workspace.setDefaultApplication(at: bundle.bundleURL, toOpen: type)
        }
    }

    static func contentTypes(
        resolve: (String) -> UTType? = { UTType(filenameExtension: $0) }
    ) throws -> [UTType] {
        var types: [UTType] = []
        for documentType in documentTypes {
            guard let type = resolve(documentType.fileExtension),
                  type.identifier == documentType.identifier else {
                // Never change a broad parent type when an exact registration is missing.
                throw AssociationError.documentTypeUnavailable(documentType.fileExtension)
            }
            if !types.contains(type) { types.append(type) }
        }
        return types
    }

    enum AssociationError: Error { case documentTypeUnavailable(String) }
}
