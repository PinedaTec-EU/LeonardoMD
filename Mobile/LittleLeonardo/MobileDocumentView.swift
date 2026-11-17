import SwiftUI
import LeonardoCore
import LeonardoRender
import LeonardoSync

@MainActor
struct MobileDocumentView: View {
    let library: MobileLibrary
    let projectID: UUID
    let file: CorpusFile
    var initialAnchor: String? = nil

    @ObservedObject private var preferences: MobileMarkdownPreferences
    @StateObject private var recommendations: MobileExtensionRecommendations
    @StateObject private var previewController: MarkdownPreviewController
    @State private var text = ""
    @State private var source = false
    @State private var assets: MarkdownMemoryAssets?
    @State private var linkedDocument: CachedDocumentLink?
    @State private var unavailableLink = false
    @State private var didScrollToInitialAnchor = false

    private let virtualRoot = URL(fileURLWithPath: "/LittleLeonardoCorpus", isDirectory: true)
    private var documentIdentity: MobileDocumentIdentity { MobileDocumentIdentity(projectID: projectID, path: file.path) }

    init(library: MobileLibrary, projectID: UUID, file: CorpusFile, initialAnchor: String? = nil) {
        self.library = library
        self.projectID = projectID
        self.file = file
        self.initialAnchor = initialAnchor

        let preferences = MobileMarkdownPreferences.shared
        let recommendations = MobileExtensionRecommendations()
        _preferences = ObservedObject(wrappedValue: preferences)
        _recommendations = StateObject(wrappedValue: recommendations)

        let controller = MarkdownPreviewController()
        let identity = MobileDocumentIdentity(projectID: projectID, path: file.path)
        controller.onDetectedExtensions = { detectedSource, identifiers in
            guard let current = library.currentFile(projectID: projectID, path: file.path),
                  let currentSource = String(data: current.content, encoding: .utf8),
                  currentSource == detectedSource else { return }
            recommendations.activate(document: identity, preferences: preferences)
            recommendations.inspect(document: identity, source: detectedSource,
                                    detectedIDs: identifiers, preferences: preferences)
        }
        _previewController = StateObject(wrappedValue: controller)
    }

    private var previewConfiguration: MarkdownPreviewConfiguration {
        let features = preferences.features
        var configuration = MarkdownPreviewConfiguration(
            allowsMermaid: features.mermaidEnabled,
            allowsMath: features.mathEnabled,
            allowsVegaLite: features.vegaLiteEnabled,
            allowsCitations: features.citationsEnabled,
            allowsMarkdownExtensions: features.markdownExtensionsEnabled,
            externalLinkPolicy: .blocked,
            appearance: .leonardoClassic,
            localAssetRoot: virtualRoot,
            memoryAssets: assets,
            allowsRemoteImages: false)
        configuration.compactFirstHeading = true
        return configuration
    }

    private var liveProject: OfflineProject? { library.projects.first { $0.id == projectID } }
    private var liveFile: CorpusFile? { library.currentFile(projectID: projectID, path: file.path) }

    var body: some View {
        Group {
            if liveProject == nil {
                ContentUnavailableView("Acceso retirado", systemImage: "lock", description: Text("La copia local de este proyecto se ha eliminado."))
            } else if liveFile == nil {
                ContentUnavailableView("Documento no disponible", systemImage: "doc", description: Text("El documento ya no está en la copia local."))
            } else if !source, ["md", "markdown"].contains((file.path as NSString).pathExtension.lowercased()) {
                MarkdownPreview(content: text,
                    baseURL: virtualRoot.appendingPathComponent(file.path).deletingLastPathComponent(),
                    configuration: previewConfiguration, controller: previewController, onLinkActivation: followLink)
            } else {
                ScrollView {
                    Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        }
        .classicSurface()
        .navigationTitle((file.path as NSString).lastPathComponent)
        .toolbar {
            Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath") {
                Task { await library.synchronize() }
            }.disabled(library.connecting || liveProject?.isRecoveryArchive == true)
                .accessibilityIdentifier("document-sync")
            Button(source ? "Ver documento" : "Ver texto", systemImage: "chevron.left.forwardslash.chevron.right") { source.toggle() }
        }
        .onAppear {
            recommendations.activate(document: documentIdentity, preferences: preferences)
            updateContent()
        }
        .onDisappear { recommendations.deactivate(document: documentIdentity) }
        .onChange(of: library.projects) { _, _ in updateContent() }
        .alert("Documento no disponible", isPresented: $unavailableLink) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text("El enlace no corresponde a un documento descargado dentro de la carpeta autorizada.") }
        .navigationDestination(isPresented: Binding(get: { linkedDocument != nil }, set: { if !$0 { linkedDocument = nil } })) {
            if let target = linkedDocument {
                MobileDocumentView(library: library, projectID: projectID, file: target.file, initialAnchor: target.anchor)
            }
        }
        .sheet(item: Binding(
            get: { recommendations.prompt },
            set: { if $0 == nil { recommendations.dismissPrompt() } }
        )) { request in
            MobileExtensionRecommendationDialog(request: request, spanish: MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)) { choice, enableSelected in
                recommendations.respond(to: request, choice: choice, enableSelected: enableSelected,
                                        preferences: preferences)
            }
        }
        .onChange(of: preferences.extensionWarningResetRevision) { _, _ in
            recommendations.warningPreferencesDidReset(preferences: preferences)
        }
        .onChange(of: previewController.isReady) { _, ready in
            if ready, !didScrollToInitialAnchor, let initialAnchor {
                previewController.scroll(to: initialAnchor)
                didScrollToInitialAnchor = true
            }
        }
    }

    private func updateContent() {
        let updatedText = liveFile.flatMap { String(data: $0.content, encoding: .utf8) } ?? ""
        if updatedText != text { recommendations.documentContentWillReload(documentIdentity) }
        text = updatedText
        assets = liveProject.map { MarkdownMemoryAssets(files: Dictionary(uniqueKeysWithValues: $0.files.map { ($0.path, $0.content) })) }
    }

    private func followLink(_ url: URL) {
        guard let project = liveProject,
              let target = CachedDocumentLink(url: url, virtualRoot: virtualRoot, scope: project.scope, files: project.files) else {
            unavailableLink = true; return
        }
        if target.file.path == file.path {
            if let anchor = target.anchor { previewController.scroll(to: anchor) }
        } else { linkedDocument = target }
    }
}
