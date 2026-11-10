import SwiftUI
import LeonardoSync
import LeonardoRender
import LeonardoSyncUI

private enum MobileLibrarySheet: String, Identifiable {
    case direct, settings, about
    var id: String { rawValue }
}

struct MobileLibraryView: View {
    @Bindable var library: MobileLibrary
    @State private var presentedSheet: MobileLibrarySheet?
    @State private var qrURL = ""
    @State private var scanning = false
    @State private var manualPairing = false
    @State private var host = ""
    @State private var port = "40882"
    @State private var presentedRubricRequest: RubricRequest?
    @AppStorage("directSyncIntervalMinutes") private var syncInterval = 1
    @Environment(\.scenePhase) private var scenePhase
    private var activeRubricDraft: MobileRubricDraft? {
        library.recoverableRubricDrafts.first { $0.state != .submitted }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Proyectos / Projects") {
                    ForEach(library.libraryProjects) { project in
                        NavigationLink {
                            switch project {
                            case .demo: MobileDemoProjectView()
                            case .downloaded(let cached):
                                MobileProjectView(library: library, projectID: cached.id)
                            }
                        } label: {
                            Text(project.name).font(.headline).foregroundStyle(MobileClassic.heading)
                        }
                        .accessibilityIdentifier(project.id == "bundled-demo" ? "open-demo-project" : "open-project-\(project.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Eliminar / Delete", role: .destructive) {
                                Task { await library.deleteLibraryProject(project) }
                            }
                            .disabled(library.connecting)
                            .accessibilityIdentifier(project.id == "bundled-demo" ? "delete-demo-project" : "delete-project-\(project.id)")
                        }
                    }
                    if library.libraryProjects.isEmpty {
                        VStack(spacing: 16) {
                            MobileBrand(size: 64)
                            Text("Tus documentos, contigo").font(.title2.bold()).foregroundStyle(MobileClassic.heading)
                            Text("Conecta tu Mac y consulta tus proyectos sin conexión.")
                                .multilineTextAlignment(.center).foregroundStyle(MobileClassic.secondary)
                            Button("Conectar con mi Mac") { presentedSheet = .direct }
                                .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper).disabled(library.connecting)
                            Label("Solo lectura", systemImage: "lock").font(.footnote)
                        }.padding(.vertical, 20).frame(maxWidth: .infinity)
                    }
                }.listRowBackground(MobileClassic.paper)
            }
            .classicSurface()
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await library.synchronize(); await library.reload() }
            .toolbar {
                Button("Conectar", systemImage: "qrcode") { presentedSheet = .direct }
                    .disabled(library.connecting)
                    .accessibilityIdentifier("open-pairing")
                Button("Ajustes de sincronización", systemImage: "gearshape") { presentedSheet = .settings }
                    .accessibilityIdentifier("open-sync-settings")
                Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await library.synchronize() }
                }.disabled(library.connecting)
                if let request = library.pendingRubricRequests.first {
                    Button("Solicitud de rúbrica", systemImage: "signature") {
                        presentedRubricRequest = request
                    }.accessibilityIdentifier("open-rubric-request")
                } else if let draft = activeRubricDraft {
                    Button("Borrador de rúbrica", systemImage: "signature") {
                        presentedRubricRequest = draft.request
                    }.accessibilityIdentifier("open-rubric-draft")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let request = library.pendingRubricRequests.first {
                    Button {
                        presentedRubricRequest = request
                    } label: {
                        Label("Solicitud de rúbrica de \(request.requesterName)", systemImage: "signature")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper)
                    .padding(.horizontal)
                    .accessibilityIdentifier("rubric-request-banner")
                } else if let draft = activeRubricDraft {
                    Button {
                        presentedRubricRequest = draft.request
                    } label: {
                        Label("Recuperar rúbrica de \(draft.request.requesterName)", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper)
                    .padding(.horizontal)
                    .accessibilityIdentifier("rubric-draft-banner")
                } else if let code = library.comparisonCode {
                    VStack {
                        Text("Código de conexión: \(code)").font(.headline.monospacedDigit())
                        Text("Comprueba que coincide en LeonardoMD, autoriza los proyectos y pulsa Sincronizar.")
                            .font(.caption)
                    }.padding().background(MobileClassic.inset)
                }
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .direct: directConnectionSheet
                case .settings: synchronizationSettings
                case .about: MobileAboutView()
                }
            }
            .fullScreenCover(item: $presentedRubricRequest) { request in
                MobileRubricCaptureView(request: request, library: library)
            }
            .onChange(of: library.pendingRubricRequests) { _, requests in
                guard presentedRubricRequest == nil, let request = requests.first else { return }
                presentedRubricRequest = request
            }
            .onChange(of: library.recoverableRubricDrafts) { _, drafts in
                guard presentedRubricRequest == nil,
                      let draft = drafts.first(where: { $0.state != .submitted }) else { return }
                presentedRubricRequest = draft.request
            }
        }
        .task(id: "\(syncInterval)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            await library.synchronize()
            guard [1, 5, 15, 30, 60].contains(syncInterval) else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(syncInterval * 60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await library.synchronize()
            }
        }
        .task(id: "rubric-\(scenePhase)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await library.pollRubricRequests()
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
        .alert("No se pudo completar la operación", isPresented: Binding(
            get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("Aceptar") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
    private var directConnectionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Conecta con tu Mac").font(.title2.bold()).foregroundStyle(MobileClassic.heading)
                        Label("Abre LeonardoMD y activa el uso compartido", systemImage: "1.circle")
                        Label("Escanea el QR o introduce la dirección", systemImage: "2.circle")
                        Label("Comprueba el código y autoriza en el Mac", systemImage: "3.circle")
                        Text("Ambos dispositivos deben estar en la misma red local.")
                            .font(.footnote).foregroundStyle(MobileClassic.secondary)
                    }.padding(.vertical, 8)
                Picker("Método de conexión", selection: $manualPairing) {
                    Text("QR").tag(false)
                    Text("IP y puerto").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("pairing-method")
                if manualPairing {
                    TextField("IP de LeonardoMD", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("pairing-host")
                    TextField("Puerto", text: $port).keyboardType(.numberPad)
                        .accessibilityIdentifier("pairing-port")
                } else {
                    TextField("littleleonardo://pair…", text: $qrURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Escanear QR", systemImage: "camera") { scanning = true }
                        .disabled(library.connecting)
                        .accessibilityIdentifier("scan-pairing-qr")
                }
                }.listRowBackground(MobileClassic.inset)
                Section { syncFrequency }.listRowBackground(MobileClassic.inset)
                Section {
                Button("Solicitar conexión") {
                    Task {
                        if manualPairing {
                            await library.connectManual(host: host, port: port, deviceName: UIDevice.current.name)
                        } else {
                            await library.connect(qrURL: qrURL, deviceName: UIDevice.current.name)
                        }
                        if library.comparisonCode != nil { qrURL = ""; presentedSheet = nil }
                    }
                }.disabled(library.connecting || (manualPairing ? host.isEmpty || (UInt16(port) ?? 0) == 0 : qrURL.isEmpty))
                }.listRowBackground(MobileClassic.paper)
            }.classicSurface().navigationTitle("Conectar con LeonardoMD")
            .toolbar { Button("Cerrar") { presentedSheet = nil } }
            .sheet(isPresented: $scanning) {
                MobileQRScannerScreen { qrURL = $0 }
            }
        }
    }

    private var syncFrequency: some View {
        Group {
            Picker("Sincronización automática", selection: $syncInterval) {
                Text("Solo manual").tag(0)
                ForEach([1, 5, 15, 30, 60], id: \.self) { Text("Cada \($0) min").tag($0) }
            }
            Text("La sincronización automática funciona mientras la app está activa.").font(.caption)
        }
    }

    private var synchronizationSettings: some View {
        NavigationStack {
            Form {
                Section("Frecuencia") { syncFrequency }.listRowBackground(MobileClassic.inset)
                Section("Proyectos / Projects") {
                    Button("Recuperar demo / Restore demo", systemImage: "arrow.counterclockwise") {
                        do { try library.projectLifecycle.restoreDemo() }
                        catch { library.error = error.localizedDescription }
                    }
                    .disabled(library.projectLifecycle.demoIsVisible)
                    .accessibilityIdentifier("restore-demo-project")
                    Text("Recupera el proyecto con tus respuestas de práctica guardadas en este dispositivo. / Restore the project with your practice answers saved on this device.")
                        .font(.caption)
                }.listRowBackground(MobileClassic.inset)
                SyncCacheSettingsView(library: library.downloads, spanish: true).listRowBackground(MobileClassic.inset)
                Section {
                    Button("Acerca de Little Leonardo", systemImage: "info.circle") { presentedSheet = .about }
                        .accessibilityIdentifier("open-about")
                }.listRowBackground(MobileClassic.inset)
            }
                .classicSurface()
                .navigationTitle("Sincronización")
                .toolbar { Button("Cerrar") { presentedSheet = nil } }
        }
    }
}

struct MobileProjectView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var exporting = false
    @State private var selectedEntry: RemoteFileEntry?
    private var project: OfflineProject? { library.projects.first { $0.id == projectID } }
    var body: some View {
        Group {
            if let project, !project.isRecoveryArchive {
                SyncCatalogueView(library: library.downloads, projectID: project.id, spanish: true, rowBackground: MobileClassic.paper) { entry in selectedEntry = entry }
            } else {
            List {
            if let project {
                Section {
                    Text("Archivo de recuperación · Solo lectura").font(.caption).foregroundStyle(MobileClassic.secondary)
                    Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)").font(.caption)
                    if project.isRecoveryArchive {
                        Text("Esta copia antigua conserva tus cambios locales y enviados. Expórtala para recuperarlos en un ordenador. No se editará ni se enviará automáticamente.")
                        Button("Exportar recuperación", systemImage: "square.and.arrow.up") { exporting = true }
                            .accessibilityIdentifier("export-recovery")
                    }
                }
                .listRowBackground(MobileClassic.inset)
                ForEach(project.files.filter { ["md", "markdown", "txt"].contains(($0.path as NSString).pathExtension.lowercased()) }, id: \.path) { file in
                    NavigationLink(file.path) {
                        MobileDocumentView(library: library, projectID: project.id, file: file)
                    }.listRowBackground(MobileClassic.paper)
                }
            }
            }
            }
        }.classicSurface().navigationTitle(project?.name ?? "Proyecto")
        .navigationDestination(item: $selectedEntry) { entry in
            RemoteDocumentPreview(library: library.downloads, projectID: projectID, entry: entry, spanish: true, appearance: .leonardoClassic, compactFirstHeading: true).classicSurface()
        }
        .fileExporter(isPresented: $exporting, document: project.map(MobileRecoveryDocument.init),
                      contentType: .json, defaultFilename: "LittleLeonardo-\(projectID.uuidString)-recovery") { result in
            if case .failure(let error) = result { library.error = error.localizedDescription }
        }
    }
}

struct MobileDocumentView: View {
    let library: MobileLibrary
    let projectID: UUID
    let file: CorpusFile
    var initialAnchor: String? = nil
    @State private var text = ""
    @State private var source = false
    @State private var assets: MarkdownMemoryAssets?
    @State private var linkedDocument: CachedDocumentLink?
    @State private var unavailableLink = false
    @State private var didScrollToInitialAnchor = false
    @StateObject private var previewController = MarkdownPreviewController()
    private let virtualRoot = URL(fileURLWithPath: "/LittleLeonardoCorpus", isDirectory: true)
    private var previewConfiguration: MarkdownPreviewConfiguration {
        var configuration = MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: true, externalLinkPolicy: .blocked,
            appearance: .leonardoClassic,
            localAssetRoot: virtualRoot, memoryAssets: assets, allowsRemoteImages: false)
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
        .onAppear { updateContent() }
        .onChange(of: library.projects) { _, _ in updateContent() }
        .alert("Documento no disponible", isPresented: $unavailableLink) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text("El enlace no corresponde a un documento descargado dentro de la carpeta autorizada.") }
        .navigationDestination(isPresented: Binding(get: { linkedDocument != nil }, set: { if !$0 { linkedDocument = nil } })) {
            if let target = linkedDocument {
                MobileDocumentView(library: library, projectID: projectID, file: target.file, initialAnchor: target.anchor)
            }
        }
        .onChange(of: previewController.isReady) { _, ready in
            if ready, !didScrollToInitialAnchor, let initialAnchor {
                previewController.scroll(to: initialAnchor)
                didScrollToInitialAnchor = true
            }
        }
    }

    private func updateContent() {
        text = liveFile.flatMap { String(data: $0.content, encoding: .utf8) } ?? ""
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
