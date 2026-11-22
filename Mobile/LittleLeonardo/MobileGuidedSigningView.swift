import CryptoKit
import SwiftUI
import LeonardoCore

/// Offline signing of an explicitly selected copy. The shared project is only
/// read; the result leaves the phone as a user-exported exchange file.
struct MobileGuidedSigningView: View {
    let library: MobileLibrary
    let localDocumentLocation: String?
    private let initiallyShowingDocumentReader: Bool
    let initialExchange: LeonardoSigningExchange
    @Environment(\.dismiss) private var dismiss
    @State var document: LeonardoDocument?
    @State var session: LeonardoGuidedSigningSession
    @State var resources: [LeonardoSigningResource]
    @State var trustedCredentials: [LeonardoSigningCredential]
    @State var trustAccepted: Bool
    @State var locallyTrustedCredentialIDs: Set<String> = []
    @State var selectedTrustCredentialID: String?
    @State var trustFingerprintInput = ""
    @State var profiles: [LeonardoSignerProfile] = []
    @State var credentialIDs: [String] = []
    @State var selectedPositionID: String?
    @State var selectedProfileID: UUID?
    @State var selectedCredentialID = ""
    @State var creatingProfile = true
    @State var fullName = ""
    @State var documentType = LeonardoIdentityDocumentType.nationalID
    @State var documentNumber = ""
    // Saving the declared identity is a separate, opt-in consent. The
    // assignment still carries the entered details for its proof, but a new
    // local profile must not retain them by default.
    @State var saveIdentityDetails = false
    @State var saveRubric = false
    @State var profileRubric: LeonardoRubric?
    @State var selectedTargetIndex: Int?
    @State private var previewFocusTarget: LeonardoSigningLocationTarget?
    @State var availableTargetKeys: Set<String> = []
    @State var rubric = LeonardoRubric()
    @State private var rubricReuseChoice: LeonardoRubricReuse?
    @State private var showingRubric = false
    @State var showingDocumentReader = false
    @State private var showingEnrollment = false
    @State private var showingPassword = false
    @State private var showingExportDisclosure = false
    @State var exporting = false
    @State var exportDocument: MobileSigningExchangeDocument?
    @State var ready = false
    @State var hasInvalidSeal = false
    @State var storedBaseline: LeonardoGuidedSigningSession?
    @State var verification: [String: LeonardoSignatureVerification] = [:]
    @State private var showingProfileRubric = false
    @State private var profileRubricDraft = LeonardoRubric()
    @State var busy = false
    @State var errorMessage: String?
    @State var localLoadFailed = false

    init(
        library: MobileLibrary,
        exchange: LeonardoSigningExchange,
        localDocumentLocation: String? = nil,
        initiallyShowingDocumentReader: Bool = false
    ) {
        self.library = library
        self.initialExchange = exchange
        self.localDocumentLocation = localDocumentLocation
        self.initiallyShowingDocumentReader = initiallyShowingDocumentReader
        _document = State(initialValue: try? exchange.document())
        _session = State(initialValue: exchange.session)
        _resources = State(initialValue: (try? exchange.signingResources()) ?? [])
        _trustedCredentials = State(initialValue: exchange.trustedCredentials)
        _trustAccepted = State(initialValue: exchange.trustedCredentials.isEmpty)
    }

    var spanish: Bool {
        MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
    }

    private var selectedPosition: LeonardoSignerPosition? {
        guard let selectedPositionID else { return nil }
        return session.declaration.positions.first { $0.id == selectedPositionID }
    }

    private var selectedProgress: LeonardoSigningPositionProgress? {
        guard let selectedPositionID else { return nil }
        return session.positions[selectedPositionID]
    }

    var selectedTargets: [LeonardoSigningLocationTarget] {
        guard let document, let selectedPositionID else { return [] }
        return (try? session.targets(for: selectedPositionID, document: document)) ?? []
    }

    var untrustedPackageCredentials: [LeonardoSigningCredential] {
        trustedCredentials.filter { !locallyTrustedCredentialIDs.contains($0.id) }
    }

    /// Enrollment returns the authoritative credential identity. The list is
    /// only a refreshed presentation snapshot and may contain another key
    /// after it in lexical order.
    static func selectedCredentialID(
        afterEnrollment credential: LeonardoSigningCredential,
        availableIDs: [String]
    ) -> String? {
        availableIDs.contains(credential.id) ? credential.id : nil
    }

    var workflowAllowed: Bool {
        ready && trustAccepted && !hasInvalidSeal && verification.values.allSatisfy { $0 == .valid }
    }

    private var selectedProfile: LeonardoSignerProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    private var needsIdentity: Bool {
        creatingProfile || selectedProfile?.identity == nil
    }

    private var canAssign: Bool {
        guard let selectedPositionID,
              selectedProgress?.state == .pending,
              !selectedCredentialID.isEmpty else { return false }
        guard creatingProfile || selectedProfile != nil else { return false }
        if needsIdentity {
            return (!creatingProfile || !saveRubric || profileRubric != nil)
                && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !documentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedProfileID != nil
    }

    var body: some View {
        Group {
            if let document {
                signingContent(document: document)
            } else {
                ContentUnavailableView(
                    spanish ? "Copia no válida" : "Invalid copy",
                    systemImage: "exclamationmark.triangle",
                    description: Text(MobileSigningCopyError.invalidExchange.message)
                )
            }
        }
        .navigationTitle(spanish ? "Firma de copia" : "Sign copy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLocalSigningData()
            if initiallyShowingDocumentReader && document != nil {
                openDocumentReader()
            }
        }
        .onChange(of: selectedPositionID) { _, _ in
            guard selectedProgress?.assignment == nil else { return }
            creatingProfile = true
            selectedProfileID = nil
            selectedCredentialID = ""
            fullName = ""
            documentType = .nationalID
            documentNumber = ""
            saveIdentityDetails = false
            saveRubric = false
            profileRubric = nil
        }
        .alert(spanish ? "Firma guiada" : "Guided signing", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(spanish ? "Aceptar" : "OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert(
            spanish ? "Contenido de la copia" : "Signing copy contents",
            isPresented: $showingExportDisclosure
        ) {
            Button(spanish ? "Exportar" : "Export") {
                if let document { exportSigningCopy(document: document) }
            }
            Button(spanish ? "Cancelar" : "Cancel", role: .cancel) {}
        } message: {
            Text(exportDisclosureMessage)
        }
        .sheet(isPresented: $showingProfileRubric) {
            MobileGuidedRubricSheet(rubric: $profileRubricDraft, spanish: spanish, profileCapture: true) {
                profileRubric = profileRubricDraft
                showingProfileRubric = false
            }
        }
        .sheet(isPresented: $showingRubric) {
            MobileGuidedRubricSheet(rubric: $rubric, spanish: spanish) {
                showingRubric = false
                confirmSelectedTarget(reuse: .new, rubric: rubric)
            }
        }
        .fullScreenCover(isPresented: $showingDocumentReader) {
            if let document {
                NavigationStack {
                    MobileGuidedSigningDocumentReader(
                        document: document,
                        resources: resources,
                        session: session,
                        trustedCredentials: trustedCredentials.filter { locallyTrustedCredentialIDs.contains($0.id) },
                        trustAccepted: ready,
                        focusTarget: previewFocusTarget,
                        availableTargetKeys: $availableTargetKeys
                    ) {
                        previewFocusTarget = nil
                    }
                    .navigationTitle(spanish ? "Documento completo" : "Full document")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(spanish ? "Cerrar" : "Close") {
                                showingDocumentReader = false
                            }
                        }
                    }
                    .classicSurface()
                }
            }
        }
        .sheet(isPresented: $showingEnrollment) {
            MobileSigningCredentialEnrollment(spanish: spanish) { password in
                showingEnrollment = false
                Task { await enrollCredential(password: password) }
            }
        }
        .sheet(isPresented: $showingPassword) {
            MobileSigningPassword(spanish: spanish) { password in
                showingPassword = false
                Task { await signSelectedPosition(password: password) }
            }
        }
        .confirmationDialog(
            spanish ? "Confirmar reutilización" : "Confirm reuse",
            isPresented: Binding(
                get: { rubricReuseChoice != nil },
                set: { if !$0 { rubricReuseChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(spanish ? "Reutilizar y confirmar" : "Reuse and confirm") {
                guard let reuse = rubricReuseChoice,
                      let selectedPositionID,
                      let value = reuseRubric(for: reuse) else { return }
                rubricReuseChoice = nil
                confirmSelectedTarget(reuse: reuse, rubric: value, reuseConfirmed: true)
                _ = selectedPositionID
            }
            Button(spanish ? "Cancelar" : "Cancel", role: .cancel) { rubricReuseChoice = nil }
        } message: {
            Text(spanish
                 ? "La rúbrica se reutilizará solo en este puesto y esta aparición exacta."
                 : "The rubric is reused only for this position and exact occurrence.")
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Leonardo-signing-copy-\(session.id.uuidString)"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = String(describing: error)
            }
        }
    }

    @ViewBuilder
    private func signingContent(document: LeonardoDocument) -> some View {
        List {
            Section {
                Label(
                    spanish
                        ? "Esta copia se firma sin editar ni sincronizar el documento compartido."
                        : "This copy is signed without editing or synchronizing the shared document.",
                    systemImage: "lock.doc"
                )
                .font(.footnote)
                .foregroundStyle(MobileClassic.secondary)
                if ready && initialExchange.requiresLocalReview(comparedTo: session) {
                    Label(
                        spanish
                            ? "Revisa y confirma las ubicaciones pendientes en este dispositivo antes de firmar."
                            : "Review and confirm the remaining locations on this device before signing.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(MobileClassic.secondary)
                }
                if localLoadFailed {
                    Label(
                        spanish
                            ? "No se pudo comprobar el estado local de firma. Puedes leer la copia y volver a abrirla para intentarlo de nuevo."
                            : "Local signing status could not be checked. You can read the copy and reopen it to try again.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                if ready && (hasInvalidSeal || verification.values.contains(where: {
                    $0 == .invalidSignature || $0 == .modifiedSnapshot
                })) {
                    Label(
                        spanish ? "La copia contiene firmas no válidas o el documento ha cambiado." : "The copy contains invalid signatures or the document has changed.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                }
                if session.snapshot == nil {
                    let names = session.optionalBlankFieldIDs(document: document).map { fieldID in
                        document.metadata.fields[fieldID]?.label ?? fieldID
                    }
                    if !names.isEmpty {
                        Label(
                            spanish
                                ? "Estos campos opcionales quedarán vacíos: \(names.joined(separator: ", "))"
                                : "Optional fields will remain blank: \(names.joined(separator: ", "))",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(MobileClassic.secondary)
                    }
                }
                if !untrustedPackageCredentials.isEmpty && !trustAccepted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(spanish
                             ? "La copia incluye claves públicas para verificar firmas. Comprueba cada huella por otra vía antes de confiar en ella."
                             : "The copy includes public keys for signature verification. Check each fingerprint through a separate channel before trusting it.")
                            .font(.footnote)
                        ForEach(untrustedPackageCredentials) { credential in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(credential.id).font(.caption.weight(.semibold))
                                Text(publicFingerprint(credential))
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        Picker(spanish ? "Clave a comprobar" : "Key to check",
                               selection: $selectedTrustCredentialID) {
                            ForEach(untrustedPackageCredentials) { credential in
                                Text(credential.id).tag(Optional(credential.id))
                            }
                        }
                        TextField(spanish ? "Huella recibida por otra vía" : "Fingerprint received separately",
                                  text: $trustFingerprintInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button(spanish ? "Confirmar huella y confiar" : "Confirm fingerprint and trust") {
                            Task { await acceptSelectedPublicKey() }
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(MobileClassic.paper)
                        .disabled(selectedTrustCredentialID == nil || trustFingerprintInput.isEmpty || busy)
                    }
                } else if !trustedCredentials.isEmpty {
                    Label(spanish ? "Confianza pública aceptada" : "Public trust accepted", systemImage: "checkmark.seal")
                        .font(.footnote).foregroundStyle(.green)
                }
            }
            .listRowBackground(MobileClassic.inset)

            Section(spanish ? "Documento completo" : "Full document") {
                Button {
                    openDocumentReader()
                } label: {
                    Label(
                        spanish ? "Abrir copia completa" : "Open full signing copy",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(MobileClassic.paper)
                .accessibilityIdentifier("mobile-signing-open-document")
                Text(spanish
                     ? "La copia completa se abre en una página independiente para leerla sin editarla."
                     : "The full copy opens on a separate page so it can be read without editing.")
                    .font(.caption)
                    .foregroundStyle(MobileClassic.secondary)
            }
            .listRowBackground(MobileClassic.paper)

            Section(spanish ? "Puestos obligatorios" : "Required positions") {
                ForEach(session.declaration.positions) { position in
                    let progress = session.positions[position.id]
                    Button {
                        selectedPositionID = position.id
                        selectedTargetIndex = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(position.label).font(.headline)
                                Text(progress?.state == .signed ? verificationLabel(verification[position.id]) : positionState(progress?.state))
                                    .font(.caption).foregroundStyle(MobileClassic.secondary)
                            }
                            Spacer()
                            if progress?.state == .signed {
                                let verified = verification[position.id] == .valid
                                Image(systemName: verified ? "checkmark.seal.fill" : "exclamationmark.triangle")
                                    .foregroundStyle(verified ? .green : .orange)
                            } else if progress?.assignment != nil {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(MobileClassic.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mobile-signing-position-\(position.id)")
                }
            }
            .listRowBackground(MobileClassic.paper)

            if let position = selectedPosition, let progress = selectedProgress {
                assignmentSection(position: position, progress: progress)
                    .disabled(!workflowAllowed)
                    .listRowBackground(MobileClassic.inset)
                reviewSection(position: position, progress: progress, document: document)
                    .disabled(!workflowAllowed && progress.state != .signed)
                    .listRowBackground(MobileClassic.paper)
            }

            Section {
                Button(spanish ? "Exportar copia de firma" : "Export signed copy", systemImage: "square.and.arrow.up") {
                    showingExportDisclosure = true
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(MobileClassic.paper)
                .disabled(busy || !workflowAllowed)
                .accessibilityIdentifier("export-mobile-signing-copy")
                Text(spanish
                     ? "La exportación es un intercambio explícito; no actualiza el proyecto compartido."
                     : "Export is an explicit exchange; it never updates the shared project.")
                    .font(.caption).foregroundStyle(MobileClassic.secondary)
            }
            .listRowBackground(MobileClassic.inset)
        }
        .classicSurface()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(spanish ? "Cerrar" : "Close") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func assignmentSection(
        position: LeonardoSignerPosition,
        progress: LeonardoSigningPositionProgress
    ) -> some View {
        Section(spanish ? "Identidad y credencial · \(position.label)" : "Identity and credential · \(position.label)") {
            if let assignment = progress.assignment {
                Label(
                    "\(assignment.identity.fullName) · \(documentTypeLabel(assignment.identity.documentType)) · \(assignment.identity.redactedDocumentNumber)",
                    systemImage: "person.crop.circle"
                )
                Text(spanish ? "Identidad declarada; la credencial es un registro distinto." : "Declared identity; the credential is a separate record.")
                    .font(.caption).foregroundStyle(MobileClassic.secondary)
            } else {
                Picker(spanish ? "Perfil local" : "Local profile", selection: $creatingProfile) {
                    Text(spanish ? "Alta nueva" : "New signer").tag(true)
                    Text(spanish ? "Perfil guardado" : "Saved profile").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: creatingProfile) { _, creating in
                    if creating {
                        fullName = ""
                        documentNumber = ""
                        documentType = .nationalID
                        profileRubric = nil
                    } else {
                        loadProfile(selectedProfileID)
                    }
                }
                if !creatingProfile {
                    Picker(spanish ? "Perfil" : "Profile", selection: $selectedProfileID) {
                        Text(spanish ? "Selecciona un perfil" : "Select a profile").tag(UUID?.none)
                        ForEach(profiles) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }
                    .onChange(of: selectedProfileID) { _, value in loadProfile(value) }
                }
                if needsIdentity && (creatingProfile || selectedProfile != nil) {
                    TextField(spanish ? "Nombre completo" : "Full name", text: $fullName)
                    Picker(spanish ? "Tipo de documento" : "Document type", selection: $documentType) {
                        ForEach(LeonardoIdentityDocumentType.allCases, id: \.rawValue) { type in
                            Text(documentTypeLabel(type)).tag(type)
                        }
                    }
                    TextField(spanish ? "Número de documento" : "Document number", text: $documentNumber)
                }
                if creatingProfile {
                    Toggle(spanish ? "Guardar datos de identidad" : "Save identity details", isOn: $saveIdentityDetails)
                    Toggle(spanish ? "Guardar rúbrica del perfil" : "Save profile rubric", isOn: $saveRubric)
                    if saveRubric {
                        Button(spanish ? "Dibujar rúbrica del perfil" : "Draw profile rubric", systemImage: "signature") {
                            profileRubricDraft = profileRubric ?? LeonardoRubric()
                            showingProfileRubric = true
                        }
                        if let profileRubric {
                            MobileRubricPreview(rubric: profileRubric).frame(height: 100)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Picker(spanish ? "Credencial personal" : "Personal credential", selection: $selectedCredentialID) {
                        Text(spanish ? "Selecciona una credencial" : "Select a credential").tag("")
                        ForEach(credentialIDs, id: \.self) { id in
                            Text(String(id.suffix(12))).tag(id)
                        }
                    }
                    .accessibilityIdentifier("mobile-signing-credential-picker")
                    Button(spanish ? "Inscribir credencial personal" : "Enroll personal credential", systemImage: "plus.circle") {
                        showingEnrollment = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("mobile-signing-enroll-credential")
                }
                Button(spanish ? "Asignar y revisar" : "Assign and review", systemImage: "person.badge.plus") {
                    Task { await assignSelectedPosition(position.id) }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(MobileClassic.paper)
                .disabled(!canAssign || busy)
            }
        }
    }

    @ViewBuilder
    private func reviewSection(
        position: LeonardoSignerPosition,
        progress: LeonardoSigningPositionProgress,
        document: LeonardoDocument
    ) -> some View {
        Section(spanish ? "Revisión exacta · \(position.label)" : "Exact review · \(position.label)") {
            if progress.assignment == nil {
                Text(spanish ? "Asigna primero el perfil y la credencial personal." : "Assign the profile and personal credential first.")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
            } else if progress.state == .pending {
                Button(spanish ? "Iniciar revisión" : "Begin review", systemImage: "play.circle") {
                    Task { await beginReview(position.id, document: document) }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(MobileClassic.paper)
                .disabled(busy || !trustAccepted)
            } else if progress.state == .paused {
                Button(spanish ? "Reanudar revisión" : "Resume review", systemImage: "play.circle") {
                    Task { await resumeReview(position.id) }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(MobileClassic.paper)
                .disabled(busy)
            } else if progress.state == .signed {
                let verified = verification[position.id] == .valid
                Label(verificationLabel(verification[position.id]),
                      systemImage: verified ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(verified ? .green : .orange)
            } else {
                let targets = selectedTargets
                if targets.isEmpty {
                    Text(spanish ? "No hay apariciones renderizables; el flujo se detiene." : "No rendered occurrences are available; the workflow is blocked.")
                        .font(.footnote).foregroundStyle(.orange)
                } else {
                    ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                        let confirmed = progress.locations.contains {
                            $0.fieldID == target.fieldID && $0.occurrence == target.occurrence
                        }
                        let targetKey = MobileGuidedSigningTargetKey.make(
                            fieldID: target.fieldID, occurrence: target.occurrence
                        )
                        let targetAvailable = availableTargetKeys.contains(targetKey)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(index + 1). \(target.fieldID) · \(target.occurrence + 1)")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: confirmed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(confirmed ? .green : MobileClassic.secondary)
                            }
                            Text(context(for: target, in: document.body))
                                .font(.caption.monospaced())
                                .foregroundStyle(MobileClassic.secondary)
                                .textSelection(.enabled)
                            if !confirmed {
                                HStack {
                                    Button(spanish ? "Ver ubicación" : "View location", systemImage: "arrow.down.to.line") {
                                        selectedTargetIndex = index
                                        previewFocusTarget = target
                                        openDocumentReader()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(busy)
                                    Button(spanish ? "Leer y dibujar" : "Read and draw") {
                                        selectedTargetIndex = index
                                        previewFocusTarget = target
                                        rubric = LeonardoRubric()
                                        showingRubric = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .foregroundStyle(MobileClassic.paper)
                                    .disabled(!targetAvailable || busy)
                                    if session.rubricByPosition[position.id] != nil {
                                        Button(spanish ? "Reutilizar última" : "Reuse last") {
                                            selectedTargetIndex = index
                                            previewFocusTarget = target
                                            rubricReuseChoice = .session
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!targetAvailable || busy)
                                    }
                                    if progress.assignment?.profileRubric != nil {
                                        Button(spanish ? "Reutilizar perfil" : "Reuse profile") {
                                            selectedTargetIndex = index
                                            previewFocusTarget = target
                                            rubricReuseChoice = .profile
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!targetAvailable || busy)
                                    }
                                }
                                if !targetAvailable {
                                    Text(spanish
                                         ? "La aparición aún no está disponible en el lector; no se puede confirmar."
                                         : "This occurrence is not available in the reader yet; it cannot be confirmed.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                        .accessibilityIdentifier("mobile-signing-target-\(target.fieldID)-\(target.occurrence)")
                    }
                    HStack {
                        Button(spanish ? "Pausar" : "Pause", systemImage: "pause.circle") {
                            Task { await pauseReview(position.id) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                        Spacer()
                        Button(spanish ? "Firmar" : "Sign", systemImage: "signature") {
                            showingPassword = true
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(MobileClassic.paper)
                        .disabled(progress.state != .readyToSign || busy || !trustAccepted)
                    }
                }
            }
        }
    }

    private func verificationLabel(_ result: LeonardoSignatureVerification?) -> String {
        switch result {
        case .valid: return spanish ? "Firma verificada" : "Signature verified"
        case .invalidSignature, .modifiedSnapshot:
            return spanish ? "Firma no válida" : "Invalid signature"
        case .unknownCredential, nil:
            return spanish ? "Firma pendiente de verificar" : "Signature awaiting verification"
        }
    }

    private var exportDisclosureMessage: String {
        let assignments: [String] = session.declaration.positions.compactMap { position in
            guard let assignment = session.positions[position.id]?.assignment else { return nil }
            let rubric = assignment.profileRubric == nil
                ? (spanish ? "sin rúbrica de perfil" : "no profile rubric")
                : (spanish ? "rúbrica de perfil" : "profile rubric")
            return "• \(position.label): \(assignment.identity.fullName) · \(documentTypeLabel(assignment.identity.documentType)) · \(assignment.identity.redactedDocumentNumber) · \(rubric)"
        }
        let details = assignments.isEmpty ? "• No assigned signer yet." : assignments.joined(separator: "\n")
        if spanish {
            let translated = assignments.isEmpty ? "• Todavía no hay puestos asignados." : assignments.joined(separator: "\n")
            return "Se exportarán solo esta fuente, sus recursos, el progreso y los puestos asignados (incluidos nombre, tipo y número de documento declarado, y las rúbricas presentes):\n\(translated)\n\nNo se incluyen claves privadas, rutas locales ni perfiles no asignados. La identidad permanece declarada."
        }
        return "Only this source, its resources, progress and assigned positions will be exported (including declared name, document type and number, and present rubrics):\n\(details)\n\nPrivate keys, local paths and unassigned profiles are not included. Identity remains declared."
    }

    func publicFingerprint(_ credential: LeonardoSigningCredential) -> String {
        SHA256.hash(data: credential.publicKey).map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }

    private func context(for target: LeonardoSigningLocationTarget, in body: String) -> String {
        target.reviewedContext(in: body)?.replacingOccurrences(of: "\n", with: " ↵ ") ?? ""
    }

    private func positionState(_ state: LeonardoSigningPositionState?) -> String {
        switch state {
        case .pending: return spanish ? "Pendiente" : "Pending"
        case .reviewing: return spanish ? "En revisión" : "Reviewing"
        case .paused: return spanish ? "Pausada" : "Paused"
        case .readyToSign: return spanish ? "Lista para firmar" : "Ready to sign"
        case .signed: return spanish ? "Firmada" : "Signed"
        case nil: return spanish ? "No disponible" : "Unavailable"
        }
    }

    private func documentTypeLabel(_ type: LeonardoIdentityDocumentType) -> String {
        switch type {
        case .nationalID: return spanish ? "DNI" : "National ID"
        case .passport: return spanish ? "Pasaporte" : "Passport"
        case .driverLicense: return spanish ? "Permiso de conducir" : "Driver license"
        case .other: return spanish ? "Otro documento" : "Other document"
        }
    }
}
