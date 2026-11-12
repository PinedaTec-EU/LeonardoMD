import SwiftUI
import LeonardoCore
import LeonardoSync
import LeonardoRender
import LeonardoSyncUI

private enum MobileLibrarySheet: String, Identifiable {
    case direct, settings, about
    var id: String { rawValue }
}

extension OfflineProject {
    /// iOS only receives direct-sync projects from another device. The legacy
    /// Git payload remains a local recovery archive and must not look remote.
    var projectIdentity: ProjectIdentity {
        isRecoveryArchive ? .recoveryArchive : .received
    }
}

extension MobileLibraryProject {
    /// The library list is a presentation boundary. A downloaded direct-sync
    /// project is still received from another device; only the bundled demo is
    /// local, and a legacy Git payload remains a recovery archive.
    var projectIdentity: ProjectIdentity {
        switch self {
        case .demo: .local
        case .downloaded(let project): project.projectIdentity
        }
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct MobileRemoteFileRoute: Hashable, Identifiable {
    let projectID: UUID
    let entry: RemoteFileEntry
    var id: String { projectID.uuidString + ":" + entry.path }
}

struct MobileProjectIdentityLabel: View {
    let name: String
    let identity: ProjectIdentity
    let accessibilityIdentifier: String?

    init(name: String, identity: ProjectIdentity, accessibilityIdentifier: String? = "project-identity") {
        self.name = name
        self.identity = identity
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var bilingualRole: String {
        let spanish = identity.title(languageCode: "es")
        let english = identity.title(languageCode: "en")
        return spanish == english ? spanish : "\(spanish) · \(english)"
    }

    var accessibilityText: String { "\(name), \(bilingualRole)" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: ProjectIdentity.projectSymbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MobileClassic.heading)
                if let indicator = identity.indicatorSymbolName {
                    Image(systemName: indicator)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MobileClassic.accent)
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(MobileClassic.heading)
                Text(bilingualRole)
                    .font(.caption)
                    .foregroundStyle(MobileClassic.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }
}

struct MobileLibraryView: View {
    @Bindable var library: MobileLibrary
    @State private var presentedSheet: MobileLibrarySheet?
    @State private var qrURL = ""
    @State private var scanning = false
    @State private var manualPairing = false
    @State private var host = ""
    @State private var port = "40882"
    @State private var selectedRemoteFile: MobileRemoteFileRoute?
    @State private var presentedRubricRequest: RubricRequest?
    @AppStorage("directSyncIntervalMinutes") private var syncInterval = 1
    @Environment(\.scenePhase) private var scenePhase
    private var activeRubricDraft: MobileRubricDraft? {
        library.recoverableRubricDrafts.first { $0.state != .submitted }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Mac conectados") {
                    let activeConnections = library.connections.filter { !$0.revoked }
                    if activeConnections.isEmpty {
                        Text("Los proyectos compartidos aparecerán aquí al conectar un Mac.")
                            .font(.subheadline).foregroundStyle(MobileClassic.secondary)
                    }
                    ForEach(activeConnections) { connection in
                        MobileSharedHostDisclosureRow(library: library, connection: connection,
                            descriptors: sharedProjectDescriptors(for: connection)) { descriptor, entry in
                                selectedRemoteFile = MobileRemoteFileRoute(projectID: descriptor.id, entry: entry)
                            }
                    }
                }

                Section("En este dispositivo") {
                    ForEach(localLibraryProjects) { project in
                        MobileLocalLibraryProjectRow(library: library, project: project)
                    }
                    if localLibraryProjects.isEmpty && library.connections.allSatisfy(\.revoked) {
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
            .navigationDestination(item: $selectedRemoteFile) { route in
                RemoteDocumentPreview(library: library.downloads, projectID: route.projectID,
                    entry: route.entry, spanish: true, appearance: .leonardoClassic,
                    compactFirstHeading: true).classicSurface()
            }
            .refreshable { await library.synchronize(); await library.reload() }
            .toolbar { libraryToolbar }
            .safeAreaInset(edge: .bottom) { bottomAccessory }
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

    private var localLibraryProjects: [MobileLibraryProject] {
        library.libraryProjects.filter { project in
            switch project {
            case .demo: true
            case .downloaded(let value): value.isRecoveryArchive
            }
        }
    }

    private func sharedProjectDescriptors(for connection: MobileDirectConnection) -> [SharedProjectDescriptor] {
        var descriptors = connection.projectDescriptors.filter { connection.projectIDs.contains($0.id) }
        let known = Set(descriptors.map(\.id))
        for project in library.projects where connection.projectIDs.contains(project.id)
            && connection.acceptedProjectIDs.contains(project.id) && !known.contains(project.id) {
            descriptors.append(SharedProjectDescriptor(id: project.id, name: project.name, scope: project.scope))
        }
        return descriptors.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
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
    }

    @ViewBuilder private var bottomAccessory: some View {
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

private struct MobileLocalLibraryProjectRow: View {
    @Bindable var library: MobileLibrary
    let project: MobileLibraryProject

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 5) {
                MobileProjectIdentityLabel(name: project.name, identity: project.projectIdentity,
                                           accessibilityIdentifier: nil)
                if isRecoveryArchive {
                    Text("Archivo de recuperación · Solo lectura")
                        .font(.caption).foregroundStyle(MobileClassic.secondary)
                }
            }
        }
        // Keep the stable navigation contract on the outer link; the identity
        // label remains a child of the navigable row.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(project.id == "bundled-demo" ? "open-demo-project" : "open-project-\(project.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Eliminar / Delete", role: .destructive) {
                Task { await library.deleteLibraryProject(project) }
            }
            .disabled(library.connecting)
            .accessibilityIdentifier(project.id == "bundled-demo" ? "delete-demo-project" : "delete-project-\(project.id)")
        }
    }

    @ViewBuilder private var destination: some View {
        switch project {
        case .demo: MobileDemoProjectView()
        case .downloaded(let cached): MobileProjectView(library: library, projectID: cached.id)
        }
    }

    private var isRecoveryArchive: Bool {
        guard case .downloaded(let cached) = project else { return false }
        return cached.isRecoveryArchive
    }
}

private struct MobileSharedHostDisclosureRow: View {
    @Bindable var library: MobileLibrary
    let connection: MobileDirectConnection
    let descriptors: [SharedProjectDescriptor]
    let openFile: (SharedProjectDescriptor, RemoteFileEntry) -> Void

    var body: some View {
        DisclosureGroup {
            if descriptors.isEmpty {
                Text("Este Mac todavía no comparte proyectos.")
                    .font(.subheadline).foregroundStyle(MobileClassic.secondary)
            }
            ForEach(descriptors) { descriptor in
                projectRow(descriptor)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title3).foregroundStyle(MobileClassic.heading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.hostDisplayName(connection.endpoint))
                        .font(.headline).foregroundStyle(MobileClassic.heading)
                    let pendingCount = connection.projectIDs.subtracting(connection.ignoredProjectIDs)
                        .subtracting(connection.acceptedProjectIDs).count
                    let totalCount = connection.projectIDs.count
                    Text(totalCount == 0 ? "Conexión activa" :
                         "\(totalCount) proyectos · \(pendingCount) por revisar")
                        .font(.caption).foregroundStyle(MobileClassic.secondary)
                }
            }
            .accessibilityIdentifier("shared-host-\(connection.connectionID)")
        }
        .listRowBackground(MobileClassic.paper)
    }

    @ViewBuilder private func projectRow(_ descriptor: SharedProjectDescriptor) -> some View {
        if connection.acceptedProjectIDs.contains(descriptor.id) {
            MobileSharedProjectTreeRow(library: library, connection: connection,
                descriptor: descriptor, newFilePaths: connection.newFilePaths[descriptor.id] ?? []) { entry in
                    openFile(descriptor, entry)
                }
        } else {
            MobileIncomingSharedProjectRow(library: library, connection: connection,
                                           descriptor: descriptor,
                                           ignored: connection.ignoredProjectIDs.contains(descriptor.id))
        }
    }

    private static func hostDisplayName(_ endpoint: URL) -> String {
        guard var host = endpoint.host, !host.isEmpty else { return "Mac conectado" }
        if host.lowercased().hasSuffix(".local") { host.removeLast(6) }
        host = host.replacingOccurrences(of: "-", with: " ")
        return host.prefix(1).uppercased() + String(host.dropFirst())
    }
}

private struct MobileIncomingSharedProjectRow: View {
    @Bindable var library: MobileLibrary
    let connection: MobileDirectConnection
    let descriptor: SharedProjectDescriptor
    let ignored: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.name).font(.headline).foregroundStyle(MobileClassic.heading)
                Label(ignored ? "Ignorado" : "Proyecto nuevo",
                      systemImage: ignored ? "minus.circle" : "sparkle")
                    .font(.caption).foregroundStyle(MobileClassic.secondary)
            }
            Spacer(minLength: 4)
            if !ignored {
                Button("Añadir") { addProject() }
                    .buttonStyle(.borderedProminent).tint(MobileClassic.heading)
                    .foregroundStyle(MobileClassic.paper).disabled(library.connecting)
                Button("Ignorar") {
                    library.ignoreSharedProject(connectionID: connection.connectionID, projectID: descriptor.id)
                }
                .buttonStyle(.bordered).disabled(library.connecting)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("incoming-project-\(descriptor.id)")
    }

    private func addProject() {
        Task { await library.acceptSharedProject(connectionID: connection.connectionID, projectID: descriptor.id) }
    }
}

private struct MobileSharedProjectTreeRow: View {
    @Bindable var library: MobileLibrary
    let connection: MobileDirectConnection
    let descriptor: SharedProjectDescriptor
    let newFilePaths: Set<String>
    let open: (RemoteFileEntry) -> Void

    private var cached: CachedRemoteProject? {
        library.downloads.projects.first { $0.id == descriptor.id }
    }
    private var isKeepingProjectOffline: Bool { cached?.keepsFolder("") == true }
    private var hasRetainedFiles: Bool {
        guard let cached else { return false }
        return cached.catalogue.files.contains { cached.keeps($0.path) }
    }
    private var releasableFiles: [RemoteFileEntry] {
        guard let cached else { return [] }
        return cached.catalogue.files.filter { entry in
            !cached.keeps(entry.path) && cached.isDownloaded(entry)
        }
    }

    var body: some View {
        DisclosureGroup {
            if let cached {
                if cached.catalogue.files.isEmpty {
                    Text("Este proyecto no tiene ficheros compartidos.")
                        .font(.subheadline).foregroundStyle(MobileClassic.secondary)
                }
                ForEach(cached.catalogue.files.sorted {
                    $0.path.localizedStandardCompare($1.path) == .orderedAscending
                }) { entry in
                    fileRow(entry, project: cached)
                }
            } else {
                Text("Sincroniza para cargar los ficheros compartidos.")
                    .font(.subheadline).foregroundStyle(MobileClassic.secondary)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(MobileClassic.heading).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.name).font(.headline).foregroundStyle(MobileClassic.heading)
                    Text(projectStatus)
                        .font(.caption).foregroundStyle(MobileClassic.secondary)
                    if isKeepingProjectOffline {
                        Text("Incluye los ficheros nuevos")
                            .font(.caption2).foregroundStyle(MobileClassic.secondary)
                    }
                }
                Spacer(minLength: 4)
                projectMenu
            }
            .contentShape(Rectangle())
            .accessibilityIdentifier("shared-project-\(descriptor.id)")
        }
        .listRowBackground(MobileClassic.paper)
    }

    private var projectStatus: String {
        guard let cached else { return "Solo remoto" }
        let entries = cached.catalogue.files
        guard !entries.isEmpty else { return "Sin ficheros" }
        let downloaded = entries.filter { cached.isDownloaded($0) }.count
        if isKeepingProjectOffline {
            let availability = entries.allSatisfy { cached.isAvailableOffline($0) }
                ? "Disponible sin conexión" : "Sin conexión pendiente"
            return "\(availability) · \(downloaded)/\(entries.count) ficheros"
        }
        return downloaded == 0 ? "Solo remoto" : "En caché · \(downloaded)/\(entries.count) ficheros"
    }

    private var projectMenu: some View {
        Menu {
            Button(isKeepingProjectOffline ? "Dejar de mantener sin conexión" : "Mantener sin conexión",
                   systemImage: isKeepingProjectOffline ? "pin.slash" : "pin") {
                if !isKeepingProjectOffline {
                    library.dismissNewFiles(connectionID: connection.connectionID, projectID: descriptor.id)
                }
                Task {
                    await library.downloads.retain(id: descriptor.id, path: "", isFolder: true,
                                                   keep: !isKeepingProjectOffline)
                }
            }
            .disabled(cached == nil || library.connecting)
            Button("Liberar espacio local", systemImage: "externaldrive.badge.minus") {
                Task { await library.downloads.release(id: descriptor.id, path: "", isFolder: true) }
            }
            .disabled(releasableFiles.isEmpty || library.connecting)
            if hasRetainedFiles {
                Text("Los ficheros fijados se conservan. Deja de mantenerlos sin conexión para liberarlos.")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(MobileClassic.heading)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Acciones de \(descriptor.name)")
        .accessibilityIdentifier("shared-project-actions-\(descriptor.id)")
    }

    private func fileRow(_ entry: RemoteFileEntry, project: CachedRemoteProject) -> some View {
        let isNew = newFilePaths.contains(entry.path)
        let retained = project.keeps(entry.path)
        let downloaded = project.isDownloaded(entry)
        return HStack(spacing: 10) {
            Button {
                if isNew {
                    library.dismissNewFile(connectionID: connection.connectionID,
                                           projectID: descriptor.id, path: entry.path)
                }
                open(entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text((entry.path as NSString).lastPathComponent)
                        .foregroundStyle(MobileClassic.heading)
                        .lineLimit(1)
                    if let parent = parentPath(entry.path) {
                        Text(parent).font(.caption2).foregroundStyle(MobileClassic.secondary).lineLimit(1)
                    }
                    if isNew {
                        Label("Archivo nuevo", systemImage: "sparkle")
                            .font(.caption2).foregroundStyle(MobileClassic.accent)
                    } else {
                        Text(fileStatus(project: project, entry: entry))
                            .font(.caption2).foregroundStyle(MobileClassic.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shared-file-\(descriptor.id)-\(entry.path)")
            Menu {
                Button("Abrir", systemImage: "doc.text") {
                    if isNew {
                        library.dismissNewFile(connectionID: connection.connectionID,
                                               projectID: descriptor.id, path: entry.path)
                    }
                    open(entry)
                }
                Button(retained ? "Dejar de mantener sin conexión" : "Mantener sin conexión",
                       systemImage: retained ? "pin.slash" : "pin") {
                    if isNew {
                        library.dismissNewFile(connectionID: connection.connectionID,
                                               projectID: descriptor.id, path: entry.path)
                    }
                    Task { await library.downloads.retain(id: descriptor.id, path: entry.path,
                                                          isFolder: false, keep: !retained) }
                }
                Button("Liberar espacio local", systemImage: "externaldrive.badge.minus") {
                    Task { await library.downloads.release(id: descriptor.id, path: entry.path, isFolder: false) }
                }
                .disabled(!downloaded || retained || library.connecting)
                if isNew {
                    Button("Ignorar novedad", systemImage: "xmark.circle") {
                        library.dismissNewFile(connectionID: connection.connectionID,
                                               projectID: descriptor.id, path: entry.path)
                    }
                    Text("No se descarga. Puedes abrirlo más adelante.")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileClassic.heading)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Acciones de \((entry.path as NSString).lastPathComponent)")
            .accessibilityIdentifier("shared-file-actions-\(descriptor.id)-\(entry.path)")
        }
        .padding(.vertical, 3)
        .listRowBackground(MobileClassic.paper)
    }

    private func fileStatus(project: CachedRemoteProject, entry: RemoteFileEntry) -> String {
        if project.isAvailableOffline(entry) { return "Disponible sin conexión" }
        if project.keeps(entry.path) { return "Sin conexión pendiente" }
        return project.isDownloaded(entry) ? "En caché" : "Solo remoto"
    }

    private func parentPath(_ path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? nil : parent
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
                VStack(alignment: .leading, spacing: 0) {
                    MobileProjectIdentityLabel(name: project.name, identity: project.projectIdentity)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MobileClassic.inset)
                    SyncCatalogueView(library: library.downloads, projectID: project.id,
                                      spanish: true, rowBackground: MobileClassic.paper) { entry in
                        selectedEntry = entry
                    }
                }
            } else {
                List {
                    if let project {
                        Section {
                            MobileProjectIdentityLabel(name: project.name, identity: project.projectIdentity)
                            Text("Disponible offline · Solo lectura")
                                .font(.caption).foregroundStyle(MobileClassic.secondary)
                            Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)")
                                .font(.caption)
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
