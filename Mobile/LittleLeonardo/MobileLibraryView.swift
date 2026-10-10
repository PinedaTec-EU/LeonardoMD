import SwiftUI
import LeonardoSync
import LeonardoRender

private enum MobileLibrarySheet: String, Identifiable {
    case direct, git, settings
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
    @AppStorage("gitAuthorName") private var gitAuthorName = "Little Leonardo"
    @AppStorage("gitAuthorEmail") private var gitAuthorEmail = "little-leonardo@local.invalid"
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List(library.projects, id: \.id) { project in
                NavigationLink {
                    MobileProjectView(library: library, projectID: project.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(project.name)
                        Text(project.mode == .direct ? "Consulta desde LeonardoMD" : "Edición mediante Git")
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
                Button("Conectar Git", systemImage: "arrow.triangle.branch") { presentedSheet = .git }
                    .disabled(library.connecting).accessibilityIdentifier("open-git-pairing")
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
                case .git: MobileGitConnectionView(library: library)
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
            Form {
                syncFrequency
                Section("Autor de los commits Git") {
                    TextField("Nombre", text: $gitAuthorName)
                    TextField("Correo", text: $gitAuthorEmail).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Esta identidad aparecerá en los commits enviados.").font(.caption)
                }
            }
                .navigationTitle("Sincronización")
                .toolbar { Button("Cerrar") { presentedSheet = nil } }
        }
    }

}

struct MobileProjectView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var newDocument = false
    @State private var documentName = ""
    @State private var deletingPath: String?
    @AppStorage("gitAuthorName") private var gitAuthorName = "Little Leonardo"
    @AppStorage("gitAuthorEmail") private var gitAuthorEmail = "little-leonardo@local.invalid"
    private var project: OfflineProject? { library.projects.first { $0.id == projectID } }
    var body: some View {
        List {
            if let project {
                Section {
                    Text(project.mode == .direct ? "Disponible offline · Solo lectura" : "Disponible offline · Git")
                        .font(.caption).foregroundStyle(.secondary)
                    if let status = library.gitStatus[project.id] { Text(status).font(.caption).foregroundStyle(.secondary) }
                    Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)")
                        .font(.caption)
                }
                ForEach(project.files.filter { ["md", "markdown", "txt"].contains(($0.path as NSString).pathExtension.lowercased()) }, id: \.path) { file in
                    NavigationLink(file.path) {
                        MobileDocumentView(library: library, projectID: project.id, file: file, mode: project.mode)
                    }.swipeActions {
                        if project.mode == .git {
                            Button("Eliminar", role: .destructive) { deletingPath = file.path }
                                .disabled(library.connecting)
                        }
                    }
                }
            }
        }.navigationTitle(project?.name ?? "Proyecto")
        .toolbar {
            if let project, project.mode == .git {
                NavigationLink {
                    MobileGitDirectMappingView(library: library, projectID: projectID)
                } label: {
                    Label("Avisar a LeonardoMD", systemImage: "bell")
                }.accessibilityIdentifier("git-direct-notification-settings")
                Button("Nuevo documento", systemImage: "doc.badge.plus") { newDocument = true }
                    .disabled(library.connecting)
                Button("Enviar cambios", systemImage: "arrow.up.circle") {
                    Task { await library.sendGitProject(projectID: projectID, authorName: gitAuthorName, authorEmail: gitAuthorEmail) }
                }.disabled(library.connecting || project.publication == .sent && !library.pendingGitSends.contains(projectID)
                           || !project.hasLocalChanges && !library.pendingGitSends.contains(projectID))
                    .accessibilityIdentifier("git-send-changes")
                if library.gitReconciliationRequired.contains(projectID), !project.hasLocalChanges {
                    Button("Solicitar reconciliación", systemImage: "arrow.triangle.branch") {
                        Task {
                            await library.sendGitProject(projectID: projectID, authorName: gitAuthorName,
                                authorEmail: gitAuthorEmail, purpose: .reconciliationRequest)
                        }
                    }.disabled(library.connecting || project.publication == .sent)
                        .accessibilityIdentifier("git-request-reconciliation")
                }
            }
        }
        .alert("Nuevo documento", isPresented: $newDocument) {
            TextField("Nombre.md", text: $documentName)
            Button("Crear") {
                guard let project else { return }
                let path = project.scope.folder.isEmpty ? documentName : project.scope.folder + "/" + documentName
                Task {
                    if await library.createDocument(projectID: projectID, path: path) { documentName = "" }
                }
            }.disabled(library.connecting)
            Button("Cancelar", role: .cancel) { documentName = "" }
        } message: { Text("Se creará dentro de la carpeta autorizada del proyecto.") }
        .alert("Eliminar documento", isPresented: Binding(get: { deletingPath != nil }, set: { if !$0 { deletingPath = nil } })) {
            Button("Eliminar", role: .destructive) {
                guard let path = deletingPath else { return }
                Task { _ = await library.deleteFile(projectID: projectID, path: path) }
                deletingPath = nil
            }.disabled(library.connecting)
            Button("Cancelar", role: .cancel) { deletingPath = nil }
        } message: { Text(deletingPath ?? "") }
    }
}

struct MobileDocumentView: View {
    let library: MobileLibrary
    let projectID: UUID
    let file: CorpusFile
    let mode: SyncMode
    var initialAnchor: String? = nil
    @State private var text = ""
    @State private var editing = false
    @State private var holdsEditingLease = false
    @State private var readOnlyNotice = false
    @State private var saving = false
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
    private var liveProject: OfflineProject? {
        library.projects.first { $0.id == projectID }
    }
    private var liveFile: CorpusFile? {
        library.currentFile(projectID: projectID, path: file.path)
    }
    private var canEditLiveFile: Bool {
        guard let liveFile else { return false }
        return editing || String(data: liveFile.content, encoding: .utf8) != nil
    }

    var body: some View {
        Group {
            if liveProject == nil {
                ContentUnavailableView("Acceso retirado", systemImage: "lock", description: Text("La copia local de este proyecto se ha eliminado."))
            } else if liveFile == nil {
                ContentUnavailableView("Documento eliminado", systemImage: "trash",
                    description: Text("La integración eliminó este documento del corpus local."))
            } else if editing { TextEditor(text: $text).font(.system(.body, design: .monospaced)).padding() }
            else if !source, ["md", "markdown"].contains((file.path as NSString).pathExtension.lowercased()) {
                MarkdownPreview(content: text,
                    baseURL: virtualRoot.appendingPathComponent(file.path).deletingLastPathComponent(),
                    configuration: previewConfiguration, controller: previewController,
                    onLinkActivation: followLink)
            } else {
                ScrollView {
                    Text(text).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        }
        .navigationTitle((file.path as NSString).lastPathComponent)
        .toolbar {
            Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath") {
                Task { await library.synchronize() }
            }.disabled(library.connecting || editing)
                .accessibilityIdentifier("document-sync")
            if !editing {
                Button(source ? "Ver documento" : "Ver texto", systemImage: "chevron.left.forwardslash.chevron.right") { source.toggle() }
            }
            Button(editing ? "Guardar" : "Editar") {
                if editing {
                    guard liveFile != nil else {
                        markDocumentUnavailable()
                        return
                    }
                    saving = true
                    Task {
                        if await library.saveText(projectID: projectID, path: file.path, text: text) {
                            editing = false
                            releaseEditingLease()
                        } else if library.currentFile(projectID: projectID, path: file.path) == nil {
                            markDocumentUnavailable()
                        }
                        saving = false
                    }
                } else if liveProject?.mode == .direct { readOnlyNotice = true }
                else if liveFile == nil {
                    markDocumentUnavailable()
                } else if library.beginDocumentEditing(projectID: projectID, path: file.path) {
                    holdsEditingLease = true
                    editing = true
                }
            }.disabled(saving || library.connecting || !canEditLiveFile)
        }
        .onAppear {
            if editing, !holdsEditingLease {
                if liveProject == nil || liveFile == nil {
                    markDocumentUnavailable()
                } else {
                    holdsEditingLease = library.beginDocumentEditing(projectID: projectID, path: file.path)
                }
            }
            if !editing {
                if let liveFile {
                    text = String(data: liveFile.content, encoding: .utf8) ?? "El documento no contiene texto legible."
                } else {
                    markDocumentUnavailable()
                }
            }
            updateAssets(liveProject)
        }
        .onChange(of: library.projects) { _, projects in
            let project = projects.first { $0.id == projectID }
            updateAssets(project)
            guard project != nil, let liveFile else {
                markDocumentUnavailable()
                return
            }
            if !editing {
                text = String(data: liveFile.content, encoding: .utf8) ?? "El documento no contiene texto legible."
            }
        }
        .onDisappear { releaseEditingLease() }
        .alert("Este proyecto es de solo lectura", isPresented: $readOnlyNotice) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Para editar y enviar cambios desde Little Leonardo, crea un repositorio Git y conecta el proyecto mediante Git.")
        }
        .alert("Documento no disponible", isPresented: $unavailableLink) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text("El enlace no corresponde a un documento descargado dentro de la carpeta autorizada.") }
        .navigationDestination(isPresented: Binding(get: { linkedDocument != nil }, set: { if !$0 { linkedDocument = nil } })) {
            if let target = linkedDocument {
                MobileDocumentView(library: library, projectID: projectID, file: target.file,
                                   mode: mode, initialAnchor: target.anchor)
            }
        }
        .onChange(of: previewController.isReady) { _, ready in
            if ready, !didScrollToInitialAnchor, let initialAnchor {
                previewController.scroll(to: initialAnchor)
                didScrollToInitialAnchor = true
            }
        }
    }

    private func releaseEditingLease() {
        guard holdsEditingLease else { return }
        library.endDocumentEditing(projectID: projectID)
        holdsEditingLease = false
    }

    private func markDocumentUnavailable() {
        text = ""
        editing = false
        releaseEditingLease()
    }

    private func followLink(_ url: URL) {
        guard let project = library.projects.first(where: { $0.id == projectID }),
              let target = CachedDocumentLink(url: url, virtualRoot: virtualRoot,
                                              scope: project.scope, files: project.files) else {
            unavailableLink = true; return
        }
        if target.file.path == file.path {
            if let anchor = target.anchor { previewController.scroll(to: anchor) }
        } else { linkedDocument = target }
    }

    private func updateAssets(_ project: OfflineProject?) {
        assets = project.map { MarkdownMemoryAssets(files: Dictionary(uniqueKeysWithValues: $0.files.map { ($0.path, $0.content) })) }
    }
}
