import SwiftUI
import LeonardoSync

struct MobileLibraryView: View {
    @Bindable var library: MobileLibrary
    @State private var pairing = false
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
                Button("Conectar", systemImage: "qrcode") { pairing = true }
                    .disabled(library.connecting)
                    .accessibilityIdentifier("open-pairing")
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
            .sheet(isPresented: $pairing) {
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
                        Picker("Sincronización automática", selection: $syncInterval) {
                            Text("Solo manual").tag(0)
                            ForEach([1, 5, 15, 30, 60], id: \.self) { Text("Cada \($0) min").tag($0) }
                        }
                        Text("La sincronización automática funciona mientras la app está activa.").font(.caption)
                        Button("Solicitar conexión") {
                            Task {
                                if manualPairing {
                                    await library.connectManual(host: host, port: port, deviceName: UIDevice.current.name)
                                } else {
                                    await library.connect(qrURL: qrURL, deviceName: UIDevice.current.name)
                                }
                                if library.comparisonCode != nil { qrURL = ""; pairing = false }
                            }
                        }.disabled(library.connecting || (manualPairing ? host.isEmpty || (UInt16(port) ?? 0) == 0 : qrURL.isEmpty))
                    }.navigationTitle("Conectar con LeonardoMD")
                    .toolbar { Button("Cerrar") { pairing = false } }
                    .sheet(isPresented: $scanning) {
                        MobileQRScannerScreen { qrURL = $0 }
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
    }
}

struct MobileProjectView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var newDocument = false
    @State private var documentName = ""
    @State private var deletingPath: String?
    private var project: OfflineProject? { library.projects.first { $0.id == projectID } }
    var body: some View {
        List {
            if let project {
                Section {
                    Text(project.mode == .direct ? "Disponible offline · Solo lectura" : "Disponible offline · Git")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)")
                        .font(.caption)
                }
                ForEach(project.files.filter { ["md", "markdown", "txt"].contains(($0.path as NSString).pathExtension.lowercased()) }, id: \.path) { file in
                    NavigationLink(file.path) {
                        MobileDocumentView(library: library, projectID: project.id, file: file, mode: project.mode)
                    }.swipeActions {
                        if project.mode == .git {
                            Button("Eliminar", role: .destructive) { deletingPath = file.path }
                        }
                    }
                }
            }
        }.navigationTitle(project?.name ?? "Proyecto")
        .toolbar {
            if project?.mode == .git { Button("Nuevo documento", systemImage: "doc.badge.plus") { newDocument = true } }
        }
        .alert("Nuevo documento", isPresented: $newDocument) {
            TextField("Nombre.md", text: $documentName)
            Button("Crear") {
                guard let project else { return }
                let path = project.scope.folder.isEmpty ? documentName : project.scope.folder + "/" + documentName
                Task {
                    if await library.createDocument(projectID: projectID, path: path) { documentName = "" }
                }
            }
            Button("Cancelar", role: .cancel) { documentName = "" }
        } message: { Text("Se creará dentro de la carpeta autorizada del proyecto.") }
        .alert("Eliminar documento", isPresented: Binding(get: { deletingPath != nil }, set: { if !$0 { deletingPath = nil } })) {
            Button("Eliminar", role: .destructive) {
                guard let path = deletingPath else { return }
                Task { _ = await library.deleteFile(projectID: projectID, path: path) }
                deletingPath = nil
            }
            Button("Cancelar", role: .cancel) { deletingPath = nil }
        } message: { Text(deletingPath ?? "") }
    }
}

struct MobileDocumentView: View {
    let library: MobileLibrary
    let projectID: UUID
    let file: CorpusFile
    let mode: SyncMode
    @State private var text = ""
    @State private var editing = false
    @State private var readOnlyNotice = false
    @State private var saving = false

    var body: some View {
        Group {
            if !library.projects.contains(where: { $0.id == projectID }) {
                ContentUnavailableView("Acceso retirado", systemImage: "lock", description: Text("La copia local de este proyecto se ha eliminado."))
            } else if editing { TextEditor(text: $text).font(.system(.body, design: .monospaced)).padding() }
            else {
                ScrollView {
                    Text(text).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        }
        .navigationTitle((file.path as NSString).lastPathComponent)
        .toolbar {
            Button(editing ? "Guardar" : "Editar") {
                if editing {
                    saving = true
                    Task {
                        if await library.saveText(projectID: projectID, path: file.path, text: text) { editing = false }
                        saving = false
                    }
                } else if mode == .direct { readOnlyNotice = true }
                else { editing = true }
            }.disabled(saving || String(data: file.content, encoding: .utf8) == nil)
        }
        .onAppear { text = String(data: file.content, encoding: .utf8) ?? "Este documento no tiene una codificación UTF-8 válida." }
        .onChange(of: library.projects) { _, projects in
            if !projects.contains(where: { $0.id == projectID }) { text = ""; editing = false }
            else if mode == .direct {
                text = projects.first(where: { $0.id == projectID })?.files.first(where: { $0.path == file.path })
                    .flatMap { String(data: $0.content, encoding: .utf8) } ?? "El documento ya no está disponible."
            }
        }
        .alert("Este proyecto es de solo lectura", isPresented: $readOnlyNotice) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Para editar y enviar cambios desde Little Leonardo, crea un repositorio Git y conecta el proyecto mediante Git.")
        }
    }
}
