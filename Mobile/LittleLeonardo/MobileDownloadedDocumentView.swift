import SwiftUI
import LeonardoSync
import LeonardoRender

struct MobileDownloadedDocumentView: View {
    let library: MobileLibrary
    let projectID: UUID
    let entry: RemoteFileEntry
    @State private var file: CorpusFile?
    @State private var failure: String?
    private var authorized: Bool { library.downloads.projects.contains { $0.id == projectID } }
    var body: some View {
        Group {
            if !authorized { ContentUnavailableView("Proyecto no disponible", systemImage: "lock") }
            else if let file, let text = String(data: file.content, encoding: .utf8), ["md", "markdown", "txt"].contains((entry.path as NSString).pathExtension.lowercased()) {
                MarkdownPreview(content: text, configuration: MarkdownPreviewConfiguration(
                    allowsMermaid: true, allowsMath: true, externalLinkPolicy: .blocked, allowsRemoteImages: false))
            } else if let failure {
                ContentUnavailableView {
                    Label("No se pudo descargar", systemImage: "wifi.exclamationmark")
                } description: { Text(failure) } actions: { Button("Reintentar") { Task { await load() } } }
            } else if file != nil {
                Text("Archivo descargado").foregroundStyle(.secondary)
            } else { ProgressView("Descargando…") }
        }.navigationTitle((entry.path as NSString).lastPathComponent)
        .task(id: entry.revision) { await load() }
    }
    private func load() async {
        failure = nil
        do { file = try await library.downloads.open(id: projectID, path: entry.path) }
        catch { failure = error.localizedDescription }
    }
}
