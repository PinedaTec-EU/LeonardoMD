import SwiftUI
import LeonardoCore

import LeonardoSync
import LeonardoRender
import LeonardoSyncUI

enum MobileRecoveryArchiveCopy {
    static func summary(spanish: Bool) -> String {
        spanish
            ? "Esta copia antigua conserva tus cambios locales y enviados. Expórtala para recuperarlos en un ordenador. No se editará ni se enviará automáticamente."
            : "This older copy preserves your local and submitted changes. Export it to recover them on a computer. It won't be edited or sent automatically."
    }

    static func exportAction(spanish: Bool) -> String {
        spanish ? "Exportar recuperación" : "Export recovery"
    }

    static func retainedFile(size: String, spanish: Bool) -> String {
        spanish ? "Archivo conservado para exportación · \(size)" : "File retained for export · \(size)"
    }
}

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
    @State private var importedSigningCopy: MobileSigningExchangeDocument?
    @State private var importingSigningCopy = false
    @State private var presentedRubricRequest: RubricRequest?
    @AppStorage("directSyncIntervalMinutes") private var syncInterval = 1
    @AppStorage(LeonardoProjectFileVisibility.showNonDocumentFilesPreferenceKey) private var showNonDocumentFiles = false
    @Environment(\.scenePhase) private var scenePhase
    private var spanishErrors: Bool {
        MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
    }
    private var activeRubricDraft: MobileRubricDraft? {
        library.recoverableRubricDrafts.first { $0.state != .submitted }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Mac conectados") {
                    let activeConnections = library.connections.filter { !$0.revoked }
                    if activeConnections.isEmpty {
                        if localLibraryProjects.isEmpty {
                            VStack(spacing: 16) {
                                MobileBrand(size: 64)
                                Text("Tus documentos, contigo").font(.title2.bold()).foregroundStyle(MobileClassic.heading)
                                Text("Conecta tu Mac y consulta sus proyectos sin conexión.")
                                    .multilineTextAlignment(.center).foregroundStyle(MobileClassic.secondary)
                                Button("Conectar con mi Mac") { presentedSheet = .direct }
                                    .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper)
                                    .disabled(library.connecting)
                                Label("Solo lectura", systemImage: "lock").font(.footnote)
                            }
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Los proyectos compartidos aparecerán aquí al conectar un Mac.")
                                .font(.subheadline).foregroundStyle(MobileClassic.secondary)
                        }
                    }
                    ForEach(activeConnections) { connection in
                        MobileSharedHostDisclosureRow(library: library, connection: connection,
                            descriptors: sharedProjectDescriptors(for: connection)) { descriptor, entry in
                                selectedRemoteFile = MobileRemoteFileRoute(projectID: descriptor.id, entry: entry)
                            }
                    }
                }

                if !localLibraryProjects.isEmpty {
                    Section("En este dispositivo") {
                        ForEach(localLibraryProjects) { project in
                            MobileLocalLibraryProjectRow(library: library, project: project)
                        }
                    }.listRowBackground(MobileClassic.paper)
                }
            }
            .classicSurface()
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedRemoteFile) { route in
                MobileRemoteDocumentPreview(library: library.downloads, projectID: route.projectID,
                    entry: route.entry, spanish: spanishErrors, appearance: .leonardoClassic,
                    compactFirstHeading: true,
                    failureDiagnosticPresentation: { error, identity, shouldRecord in
                        let notice = MobileErrorNotice.record(
                            error,
                            operation: .downloads,
                            message: MobileErrorNotice.documentDownloadMessage(spanish: spanishErrors),
                            spanish: spanishErrors,
                            diagnosticIdentity: identity,
                            shouldRecord: shouldRecord)
                        library.error = notice
                        return notice.inlineMessage
                    }).classicSurface()
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
            .sheet(item: $importedSigningCopy) { copy in
                NavigationStack {
                    MobileGuidedSigningView(library: library, exchange: copy.exchange)
                }
            }
            .fileImporter(
                isPresented: $importingSigningCopy,
                allowedContentTypes: MobileSigningExchangeDocument.readableContentTypes,
                allowsMultipleSelection: false
            ) { result in
                importSigningCopy(result)
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
        .alert(MobileErrorNotice.alertTitle(spanish: spanishErrors), isPresented: Binding(
            get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button(MobileErrorNotice.acceptLabel(spanish: spanishErrors)) { library.error = nil }
        } message: { Text(library.error?.localizedAlertMessage(spanish: spanishErrors) ?? "") }
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
                MobileQRScannerScreen(
                    spanish: spanishErrors,
                    receive: { qrURL = $0 },
                    failure: { library.error = $0 })
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
        var descriptors = connection.projectDescriptors.filter {
            connection.projectIDs.contains($0.id) && !library.projectLifecycle.isDeleted($0.id)
        }
        let known = Set(descriptors.map(\.id))
        for project in library.projects where connection.projectIDs.contains(project.id)
            && connection.acceptedProjectIDs.contains(project.id)
            && !library.projectLifecycle.isDeleted(project.id) && !known.contains(project.id) {
            descriptors.append(SharedProjectDescriptor(id: project.id, name: project.name, scope: project.scope))
        }
        return descriptors.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var syncFrequency: some View {
        Group {
            Picker(
                spanishErrors ? "Sincronización automática" : "Automatic synchronization",
                selection: $syncInterval
            ) {
                Text(spanishErrors ? "Solo manual" : "Manual only")
                    .tag(0)
                    .accessibilityIdentifier("sync-frequency-option-0")
                ForEach([1, 5, 15, 30, 60], id: \.self) { minutes in
                    Text(spanishErrors ? "Cada \(minutes) min" : "Every \(minutes) min")
                        .tag(minutes)
                        .accessibilityIdentifier("sync-frequency-option-\(minutes)")
                }
            }
            .accessibilityIdentifier("sync-frequency-picker")
            Text(spanishErrors
                 ? "La sincronización automática funciona mientras la app está activa."
                 : "Automatic synchronization runs while the app is active.")
                .font(.caption)
                .accessibilityIdentifier("sync-frequency-note")
        }
    }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Conectar", systemImage: "qrcode") { presentedSheet = .direct }
                .disabled(library.connecting)
                .accessibilityIdentifier("open-pairing")
            Button { presentedSheet = .settings } label: {
                Label(MobileErrorNotice.syncSettingsLabel(spanish: spanishErrors), systemImage: "gearshape")
            }
                .accessibilityIdentifier("open-sync-settings")
            Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath") {
                Task { await library.synchronize() }
            }.disabled(library.connecting)
            Button(spanishErrors ? "Importar copia firmada" : "Import signing copy",
                   systemImage: "square.and.arrow.down") {
                importingSigningCopy = true
            }
            .accessibilityIdentifier("import-mobile-signing-copy")
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

    private func importSigningCopy(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= LeonardoSigningExchange.maximumEnvelopeBytes else {
                throw LeonardoSigningError.storageFailure
            }
            importedSigningCopy = MobileSigningExchangeDocument(
                exchange: try LeonardoSigningExchange.decoded(Data(contentsOf: url, options: [.mappedIfSafe]))
            )
        } catch {
            library.presentError(error, operation: .library,
                                 message: spanishErrors
                                 ? "No se pudo abrir la copia de firma."
                                 : "The signing copy could not be opened.")
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
                MobileMarkdownExtensionsSettings(preferences: .shared, spanish: spanishErrors)
                Section(spanishErrors ? "Frecuencia" : "Frequency") { syncFrequency }
                    .listRowBackground(MobileClassic.inset)
                Section("Proyectos / Projects") {
                    Button("Recuperar demo / Restore demo", systemImage: "arrow.counterclockwise") {
                        do { try library.projectLifecycle.restoreDemo() }
                        catch {
                            library.presentError(error, operation: .practice,
                                                 message: "No se pudo recuperar la demo.")
                        }
                    }
                    .disabled(library.projectLifecycle.demoIsVisible)
                    .accessibilityIdentifier("restore-demo-project")
                    Text("Recupera el proyecto con tus respuestas de práctica guardadas en este dispositivo. / Restore the project with your practice answers saved on this device.")
                        .font(.caption)
                }.listRowBackground(MobileClassic.inset)
                Section(spanishErrors ? "Archivos del proyecto" : "Project files") {
                    Toggle(spanishErrors ? "Mostrar archivos que no sean documentos" : "Show non-document files",
                           isOn: $showNonDocumentFiles)
                        .accessibilityIdentifier("show-non-document-files")
                    Text(spanishErrors
                         ? "Incluye imágenes y otros archivos en los listados. Las imágenes referenciadas desde Markdown siguen cargándose aunque ocultes sus archivos."
                         : "Includes images and other files in project lists. Images referenced from Markdown still load when their files are hidden.")
                        .font(.caption)
                }.listRowBackground(MobileClassic.inset)
                SyncCacheSettingsView(library: library.downloads, spanish: spanishErrors).listRowBackground(MobileClassic.inset)
                Section {
                    Button("Acerca de Little Leonardo", systemImage: "info.circle") { presentedSheet = .about }
                        .accessibilityIdentifier("open-about")
                }.listRowBackground(MobileClassic.inset)
                Section(MobileErrorLogCopy.diagnosticsSection(spanish: spanishErrors)) {
                    NavigationLink {
                        MobileErrorLogView(spanish: spanishErrors)
                    } label: {
                        Label(MobileErrorLogCopy.openLog(spanish: spanishErrors),
                              systemImage: "doc.text.magnifyingglass")
                    }
                        .accessibilityIdentifier("open-error-log")
                }.listRowBackground(MobileClassic.inset)
            }
                .classicSurface()
                .navigationTitle(MobileErrorLogCopy.synchronizationTitle(spanish: spanishErrors))
                .toolbar {
                    Button(MobileErrorLogCopy.close(spanish: spanishErrors)) { presentedSheet = nil }
                        .accessibilityIdentifier("close-sync-settings")
                }
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

struct MobileProjectView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var exporting = false
    @State private var selectedEntry: RemoteFileEntry?
    @AppStorage(LeonardoProjectFileVisibility.showNonDocumentFilesPreferenceKey) private var showNonDocumentFiles = false
    private var spanishErrors: Bool {
        MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
    }
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
                                      spanish: spanishErrors, rowBackground: MobileClassic.paper,
                                      showNonDocumentFiles: showNonDocumentFiles,
                                      fileVisibilitySurface: .littleLeonardo) { entry in
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
                                Text(MobileRecoveryArchiveCopy.summary(spanish: spanishErrors))
                                Button(MobileRecoveryArchiveCopy.exportAction(spanish: spanishErrors),
                                       systemImage: "square.and.arrow.up") { exporting = true }
                                    .accessibilityIdentifier("export-recovery")
                            }
                        }
                        .listRowBackground(MobileClassic.inset)
                        ForEach(project.files.filter {
                            LeonardoProjectFileVisibility.shouldShowFile(at: $0.path,
                                                                         showNonDocumentFiles: showNonDocumentFiles,
                                                                         on: .littleLeonardo)
                        }, id: \.path) { file in
                            if LeonardoProjectFileVisibility.isSupportedDocumentExtension(
                                (file.path as NSString).pathExtension, on: .littleLeonardo) {
                                NavigationLink(file.path) {
                                    MobileDocumentView(library: library, projectID: project.id, file: file)
                                }.listRowBackground(MobileClassic.paper)
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.path)
                                    Text(MobileRecoveryArchiveCopy.retainedFile(
                                        size: ByteCountFormatter.string(fromByteCount: Int64(file.content.count), countStyle: .file),
                                        spanish: spanishErrors))
                                        .font(.caption).foregroundStyle(MobileClassic.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("recovery-file-info")
                                .listRowBackground(MobileClassic.paper)
                            }
                        }
                    }
                }
            }
        }.classicSurface().navigationTitle(project?.name ?? "Proyecto")
        .navigationDestination(item: $selectedEntry) { entry in
            MobileRemoteDocumentPreview(
                library: library.downloads,
                projectID: projectID,
                entry: entry,
                spanish: spanishErrors,
                appearance: .leonardoClassic,
                compactFirstHeading: true,
                failureDiagnosticPresentation: { error, identity, shouldRecord in
                    MobileErrorNotice.record(
                        error,
                        operation: .downloads,
                        message: MobileErrorNotice.documentLoadMessage(spanish: spanishErrors),
                        spanish: spanishErrors,
                        diagnosticIdentity: identity,
                        shouldRecord: shouldRecord).inlineMessage
                }).classicSurface()
        }
        .fileExporter(isPresented: $exporting, document: project.map(MobileRecoveryDocument.init),
                      contentType: .json, defaultFilename: "LittleLeonardo-\(projectID.uuidString)-recovery") { result in
            if case .failure(let error) = result {
                library.presentError(error, operation: .export,
                                     message: "No se pudo exportar el archivo de recuperación.")
            }
        }
    }
}
