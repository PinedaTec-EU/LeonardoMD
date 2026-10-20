import SwiftUI
import LeonardoSync
import LeonardoRender

private enum MobileLibrarySheet: String, Identifiable {
    case direct, settings
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
    @AppStorage("directSyncIntervalMinutes") private var syncInterval = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List(library.projects, id: \.id) { project in
                NavigationLink {
                    MobileProjectView(library: library, projectID: project.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(project.name)
                        Text(project.isRecoveryArchive ? "Archivo de recuperación · Solo lectura" : "Consulta desde LeonardoMD · Solo lectura")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if library.projects.isEmpty {
                    ContentUnavailableView("Little Leonardo", systemImage: "book.closed",
                        description: Text("Conecta con LeonardoMD para descargar tus proyectos y consultarlos offline."))
                }
            }
            .navigationTitle("Little Leonardo")
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
            }
            .safeAreaInset(edge: .bottom) {
                if let code = library.comparisonCode {
                    VStack {
                        Text("Código de conexión: \(code)").font(.headline.monospacedDigit())
                        Text("Comprueba que coincide en LeonardoMD, autoriza los proyectos y pulsa Sincronizar.")
                            .font(.caption)
                    }.padding().background(.regularMaterial)
                }
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .direct: directConnectionSheet
                case .settings: synchronizationSettings
                }
            }
        }
        .task(id: "\(syncInterval)-\(scenePhase)") {
            guard scenePhase == .active, [1, 5, 15, 30, 60].contains(syncInterval) else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(syncInterval * 60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await library.synchronize()
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
                Text("Ambos dispositivos deben estar en la misma red local. Comprueba el código en las dos pantallas antes de autorizar la conexión.")
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
                syncFrequency
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
            }.navigationTitle("Conectar con LeonardoMD")
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
            Form { syncFrequency }
                .navigationTitle("Sincronización")
                .toolbar { Button("Cerrar") { presentedSheet = nil } }
        }
    }
}

struct MobileProjectView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var exporting = false
    private var project: OfflineProject? { library.projects.first { $0.id == projectID } }
    var body: some View {
        List {
            if let project {
                Section {
                    Text("Disponible offline · Solo lectura").font(.caption).foregroundStyle(.secondary)
                    Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)").font(.caption)
                    if project.isRecoveryArchive {
                        Text("Esta copia antigua conserva tus cambios locales y enviados. Expórtala para recuperarlos en un ordenador. No se editará ni se enviará automáticamente.")
                        Button("Exportar recuperación", systemImage: "square.and.arrow.up") { exporting = true }
                            .accessibilityIdentifier("export-recovery")
                    }
                }
                ForEach(project.files.filter { ["md", "markdown", "txt"].contains(($0.path as NSString).pathExtension.lowercased()) }, id: \.path) { file in
                    NavigationLink(file.path) {
                        MobileDocumentView(library: library, projectID: project.id, file: file)
                    }
                }
            }
        }.navigationTitle(project?.name ?? "Proyecto")
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
        MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: true, externalLinkPolicy: .blocked,
            localAssetRoot: virtualRoot, memoryAssets: assets, allowsRemoteImages: false)
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
