import SwiftUI
import LeonardoCore
import LeonardoRender
import LeonardoSync
import LeonardoSyncUI

@MainActor
struct MobileDocumentView: View {
    private static let markdownPreviewExtensions: Set<String> = ["md", "markdown", "mdlf", "mdlr"]
    private static let leonardoFormatExtensions: Set<String> = ["mdlf", "mdlr"]
    private static let previewableDocumentExtensions: Set<String> = ["md", "markdown", "txt", "mdlf", "mdlr"]
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
    @State private var signingCopy: MobileSigningExchangeDocument?
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
        configuration.allowsLeonardoFormat = Self.leonardoFormatExtensions.contains(fileExtension)
        return configuration
    }

    private var liveProject: OfflineProject? { library.projects.first { $0.id == projectID } }
    private var liveFile: CorpusFile? { library.currentFile(projectID: projectID, path: file.path) }
    private var fileExtension: String { (file.path as NSString).pathExtension.lowercased() }
    private var spanishErrors: Bool {
        MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
    }
    private var guidedSigningDeclaration: LeonardoSigningDeclaration? {
        guard !source,
              Self.leonardoFormatExtensions.contains(fileExtension),
              let document = try? LeonardoFormatParser.parse(text),
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else { return nil }
        return document.metadata.document.signing
    }

    var body: some View {
        Group {
            if liveProject == nil {
                ContentUnavailableView("Acceso retirado", systemImage: "lock", description: Text("La copia local de este proyecto se ha eliminado."))
            } else if liveFile == nil {
                ContentUnavailableView("Documento no disponible", systemImage: "doc", description: Text("El documento ya no está en la copia local."))
            } else if !Self.previewableDocumentExtensions.contains(fileExtension) {
                ContentUnavailableView("Archivo conservado", systemImage: "doc",
                    description: Text("Este archivo se conserva en la copia de recuperación. Expórtala para abrirlo en un ordenador."))
            } else if !source, Self.markdownPreviewExtensions.contains(fileExtension) {
                VStack(alignment: .leading, spacing: 0) {
                    if let guidedSigningDeclaration {
                        LeonardoGuidedSigningReadOnlyBanner(
                            declaration: guidedSigningDeclaration,
                            spanish: spanishErrors)
                    }
                    MarkdownPreview(content: text,
                        baseURL: virtualRoot.appendingPathComponent(file.path).deletingLastPathComponent(),
                        configuration: previewConfiguration, controller: previewController, onLinkActivation: followLink)
                }
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
            if guidedSigningDeclaration != nil {
                Button(spanishErrors ? "Firmar copia" : "Sign copy", systemImage: "signature") {
                    Task { await prepareSigningCopy() }
                }
                .accessibilityIdentifier("prepare-mobile-signing-copy")
            }
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
        .navigationDestination(item: $signingCopy) { copy in
            MobileGuidedSigningView(library: library, exchange: copy.exchange, localDocumentLocation: signingLocation)
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

    private var signingLocation: String { "mobile://\(projectID.uuidString)/\(file.path)" }

    private func prepareSigningCopy() async {
        guard let liveProject,
              let document = try? LeonardoFormatParser.parse(text),
              document.metadata.formatVersion >= LeonardoFormat.signingVersion,
              document.metadata.document.signing != nil else {
            unavailableLink = true
            return
        }
        do {
            let resources = try Self.signingResources(
                source: text, documentPath: file.path, scope: liveProject.scope, files: liveProject.files
            )
            let stored = try await library.signingStore.sessions().last {
                $0.documentLocation == signingLocation && $0.documentID == document.metadata.document.id
                    && $0.initialRevision == document.metadata.document.revision
            }
            let session = try stored ?? LeonardoGuidedSigningSession(
                document: document, at: Date(), documentLocation: signingLocation
            )
            let credentialIDs = Set(session.positions.values.compactMap { $0.assignment?.credentialID })
            let trust = try await library.signingCredentialStore.trustStore()
            let exchange = try LeonardoSigningExchange(
                document: document,
                resources: resources,
                session: session,
                trustedCredentials: trust.allCredentials.filter { credentialIDs.contains($0.id) },
                at: Date()
            )
            signingCopy = MobileSigningExchangeDocument(exchange: exchange)
        } catch LeonardoSigningError.remoteImagesNotSealable {
            library.presentError(LeonardoSigningError.remoteImagesNotSealable, operation: .export,
                                 message: spanishErrors
                                 ? "Sustituye las imágenes en línea por archivos locales en el documento original."
                                 : "Replace online images with local files in the original document.")
        } catch {
            library.presentError(error, operation: .export,
                                 message: spanishErrors
                                 ? "No se pudo preparar la copia de firma."
                                 : "The signing copy could not be prepared.")
        }
    }

    static func signingResources(
        source: String, documentPath: String, scope: CorpusScope, files: [CorpusFile]
    ) throws -> [LeonardoSigningResource] {
        let base = URL(fileURLWithPath: "/" + documentPath).deletingLastPathComponent()
        let document = try LeonardoFormatParser.parse(source)
        return try LeonardoLocalImagePolicy.signingReferences(in: document).map { reference in
            guard let parsed = URLComponents(string: reference),
                  parsed.scheme == nil, parsed.host == nil,
                  !parsed.path.hasPrefix("/"), !parsed.path.contains("\\"),
                  !parsed.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  let resolved = parsed.url(relativeTo: base)?.standardizedFileURL,
                  resolved.path.hasPrefix("/") else {
                throw LeonardoSigningError.invalidResourceReference(reference)
            }
            let path = String(resolved.path.dropFirst())
            guard (try? scope.validate(path)) != nil,
                  let asset = files.first(where: { $0.path == path }) else {
                throw LeonardoSigningError.invalidResourceReference(reference)
            }
            return LeonardoSigningResource(reference: reference, bytes: asset.content)
        }
    }
}
