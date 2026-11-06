import SwiftUI
import LeonardoSync
import LeonardoRender

/// A read-only preview never materializes an editable document in the evictable cache.
public struct RemoteDocumentPreview: View {
    @Bindable var library: DownloadLibrary
    let projectID: UUID
    let entry: RemoteFileEntry
    let spanish: Bool
    @State private var file: CorpusFile?
    @State private var failure: String?
    @State private var source = false
    @State private var linked: RemoteFileEntry?
    @State private var images: [String: Data] = [:]
    private let virtualRoot = URL(fileURLWithPath: "/LeonardoRemote", isDirectory: true)
    public init(library: DownloadLibrary, projectID: UUID, entry: RemoteFileEntry, spanish: Bool = false) {
        self.library = library; self.projectID = projectID; self.entry = entry; self.spanish = spanish
    }
    private var project: CachedRemoteProject? { library.projects.first { $0.id == projectID } }
    private func t(_ en: String, _ es: String) -> String { spanish ? es : en }
    public var body: some View {
        Group {
            if project == nil { Text(t("Access removed", "Acceso retirado")) }
            else if let file, let text = String(data: file.content, encoding: .utf8), ["md", "markdown", "txt"].contains((entry.path as NSString).pathExtension.lowercased()) {
                if source {
                    ScrollView { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding() }
                } else {
                    MarkdownPreview(content: text, baseURL: virtualRoot.appendingPathComponent(entry.path).deletingLastPathComponent(),
                        configuration: MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: true,
                            externalLinkPolicy: .callbackOnly, localAssetRoot: virtualRoot,
                            memoryAssets: MarkdownMemoryAssets(files: images), allowsRemoteImages: false),
                        onLinkActivation: followLink)
                }
            } else if let failure {
                VStack { Text(failure); Button(t("Retry", "Reintentar")) { Task { await load() } } }
            } else if file != nil { Text(t("File downloaded", "Archivo descargado")) }
            else { ProgressView(t("Downloading…", "Descargando…")) }
        }.navigationTitle((entry.path as NSString).lastPathComponent)
        .toolbar { Button(t("Show source", "Ver texto")) { source.toggle() } }
        .task(id: project?.catalogue.files.first(where: { $0.path == entry.path })?.revision) { await load() }
        .navigationDestination(item: $linked) { target in
            RemoteDocumentPreview(library: library, projectID: projectID, entry: target, spanish: spanish)
        }
    }
    private func load() async {
        failure = nil
        do {
            let value = try await library.open(id: projectID, path: entry.path)
            guard project != nil else { return }
            file = value
            // The canonical Markdown renderer resolves local image requests only from memory.
            // Fetch only referenced, authorized image entries, never the complete corpus.
            if let text = String(data: value.content, encoding: .utf8), let project {
                for path in RemoteDocumentResources.imagePaths(in: text, documentPath: entry.path, catalogue: project.catalogue) {
                    do { images[path] = try await library.open(id: projectID, path: path).content }
                    catch { failure = error.localizedDescription }
                }
            }
        } catch { failure = error.localizedDescription }
    }
    private func followLink(_ url: URL) {
        guard let path = RemoteDocumentResources.path(url: url, virtualRoot: virtualRoot),
              let entry = project?.catalogue.files.first(where: { $0.path == path }),
              ["md", "markdown", "txt"].contains((path as NSString).pathExtension.lowercased()) else { return }
        linked = entry
    }
}
