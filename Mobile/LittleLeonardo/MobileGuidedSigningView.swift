import CryptoKit
import SwiftUI
import LeonardoCore

/// Offline signing of an explicitly selected copy. The shared project is only
/// read; the result leaves the phone as a user-exported exchange file.
struct MobileGuidedSigningView: View {
    let library: MobileLibrary
    private let initialExchange: LeonardoSigningExchange
    @Environment(\.dismiss) private var dismiss
    @State private var document: LeonardoDocument?
    @State private var session: LeonardoGuidedSigningSession
    @State private var resources: [LeonardoSigningResource]
    @State private var trustedCredentials: [LeonardoSigningCredential]
    @State private var trustAccepted: Bool
    @State private var locallyTrustedCredentialIDs: Set<String> = []
    @State private var selectedTrustCredentialID: String?
    @State private var trustFingerprintInput = ""
    @State private var profiles: [LeonardoSignerProfile] = []
    @State private var credentialIDs: [String] = []
    @State private var selectedPositionID: String?
    @State private var selectedProfileID: UUID?
    @State private var selectedCredentialID = ""
    @State private var creatingProfile = true
    @State private var fullName = ""
    @State private var documentType = LeonardoIdentityDocumentType.nationalID
    @State private var documentNumber = ""
    // Saving the declared identity is a separate, opt-in consent. The
    // assignment still carries the entered details for its proof, but a new
    // local profile must not retain them by default.
    @State private var saveIdentityDetails = false
    @State private var saveRubric = false
    @State private var profileRubric: LeonardoRubric?
    @State private var selectedTargetIndex: Int?
    @State private var rubric = LeonardoRubric()
    @State private var rubricReuseChoice: LeonardoRubricReuse?
    @State private var showingRubric = false
    @State private var showingEnrollment = false
    @State private var showingPassword = false
    @State private var showingExportDisclosure = false
    @State private var exporting = false
    @State private var exportDocument: MobileSigningExchangeDocument?
    @State private var busy = false
    @State private var errorMessage: String?

    init(library: MobileLibrary, exchange: LeonardoSigningExchange) {
        self.library = library
        self.initialExchange = exchange
        _document = State(initialValue: try? exchange.document())
        _session = State(initialValue: exchange.session)
        _resources = State(initialValue: (try? exchange.signingResources()) ?? [])
        _trustedCredentials = State(initialValue: exchange.trustedCredentials)
        _trustAccepted = State(initialValue: exchange.trustedCredentials.isEmpty)
    }

    private var spanish: Bool {
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

    private var selectedTargets: [LeonardoSigningLocationTarget] {
        guard let document, let selectedPositionID else { return [] }
        return (try? session.targets(for: selectedPositionID, document: document)) ?? []
    }

    private var untrustedPackageCredentials: [LeonardoSigningCredential] {
        trustedCredentials.filter { !locallyTrustedCredentialIDs.contains($0.id) }
    }

    private var canAssign: Bool {
        guard let selectedPositionID,
              selectedProgress?.state == .pending,
              !selectedCredentialID.isEmpty else { return false }
        if creatingProfile {
            return !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    "Copia no válida / Invalid copy",
                    systemImage: "exclamationmark.triangle",
                    description: Text(MobileSigningCopyError.invalidExchange.message)
                )
            }
        }
        .navigationTitle("Firma de copia / Sign copy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLocalSigningData() }
        .alert("Firma guiada / Guided signing", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar / OK") { errorMessage = nil }
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
        .sheet(isPresented: $showingRubric) {
            MobileGuidedRubricSheet(rubric: $rubric, spanish: spanish) {
                showingRubric = false
                confirmSelectedTarget(reuse: .new, rubric: rubric)
            }
        }
        .sheet(isPresented: $showingEnrollment) {
            MobileSigningCredentialEnrollment { password in
                showingEnrollment = false
                Task { await enrollCredential(password: password) }
            }
        }
        .sheet(isPresented: $showingPassword) {
            MobileSigningPassword { password in
                showingPassword = false
                Task { await signSelectedPosition(password: password) }
            }
        }
        .confirmationDialog(
            "Confirmar reutilización / Confirm reuse",
            isPresented: Binding(
                get: { rubricReuseChoice != nil },
                set: { if !$0 { rubricReuseChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reutilizar y confirmar / Reuse and confirm") {
                guard let reuse = rubricReuseChoice,
                      let selectedPositionID,
                      let value = reuseRubric(for: reuse) else { return }
                rubricReuseChoice = nil
                confirmSelectedTarget(reuse: reuse, rubric: value, reuseConfirmed: true)
                _ = selectedPositionID
            }
            Button("Cancelar / Cancel", role: .cancel) { rubricReuseChoice = nil }
        } message: {
            Text("La rúbrica se reutilizará solo en este puesto y esta aparición exacta. / The rubric is reused only for this position and exact occurrence.")
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
                        .buttonStyle(.bordered)
                        .disabled(selectedTrustCredentialID == nil || trustFingerprintInput.isEmpty || busy)
                    }
                } else if !trustedCredentials.isEmpty {
                    Label(spanish ? "Confianza pública aceptada" : "Public trust accepted", systemImage: "checkmark.seal")
                        .font(.footnote).foregroundStyle(.green)
                }
            }
            .listRowBackground(MobileClassic.inset)

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
                                Text(positionState(progress?.state))
                                    .font(.caption).foregroundStyle(MobileClassic.secondary)
                            }
                            Spacer()
                            if progress?.state == .signed {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
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
                    .listRowBackground(MobileClassic.inset)
                reviewSection(position: position, progress: progress, document: document)
                    .listRowBackground(MobileClassic.paper)
            }

            Section {
                Button(spanish ? "Exportar copia de firma" : "Export signed copy", systemImage: "square.and.arrow.up") {
                    showingExportDisclosure = true
                }
                .disabled(busy)
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
                    "\(assignment.identity.fullName) · \(assignment.identity.documentType.rawValue) · \(assignment.identity.redactedDocumentNumber)",
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
                if creatingProfile {
                    TextField(spanish ? "Nombre completo" : "Full name", text: $fullName)
                    Picker(spanish ? "Tipo de documento" : "Document type", selection: $documentType) {
                        ForEach(LeonardoIdentityDocumentType.allCases, id: \.rawValue) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    TextField(spanish ? "Número de documento" : "Document number", text: $documentNumber)
                    Toggle(spanish ? "Guardar datos de identidad" : "Save identity details", isOn: $saveIdentityDetails)
                    Toggle(spanish ? "Guardar rúbrica del perfil" : "Save profile rubric", isOn: $saveRubric)
                    if let profileRubric {
                        MobileRubricPreview(rubric: profileRubric)
                            .frame(height: 100)
                    }
                } else {
                    Picker(spanish ? "Perfil" : "Profile", selection: $selectedProfileID) {
                        Text(spanish ? "Selecciona un perfil" : "Select a profile").tag(UUID?.none)
                        ForEach(profiles) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }
                    .onChange(of: selectedProfileID) { _, value in loadProfile(value) }
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
                .disabled(busy || !trustAccepted)
            } else if progress.state == .paused {
                Button(spanish ? "Reanudar revisión" : "Resume review", systemImage: "play.circle") {
                    Task { await resumeReview(position.id) }
                }
                .disabled(busy)
            } else if progress.state == .signed {
                Label(spanish ? "Puesto firmado y verificado localmente." : "Position signed and verified locally.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
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
                                    Button(spanish ? "Leer y dibujar" : "Read and draw") {
                                        selectedTargetIndex = index
                                        rubric = LeonardoRubric()
                                        showingRubric = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    if session.rubricByPosition[position.id] != nil {
                                        Button(spanish ? "Reutilizar última" : "Reuse last") {
                                            selectedTargetIndex = index
                                            rubricReuseChoice = .session
                                        }
                                    }
                                    if progress.assignment?.profileRubric != nil {
                                        Button(spanish ? "Reutilizar perfil" : "Reuse profile") {
                                            selectedTargetIndex = index
                                            rubricReuseChoice = .profile
                                        }
                                    }
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
                        .disabled(busy)
                        Spacer()
                        Button(spanish ? "Firmar" : "Sign", systemImage: "signature") {
                            showingPassword = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(progress.state != .readyToSign || busy || !trustAccepted)
                    }
                }
            }
        }
    }

    private func loadLocalSigningData() async {
        do {
            profiles = try await library.signingStore.profiles()
            credentialIDs = try await library.signingCredentialStore.credentialIDs()
            let localTrust = try await library.signingCredentialStore.trustStore()
            locallyTrustedCredentialIDs = Set(trustedCredentials.compactMap { packageCredential in
                localTrust.credential(id: packageCredential.id) == packageCredential ? packageCredential.id : nil
            })
            selectedTrustCredentialID = untrustedPackageCredentials.first?.id
            trustAccepted = untrustedPackageCredentials.isEmpty
        } catch {
            errorMessage = String(describing: error)
        }
        if selectedPositionID == nil {
            selectedPositionID = session.pendingPositionIDs.first ?? session.declaration.positions.first?.id
        }
    }

    private func loadProfile(_ id: UUID?) {
        guard let id, let profile = profiles.first(where: { $0.id == id }) else { return }
        fullName = profile.identity?.fullName ?? profile.displayName
        documentType = profile.identity?.documentType ?? .nationalID
        documentNumber = profile.identity?.documentNumber ?? ""
        profileRubric = profile.rubric
    }

    private func assignSelectedPosition(_ positionID: String) async {
        busy = true
        defer { busy = false }
        do {
            let profile: LeonardoSignerProfile
            if creatingProfile {
                profile = LeonardoSignerProfile(
                    displayName: fullName,
                    identity: LeonardoDeclaredIdentity(
                        fullName: fullName, documentType: documentType, documentNumber: documentNumber
                    ),
                    rubric: profileRubric
                )
                if saveIdentityDetails || saveRubric {
                    try await library.signingStore.saveProfile(
                        profile,
                        options: .init(saveIdentityDetails: saveIdentityDetails, saveRubric: saveRubric)
                    )
                    profiles = try await library.signingStore.profiles()
                }
            } else {
                guard let selectedProfileID,
                      let existing = profiles.first(where: { $0.id == selectedProfileID }) else {
                    throw LeonardoSigningError.invalidProfile
                }
                profile = existing
            }
            let localTrust = try await library.signingCredentialStore.trustStore(
                credentialIDs: [selectedCredentialID]
            )
            guard let credential = localTrust.credential(id: selectedCredentialID) else {
                throw LeonardoSigningError.unknownCredential(selectedCredentialID)
            }
            let authorization = try LeonardoSigningAuthorization(
                positionID: positionID, profileID: profile.id, credentialID: credential.id,
                confirmedAt: Date(), explicitlyConfirmed: true
            )
            var updated = session
            try updated.assign(positionID: positionID, profile: profile, credential: credential,
                               authorization: authorization, at: Date())
            try await library.signingStore.saveSession(updated)
            // Publish state only after the actor has accepted the CAS write.
            session = updated
            if !trustedCredentials.contains(where: { $0.id == credential.id }) {
                trustedCredentials.append(credential)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func beginReview(_ positionID: String, document: LeonardoDocument) async {
        busy = true
        defer { busy = false }
        do {
            var updated = session
            _ = try updated.begin(positionID: positionID, document: document, resources: resources)
            try await library.signingStore.saveSession(updated)
            session = updated
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func pauseReview(_ positionID: String) async {
        busy = true
        defer { busy = false }
        do {
            var updated = session
            try updated.pause(positionID: positionID, at: Date())
            try await library.signingStore.saveSession(updated)
            session = updated
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func resumeReview(_ positionID: String) async {
        busy = true
        defer { busy = false }
        do {
            var updated = session
            try updated.resume(positionID: positionID, at: Date())
            try await library.signingStore.saveSession(updated)
            session = updated
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func confirmSelectedTarget(
        reuse: LeonardoRubricReuse,
        rubric: LeonardoRubric,
        reuseConfirmed: Bool = false
    ) {
        guard let document, let selectedPositionID,
              let selectedTargetIndex,
              selectedTargets.indices.contains(selectedTargetIndex) else { return }
        let target = selectedTargets[selectedTargetIndex]
        do {
            var updated = session
            try updated.confirmLocation(
                positionID: selectedPositionID, fieldID: target.fieldID, occurrence: target.occurrence,
                document: document, resources: resources, contextRead: true, rubric: rubric,
                reuse: reuse, profileRubric: updated.positions[selectedPositionID]?.assignment?.profileRubric,
                reuseConfirmed: reuseConfirmed, at: Date()
            )
            busy = true
            Task {
                do {
                    try await library.signingStore.saveSession(updated)
                    session = updated
                    busy = false
                }
                catch {
                    errorMessage = String(describing: error)
                    busy = false
                }
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reuseRubric(for reuse: LeonardoRubricReuse) -> LeonardoRubric? {
        guard let selectedPositionID else { return nil }
        switch reuse {
        case .session: return session.rubricByPosition[selectedPositionID]
        case .profile: return session.positions[selectedPositionID]?.assignment?.profileRubric
        case .new: return nil
        }
    }

    private func signSelectedPosition(password: String) async {
        guard let document, let selectedPositionID else { return }
        busy = true
        defer { busy = false }
        do {
            let assignment = try requireAssignment(positionID: selectedPositionID)
            let key = try await library.signingCredentialStore.keyPair(
                credentialID: assignment.credentialID, password: password
            )
            let trust = try LeonardoSigningTrustRegistry(credentials: trustedCredentials)
            var updated = session
            _ = try updated.sign(positionID: selectedPositionID, keyPair: key, document: document,
                                  resources: resources, trustStore: trust, at: Date())
            try await library.signingStore.saveSession(updated)
            session = updated
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func requireAssignment(positionID: String) throws -> LeonardoSigningAssignment {
        guard let assignment = session.positions[positionID]?.assignment else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        return assignment
    }

    private func enrollCredential(password: String) async {
        do {
            _ = try await library.signingCredentialStore.enroll(password: password)
            credentialIDs = try await library.signingCredentialStore.credentialIDs()
            selectedCredentialID = credentialIDs.last ?? ""
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func acceptSelectedPublicKey() async {
        guard let credentialID = selectedTrustCredentialID,
              let credential = trustedCredentials.first(where: { $0.id == credentialID }) else { return }
        let normalizedInput = trustFingerprintInput
            .filter { $0.isHexDigit }
            .lowercased()
        guard normalizedInput == publicFingerprint(credential).filter({ $0.isHexDigit }).lowercased() else {
            errorMessage = spanish
                ? "La huella no coincide. Compruébala por la vía independiente indicada."
                : "The fingerprint does not match. Check it through the separate channel."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await library.signingCredentialStore.trustPublicCredential(credential)
            locallyTrustedCredentialIDs.insert(credential.id)
            trustFingerprintInput = ""
            selectedTrustCredentialID = untrustedPackageCredentials.first?.id
            trustAccepted = untrustedPackageCredentials.isEmpty
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func exportSigningCopy(document: LeonardoDocument) {
        do {
            let exchange = try LeonardoSigningExchange(
                document: document, resources: resources, session: session,
                trustedCredentials: trustedCredentials, at: Date()
            )
            exportDocument = MobileSigningExchangeDocument(exchange: exchange)
            exporting = true
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private var exportDisclosureMessage: String {
        let assignments: [String] = session.declaration.positions.compactMap { position in
            guard let assignment = session.positions[position.id]?.assignment else { return nil }
            let rubric = assignment.profileRubric == nil ? "no profile rubric" : "profile rubric"
            return "• \(position.label): \(assignment.identity.fullName) · \(assignment.identity.documentType.rawValue) · \(assignment.identity.redactedDocumentNumber) · \(rubric)"
        }
        let details = assignments.isEmpty ? "• No assigned signer yet." : assignments.joined(separator: "\n")
        if spanish {
            let translated = assignments.isEmpty ? "• Todavía no hay puestos asignados." : assignments.joined(separator: "\n")
            return "Se exportarán solo esta fuente, sus recursos, el progreso y los puestos asignados (incluidos nombre, tipo y número de documento declarado, y las rúbricas presentes):\n\(translated)\n\nNo se incluyen claves privadas, rutas locales ni perfiles no asignados. La identidad permanece declarada."
        }
        return "Only this source, its resources, progress and assigned positions will be exported (including declared name, document type and number, and present rubrics):\n\(details)\n\nPrivate keys, local paths and unassigned profiles are not included. Identity remains declared."
    }

    private func publicFingerprint(_ credential: LeonardoSigningCredential) -> String {
        SHA256.hash(data: credential.publicKey).map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }

    private func context(for target: LeonardoSigningLocationTarget, in body: String) -> String {
        guard target.sourceOffset >= 0,
              let start = body.index(body.startIndex, offsetBy: target.sourceOffset, limitedBy: body.endIndex) else {
            return body.prefix(160).description
        }
        let lower = body.index(start, offsetBy: -120, limitedBy: body.startIndex) ?? body.startIndex
        let upper = body.index(start, offsetBy: 180, limitedBy: body.endIndex) ?? body.endIndex
        return String(body[lower..<upper]).replacingOccurrences(of: "\n", with: " ↵ ")
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
}

private struct MobileGuidedRubricSheet: View {
    @Binding var rubric: LeonardoRubric
    let spanish: Bool
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var color = "#111111"
    @State private var width = 4.0
    @State private var style = LeonardoInkStyle.solid
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(spanish ? "Lee el contexto y dibuja una rúbrica nueva." : "Read the context and draw a new rubric.")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
                MobileRubricInkTools(color: $color, width: $width, style: $style, enabled: true)
                MobileRubricCanvas(rubric: $rubric, color: color, width: width, style: style,
                                   isInteractive: true, limitReached: $limitReached)
                    .aspectRatio(3, contentMode: .fit)
                    .background(MobileClassic.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if limitReached {
                    Text("La rúbrica supera el límite portable. / Rubric exceeds the portable limit.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button(spanish ? "Confirmar aparición" : "Confirm occurrence", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(!rubric.isValid || limitReached)
            }
            .padding()
            .classicSurface()
            .navigationTitle(spanish ? "Rúbrica" : "Rubric")
            .toolbar { Button(spanish ? "Cancelar" : "Cancel") { dismiss() } }
        }
    }
}

private struct MobileSigningCredentialEnrollment: View {
    let onEnroll: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("La contraseña personal cifra la clave privada antes de guardarla en el llavero. / The personal password encrypts the private key before it is stored in the keychain.")
                        .font(.footnote)
                    SecureField("Contraseña / Password", text: $password)
                    SecureField("Confirmar / Confirm", text: $confirmation)
                }
                Button("Inscribir / Enroll") { onEnroll(password) }
                    .disabled(password.count < 8 || password != confirmation)
            }
            .navigationTitle("Credencial / Credential")
            .toolbar { Button("Cerrar / Close") { dismiss() } }
        }
    }
}

private struct MobileSigningPassword: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Contraseña personal / Personal password", text: $password)
                Button("Firmar / Sign") { onSubmit(password) }
                    .disabled(password.isEmpty)
            }
            .navigationTitle("Autorizar firma / Authorize signature")
            .toolbar { Button("Cancelar / Cancel") { dismiss() } }
        }
    }
}
