import SwiftUI
import LeonardoCore
import LeonardoSync
import LeonardoRender

/// A read-only preview never materializes an editable document in the evictable cache.
public struct RemoteDocumentPreview: View {
    private static let previewableDocumentExtensions: Set<String> = ["md", "markdown", "txt", "mdlf", "mdlr"]
    private static let leonardoFormatExtensions: Set<String> = ["mdlf", "mdlr"]
    @Bindable var library: DownloadLibrary
    let projectID: UUID
    let entry: RemoteFileEntry
    let spanish: Bool
    let appearance: MarkdownAppearance
    let compactFirstHeading: Bool
    let failurePresentation: (@MainActor (Error) -> String)?
    let failureDiagnosticPresentation: RemoteDownloadDiagnosticPresentation?
    @State private var presentation = RemoteDocumentPreviewState()
    @State private var source = false
    @State private var linked: RemoteFileEntry?
    private let virtualRoot = URL(fileURLWithPath: "/LeonardoRemote", isDirectory: true)
    public init(library: DownloadLibrary, projectID: UUID, entry: RemoteFileEntry, spanish: Bool = false,
                appearance: MarkdownAppearance = .default, compactFirstHeading: Bool = false,
                failurePresentation: (@MainActor (Error) -> String)? = nil,
                failureDiagnosticPresentation: RemoteDownloadDiagnosticPresentation? = nil) {
        self.library = library; self.projectID = projectID; self.entry = entry; self.spanish = spanish
        self.appearance = appearance; self.compactFirstHeading = compactFirstHeading
        self.failurePresentation = failurePresentation
        self.failureDiagnosticPresentation = failureDiagnosticPresentation
    }
    private var project: CachedRemoteProject? { library.projects.first { $0.id == projectID } }
    private var currentEntry: RemoteFileEntry? { project?.catalogue.files.first { $0.path == entry.path } }
    private var request: RemoteDocumentPreviewRequest {
        .init(projectID: projectID, path: entry.path, catalogue: project?.catalogue)
    }
    private var fileExtension: String { (entry.path as NSString).pathExtension.lowercased() }
    private var file: CorpusFile? { presentation.content(for: request) }
    private var failure: String? { presentation.error(for: request) }
    private var previewConfiguration: MarkdownPreviewConfiguration {
        var value = MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: true,
            externalLinkPolicy: .callbackOnly, appearance: appearance, localAssetRoot: virtualRoot,
            memoryAssets: MarkdownMemoryAssets(files: authorizedImages), allowsRemoteImages: false)
        value.allowsLeonardoFormat = Self.leonardoFormatExtensions.contains(fileExtension)
        value.compactFirstHeading = compactFirstHeading
        return value
    }
    private var authorizedImages: [String: Data] {
        let paths = Set(project?.catalogue.files.map(\.path) ?? [])
        return presentation.assets(for: request).filter { paths.contains($0.key) }
    }
    private func t(_ en: String, _ es: String) -> String { spanish ? es : en }
    public var body: some View {
        VStack(spacing: 0) {
            if project != nil, currentEntry != nil, let failure {
                VStack(alignment: .leading, spacing: 8) {
                    if presentation.showsRetainedCopy(for: request) {
                        Text(t("Showing a previously downloaded copy. The latest version could not be downloaded.",
                               "Se muestra una copia descargada anteriormente. No se pudo descargar la versión actual."))
                    }
                    Text(failure).accessibilityIdentifier("remote-download-inline-error")
                    Button(t("Retry", "Reintentar")) { Task { await load() } }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("remote-download-warning")
            }
            content
        }.navigationTitle((entry.path as NSString).lastPathComponent)
        .toolbar { Button(source ? t("Show document", "Ver documento") : t("Show source", "Ver texto")) { source.toggle() } }
        .task(id: request) { await load() }
        .navigationDestination(item: $linked) { target in
            RemoteDocumentPreview(library: library, projectID: projectID, entry: target, spanish: spanish,
                                  appearance: appearance, compactFirstHeading: compactFirstHeading,
                                  failurePresentation: failurePresentation,
                                  failureDiagnosticPresentation: failureDiagnosticPresentation)
        }
    }
    @ViewBuilder private var content: some View {
        Group {
            if project == nil { Text(t("Access removed", "Acceso retirado")) }
            else if currentEntry == nil { Text(t("Document no longer available", "Documento ya no disponible")) }
            else if let file, let text = String(data: file.content, encoding: .utf8), Self.previewableDocumentExtensions.contains(fileExtension) {
                if source || fileExtension == "txt" {
                    ScrollView { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding() }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if let declaration = guidedSigningDeclaration(in: text) {
                            LeonardoGuidedSigningReadOnlyBanner(declaration: declaration, spanish: spanish)
                        }
                        MarkdownPreview(content: text, baseURL: virtualRoot.appendingPathComponent(entry.path).deletingLastPathComponent(),
                            configuration: previewConfiguration,
                            onLinkActivation: followLink)
                    }
                }
            } else if file != nil { Text(t("File downloaded", "Archivo descargado")) }
            else if failure == nil { ProgressView(t("Downloading…", "Descargando…")) }
        }
    }
    private func load() async {
        let ticket = presentation.begin(request)
        guard let expectedCatalogue = project?.catalogue, currentEntry != nil else { return }
        do {
            let value = try await library.openResult(id: projectID, path: entry.path,
                                                     presentation: failurePresentation,
                                                     diagnosticPresentation: failureDiagnosticPresentation)
            guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue, currentEntry != nil else { return }
            presentation.receive(value, ticket: ticket)
            // The canonical Markdown renderer resolves local image requests only from memory.
            // Fetch only referenced, authorized image entries, never the complete corpus.
            if let text = String(data: value.file.content, encoding: .utf8), let project {
                for path in RemoteDocumentResources.imagePaths(in: text, documentPath: entry.path, catalogue: project.catalogue) {
                    do {
                        let image = try await library.openResult(id: projectID, path: path,
                                                                presentation: failurePresentation,
                                                                diagnosticPresentation: failureDiagnosticPresentation)
                        guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue else { return }
                        presentation.receiveImage(image.file.content, path: path, ticket: ticket)
                        if let failure = image.updateFailure {
                            let message = image.updateFailureCause?.displayMessage(using: failurePresentation)
                                ?? (failurePresentation == nil ? path + ": " + failure : failure)
                            presentation.fail(message, ticket: ticket)
                        }
                    }
                    catch {
                        guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue else { return }
                        presentation.fail(presentFailure(error, path: path), ticket: ticket)
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue else { return }
            presentation.fail(presentFailure(error, path: entry.path), ticket: ticket)
        }
    }

    private func presentFailure(_ error: Error, path: String) -> String {
        if let failure = error as? RemoteDownloadFailure {
            return failure.displayMessage(using: failurePresentation)
        }
        if let failurePresentation { return failurePresentation(error) }
        if let recorded = library.failures[DownloadLibrary.key(id: projectID, path: path)] { return recorded }
        return error.localizedDescription
    }

    private func guidedSigningDeclaration(in text: String) -> LeonardoSigningDeclaration? {
        guard let document = try? LeonardoFormatParser.parse(text),
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else { return nil }
        return document.metadata.document.signing
    }

    private func followLink(_ url: URL) {
        guard let path = RemoteDocumentResources.path(url: url, virtualRoot: virtualRoot),
              let entry = project?.catalogue.files.first(where: { $0.path == path }),
              Self.previewableDocumentExtensions.contains((path as NSString).pathExtension.lowercased()) else { return }
        linked = entry
    }
}

/// Shared by remote and offline Little Leonardo readers. It is deliberately a
/// presentation-only notice: the mobile reader never receives the desktop
/// signing coordinator or any form-editing capability.
public struct LeonardoGuidedSigningReadOnlyBanner: View {
    private let declaration: LeonardoSigningDeclaration
    private let spanish: Bool

    public init(declaration: LeonardoSigningDeclaration, spanish: Bool) {
        self.declaration = declaration
        self.spanish = spanish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(spanish ? "Firma guiada · vista de solo lectura" : "Guided signing · read-only preview",
                  systemImage: "signature")
                .font(.headline)
            Text(spanish
                 ? "Los puestos de firma se revisan y autorizan en el documento de escritorio. Esta vista móvil nunca concede edición ni acceso para firmar."
                 : "Signing positions are reviewed and authorized on the desktop document. This mobile view never grants form editing or signing access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(declaration.positions.map(\.label).joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .accessibilityIdentifier("guided-signing-read-only-banner")
    }
}
