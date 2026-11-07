import SwiftUI
import LeonardoSync
import LeonardoRender

/// A read-only preview never materializes an editable document in the evictable cache.
public struct RemoteDocumentPreview: View {
    @Bindable var library: DownloadLibrary
    let projectID: UUID
    let entry: RemoteFileEntry
    let spanish: Bool
    let appearance: MarkdownAppearance
    @State private var presentation = RemoteDocumentPreviewState()
    @State private var source = false
    @State private var linked: RemoteFileEntry?
    private let virtualRoot = URL(fileURLWithPath: "/LeonardoRemote", isDirectory: true)
    public init(library: DownloadLibrary, projectID: UUID, entry: RemoteFileEntry, spanish: Bool = false, appearance: MarkdownAppearance = .default) {
        self.library = library; self.projectID = projectID; self.entry = entry; self.spanish = spanish; self.appearance = appearance
    }
    private var project: CachedRemoteProject? { library.projects.first { $0.id == projectID } }
    private var currentEntry: RemoteFileEntry? { project?.catalogue.files.first { $0.path == entry.path } }
    private var request: RemoteDocumentPreviewRequest {
        .init(projectID: projectID, path: entry.path, catalogue: project?.catalogue)
    }
    private var file: CorpusFile? { presentation.content(for: request) }
    private var failure: String? { presentation.error(for: request) }
    private var authorizedImages: [String: Data] {
        let paths = Set(project?.catalogue.files.map(\.path) ?? [])
        return presentation.assets(for: request).filter { paths.contains($0.key) }
    }
    private func t(_ en: String, _ es: String) -> String { spanish ? es : en }
    public var body: some View {
        Group {
            if project == nil { Text(t("Access removed", "Acceso retirado")) }
            else if currentEntry == nil { Text(t("Document no longer available", "Documento ya no disponible")) }
            else if let file, let text = String(data: file.content, encoding: .utf8), ["md", "markdown", "txt"].contains((entry.path as NSString).pathExtension.lowercased()) {
                if source || (entry.path as NSString).pathExtension.lowercased() == "txt" {
                    ScrollView { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding() }
                } else {
                    MarkdownPreview(content: text, baseURL: virtualRoot.appendingPathComponent(entry.path).deletingLastPathComponent(),
                        configuration: MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: true,
                            externalLinkPolicy: .callbackOnly, appearance: appearance, localAssetRoot: virtualRoot,
                            memoryAssets: MarkdownMemoryAssets(files: authorizedImages), allowsRemoteImages: false),
                        onLinkActivation: followLink)
                }
            } else if let failure {
                VStack { Text(failure); Button(t("Retry", "Reintentar")) { Task { await load() } } }
            } else if file != nil { Text(t("File downloaded", "Archivo descargado")) }
            else { ProgressView(t("Downloading…", "Descargando…")) }
        }.navigationTitle((entry.path as NSString).lastPathComponent)
        .toolbar { Button(t("Show source", "Ver texto")) { source.toggle() } }
        .task(id: request) { await load() }
        .navigationDestination(item: $linked) { target in
            RemoteDocumentPreview(library: library, projectID: projectID, entry: target, spanish: spanish, appearance: appearance)
        }
    }
    private func load() async {
        let ticket = presentation.begin(request)
        guard let expectedCatalogue = project?.catalogue, currentEntry != nil else { return }
        do {
            let value = try await library.open(id: projectID, path: entry.path)
            guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue, currentEntry != nil else { return }
            presentation.receive(value, ticket: ticket)
            // The canonical Markdown renderer resolves local image requests only from memory.
            // Fetch only referenced, authorized image entries, never the complete corpus.
            if let text = String(data: value.content, encoding: .utf8), let project {
                for path in RemoteDocumentResources.imagePaths(in: text, documentPath: entry.path, catalogue: project.catalogue) {
                    do {
                        let image = try await library.open(id: projectID, path: path)
                        guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue else { return }
                        presentation.receiveImage(image.content, path: path, ticket: ticket)
                    }
                    catch {
                        guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue else { return }
                        presentation.fail(error.localizedDescription, ticket: ticket)
                    }
                }
            }
        } catch {
            guard !Task.isCancelled, self.project?.catalogue == expectedCatalogue else { return }
            presentation.fail(error.localizedDescription, ticket: ticket)
        }
    }
    private func followLink(_ url: URL) {
        guard let path = RemoteDocumentResources.path(url: url, virtualRoot: virtualRoot),
              let entry = project?.catalogue.files.first(where: { $0.path == path }),
              ["md", "markdown", "txt"].contains((path as NSString).pathExtension.lowercased()) else { return }
        linked = entry
    }
}
