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
    static let extensions = ["md", "markdown"]
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
        try contentTypes().allSatisfy { type in
            guard let url = workspace.urlForApplication(toOpen: type) else { return false }
            return Bundle(url: url)?.bundleIdentifier == Self.bundleIdentifier
        }
    }

    func makeDefault() async throws {
        for type in try contentTypes() {
            // A failed/cancelled type leaves the actual state to the subsequent refresh.
            try await workspace.setDefaultApplication(at: bundle.bundleURL, toOpen: type)
        }
    }

    private func contentTypes() throws -> [UTType] {
        var types: [UTType] = []
        for ext in Self.extensions {
            guard let type = UTType(filenameExtension: ext),
                  type.identifier == "net.daringfireball.markdown" else {
                // Never substitute public.plain-text when registration is unavailable.
                throw AssociationError.markdownTypeUnavailable
            }
            if !types.contains(type) { types.append(type) }
        }
        return types
    }

    enum AssociationError: Error { case markdownTypeUnavailable }
}
