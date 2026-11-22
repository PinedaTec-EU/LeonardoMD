import SwiftUI
import AppKit
import LeonardoCore
import LeonardoSync

/// Native macOS coordinator for an MDLF v2 signing plan. It deliberately
/// keeps the form preview as the reading surface and puts assignment,
/// occurrence review and signing controls in the inspector.
struct GuidedSigningView: View {
    @Bindable var session: AppSession

    @State private var selectedPositionID: String? = nil
    @State private var selectedTargetIndex = 0
    @State private var selectedProfileID: UUID? = nil
    @State private var transientProfileID: UUID? = nil
    @State private var creatingProfile = false
    @State private var fullName = ""
    @State private var documentType = LeonardoIdentityDocumentType.nationalID
    @State private var documentNumber = ""
    @State private var saveIdentityDetails = false
    @State private var saveRubric = false
    @State private var draftProfileRubric: LeonardoRubric? = nil
    @State private var locationRubric: LeonardoRubric? = nil
    @State private var reuse = LeonardoRubricReuse.new
    @State private var reuseConfirmed = false
    @State private var contextRead = false
    @State private var showAssignmentConfirmation = false
    @State private var showCredentialEnrollment = false
    @State private var showPassword = false
    @State private var showRubricEditor = false
    @State private var rubricEditorPurpose: RubricEditorPurpose = .location
    @State private var selectedCredentialID = ""
    @State private var selectedPassword = ""
    @State private var renderedTargetKeys = Set<String>()
    @State private var targetAvailabilityChecked = false

    private enum RubricEditorPurpose { case profile, location }

    private var positions: [LeonardoSignerPosition] {
        session.guidedSigningSession?.declaration.positions ?? []
    }

    private var selectedPosition: LeonardoSignerPosition? {
        positions.first { $0.id == (selectedPositionID ?? positions.first?.id) }
    }

    private var selectedProgress: LeonardoSigningPositionProgress? {
        guard let id = selectedPosition?.id else { return nil }
        return session.guidedSigningSession?.positions[id]
    }

    private var optionalBlankFieldNames: [String] {
        guard let document = session.leonardoDocument,
              let signingSession = session.guidedSigningSession,
              signingSession.snapshot == nil else { return [] }
        return signingSession.optionalBlankFieldIDs(document: document).map { fieldID in
            session.leonardoFieldDefinition(fieldID)?.label ?? fieldID
        }
    }

    private var selectedProfile: LeonardoSignerProfile? {
        guard !creatingProfile, let selectedProfileID else { return nil }
        return session.guidedSigningProfiles.first { $0.id == selectedProfileID }
    }

    private var selectedProfileNeedsIdentity: Bool {
        selectedProfile?.identity == nil
    }

    private var needsDeclaredIdentityInput: Bool {
        creatingProfile || selectedProfileNeedsIdentity
    }

    private var profileForAssignment: LeonardoSignerProfile? {
        if let selectedProfile {
            if selectedProfile.identity == nil {
                let displayName = fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? selectedProfile.displayName : fullName
                let declaredIdentity = LeonardoDeclaredIdentity(
                    fullName: displayName,
                    documentType: documentType,
                    documentNumber: documentNumber
                )
                guard declaredIdentity.isValid else { return nil }
                return GuidedSigningTransientProfile.make(
                    savedProfile: selectedProfile,
                    identity: declaredIdentity
                )
            }
            return selectedProfile
        }
        guard creatingProfile else { return nil }
        let identity = LeonardoDeclaredIdentity(fullName: fullName, documentType: documentType,
                                                documentNumber: documentNumber)
        return LeonardoSignerProfile(id: transientProfileID ?? UUID(), displayName: fullName, identity: identity,
                                     rubric: draftProfileRubric)
    }

    private var selectedCredential: LeonardoSigningCredential? {
        session.guidedSigningTrustStore?.credential(id: selectedCredentialID)
    }

    private var assignmentCanBeSubmitted: Bool {
        guard selectedPosition != nil, profileForAssignment?.isValid == true,
              profileForAssignment?.identity?.isValid == true,
              let credential = selectedCredential, credential.isValid else { return false }
        return true
    }

    private var completedPositionCount: Int {
        positions.reduce(into: 0) { count, position in
            if session.guidedSigningSession?.positions[position.id]?.state == .signed { count += 1 }
        }
    }

    private var allPositionsComplete: Bool {
        !positions.isEmpty && completedPositionCount == positions.count
    }

    private var currentTarget: LeonardoSigningLocationTarget? {
        guard session.guidedSigningTargets.indices.contains(selectedTargetIndex) else { return nil }
        return session.guidedSigningTargets[selectedTargetIndex]
    }

    private var nextTargetIndex: Int? {
        guard let progress = selectedProgress else { return nil }
        return session.guidedSigningTargets.firstIndex { target in
            !progress.locations.contains {
                $0.positionID == target.positionID
                    && $0.fieldID == target.fieldID
                    && $0.occurrence == target.occurrence
            }
        }
    }

    private var rubricForCurrentChoice: LeonardoRubric? {
        guard let positionID = selectedPosition?.id else { return nil }
        switch reuse {
        case .new: return locationRubric
        case .session: return session.guidedSigningSession?.rubricByPosition[positionID]
        case .profile: return selectedProgress?.assignment?.profileRubric
        }
    }

    var body: some View {
        signingContent
        .padding(18)
        .frame(width: 370)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityIdentifier("guided-signing-inspector")
        .task {
            if selectedPositionID == nil { selectedPositionID = positions.first?.id }
            if selectedCredentialID.isEmpty { selectedCredentialID = session.guidedSigningCredentialIDs.first ?? "" }
            profileOptionsChanged()
            await refreshRenderedTargets()
        }
        .onChange(of: session.guidedSigningCredentialIDs) { _, values in credentialIDsChanged(values) }
        .onChange(of: session.guidedSigningProfiles) { _, _ in profileOptionsChanged() }
        .onChange(of: selectedProfileID) { _, _ in selectedProfileChanged() }
        .onChange(of: selectedPositionID) { _, _ in selectedPositionChanged() }
        .onChange(of: selectedTargetIndex) { _, _ in selectedTargetChanged() }
        .onChange(of: session.guidedSigningTargets) { _, _ in refreshTargetsSoon() }
        .onChange(of: session.renderer.isReady) { _, ready in rendererReadyChanged(ready) }
        .confirmationDialog(
            L10n.text("Authorize this signer and credential for this position?"),
            isPresented: $showAssignmentConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Authorize and assign")) { assignSigner() }
            Button(L10n.text("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("The profile and personal credential are distinct records. This approval does not claim independent identity verification."))
        }
        .sheet(isPresented: $showCredentialEnrollment) {
            GuidedSigningCredentialEnrollment { password in
                Task {
                    do {
                        let credential = try await session.guidedSigningCredentialStore.enroll(password: password)
                        let trustStore = try? await session.guidedSigningCredentialStore.trustStore()
                        selectedCredentialID = credential.id
                        showCredentialEnrollment = false
                        session.guidedSigningCredentialIDs = (try? await session.guidedSigningCredentialStore.credentialIDs()) ?? []
                        session.guidedSigningTrustStore = trustStore
                    } catch {
                        session.guidedSigningError = String(describing: error)
                    }
                }
            }
        }
        .sheet(isPresented: $showPassword) {
            GuidedSigningPassword { password in
                showPassword = false
                guard let positionID = selectedPosition?.id else { return }
                Task { await session.signGuidedPosition(positionID: positionID, password: password) }
            }
        }
        .sheet(isPresented: $showRubricEditor) {
            GuidedSigningRubricCapture(
                title: rubricEditorPurpose == .profile
                    ? L10n.text("Profile rubric")
                    : L10n.text("Location rubric"),
                initialRubric: rubricEditorPurpose == .profile ? draftProfileRubric : locationRubric
            ) { rubric in
                switch rubricEditorPurpose {
                case .profile: draftProfileRubric = rubric
                case .location: locationRubric = rubric
                }
            }
        }
    }

    @ViewBuilder
    private var signingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                if session.guidedSigningLoading {
                    ProgressView(L10n.text("Preparing the protected signing workflow…"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = session.guidedSigningError {
                    integrityWarning(error)
                } else if let selectedPosition {
                    positionPicker
                    assignmentSection(selectedPosition)
                    reviewSection(selectedPosition)
                } else {
                    Text(L10n.text("No signer positions are available.")).foregroundStyle(.secondary)
                }
                if let problem = session.guidedSigningActionProblem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let status = session.guidedSigningStatus {
                    Label(status, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func credentialIDsChanged(_ values: [String]) {
        if !values.contains(selectedCredentialID) { selectedCredentialID = values.first ?? "" }
    }

    private func profileOptionsChanged() {
        guard selectedProgress?.assignment == nil else { return }
        if creatingProfile {
            if transientProfileID == nil { transientProfileID = UUID() }
            return
        }
        if session.guidedSigningProfiles.isEmpty {
            selectedProfileID = nil
            creatingProfile = true
            transientProfileID = UUID()
        } else if let selectedProfileID,
                  let profile = session.guidedSigningProfiles.first(where: { $0.id == selectedProfileID }) {
            transientProfileID = profile.identity == nil ? (transientProfileID ?? UUID()) : nil
        } else {
            selectedProfileID = session.guidedSigningProfiles.first?.id
            if let profile = session.guidedSigningProfiles.first {
                transientProfileID = profile.identity == nil ? UUID() : nil
            }
        }
    }

    private func selectedProfileChanged() {
        guard !creatingProfile else {
            if transientProfileID == nil { transientProfileID = UUID() }
            return
        }
        guard let profile = selectedProfile else {
            transientProfileID = nil
            return
        }
        transientProfileID = nil
        if profile.identity == nil {
            fullName = profile.displayName
            documentType = .nationalID
            documentNumber = ""
            saveIdentityDetails = false
        }
    }

    private func selectedPositionChanged() {
        session.guidedSigningActionProblem = nil
        if selectedProgress?.assignment == nil {
            creatingProfile = true
            selectedProfileID = nil
            transientProfileID = UUID()
            fullName = ""
            documentType = .nationalID
            documentNumber = ""
            saveIdentityDetails = false
            saveRubric = false
            draftProfileRubric = nil
        }
        selectedTargetIndex = 0
        contextRead = false
        reuseConfirmed = false
        locationRubric = nil
        renderedTargetKeys = []
        targetAvailabilityChecked = false
        session.guidedSigningTargets = []
        if let progress = selectedProgress,
           (progress.state == .reviewing || progress.state == .readyToSign) {
            session.refreshGuidedSigningTargets(for: selectedPosition?.id)
        }
    }

    private func selectedTargetChanged() {
        contextRead = false
        reuseConfirmed = false
        checkCurrentTarget()
    }

    private func rendererReadyChanged(_ ready: Bool) {
        guard ready else { return }
        refreshTargetsSoon()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(L10n.text("Guided signing"), systemImage: "signature")
                    .font(.headline)
                Spacer(minLength: 6)
                Label(
                    L10n.format("%d of %d positions complete", completedPositionCount, positions.count),
                    systemImage: allPositionsComplete ? "checkmark.circle.fill" : "person.2"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(allPositionsComplete ? .green : .secondary)
                .accessibilityLabel(L10n.format("%d of %d positions complete", completedPositionCount, positions.count))
            }
            HStack(spacing: 8) {
                Menu {
                    Button(L10n.text("Export signing copy"), systemImage: "square.and.arrow.up") {
                        Task { await session.exportGuidedSigningExchange() }
                    }
                    Button(L10n.text("Import signed copy"), systemImage: "square.and.arrow.down") {
                        session.importGuidedSigningExchange()
                    }
                } label: {
                    Label(L10n.text("Exchange"), systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(PremiumButtonStyle(compact: true))
                .disabled(!session.guidedSigningReady || session.guidedSigningError != nil)
                Spacer(minLength: 0)
            }
            Text(L10n.text("The first confirmed location seals form data, assignments and referenced resources."))
                .font(.caption).foregroundStyle(.secondary)
            if !optionalBlankFieldNames.isEmpty {
                Label(
                    L10n.format("Optional fields will remain blank: %@", optionalBlankFieldNames.joined(separator: ", ")),
                    systemImage: "info.circle"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(positions) { position in
                let fields = assignedFieldLabels(for: position.id)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: statusIcon(for: position.id)).foregroundStyle(statusColor(for: position.id))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.label).font(.subheadline.weight(.semibold))
                        Text(fields.isEmpty ? L10n.text("No rubric field assigned") : fields.joined(separator: ", "))
                            .font(.caption).foregroundStyle(fields.isEmpty ? .red : .secondary)
                    }
                    positionStatusBadge(for: position.id)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 9)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            if session.guidedSigningSession?.state == .complete {
                Label(L10n.text("All declared positions are complete."), systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            verificationBanner
        }
    }

    private var verificationBanner: some View {
        let values = session.guidedSigningVerification
        return Group {
            if !values.isEmpty {
                let valid = values.values.allSatisfy { $0 == .valid }
                Label(values.values.allSatisfy({ $0 == .valid })
                      ? L10n.text("Signatures verified against the local trust registry.")
                      : L10n.text("One or more signatures need trust or integrity review."),
                      systemImage: valid ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(valid ? .green : .orange)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((valid ? Color.green : Color.orange).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func positionStatusBadge(for positionID: String) -> some View {
        let state = session.guidedSigningSession?.positions[positionID]?.state
        return Text(state.map { stateLabel($0) } ?? L10n.text("Pending"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(for: positionID))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(statusColor(for: positionID).opacity(0.12), in: Capsule())
    }

    private var positionPicker: some View {
        HStack(spacing: 8) {
            Label(L10n.text("Signer position"), systemImage: "person.2")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 8)
            Picker(L10n.text("Signer position"), selection: Binding(
                get: { selectedPositionID ?? positions.first?.id ?? "" },
                set: { selectedPositionID = $0 }
            )) {
                ForEach(positions) { position in
                    Text(position.label).tag(position.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(L10n.text("Signer position"))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func assignmentSection(_ position: LeonardoSignerPosition) -> some View {
        if let assignment = selectedProgress?.assignment {
            VStack(alignment: .leading, spacing: 7) {
                Label(L10n.text("Assigned signer"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                Text(assignment.identity.fullName)
                Text(L10n.format("Declared identity · %@ · %@", documentTypeLabel(assignment.identity.documentType),
                                 assignment.identity.redactedDocumentNumber))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.format("Credential %@", assignment.credentialID.suffix(12).description))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Label(L10n.text("Identity declared; independent verification is not claimed."), systemImage: "person.badge.clock")
                    .font(.caption).foregroundStyle(.orange)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Label(L10n.text("Assign this position"), systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                Picker(L10n.text("Local profile"), selection: Binding(
                    get: { creatingProfile ? nil : selectedProfileID },
                    set: { value in
                        creatingProfile = value == nil
                        selectedProfileID = value
                        transientProfileID = value == nil ? UUID() : nil
                    }
                )) {
                    Text(L10n.text("New signer…")).tag(UUID?.none)
                    ForEach(session.guidedSigningProfiles) { profile in
                        Text(profile.displayName).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(L10n.text("Local profile"))
                if creatingProfile {
                    newProfileForm
                } else if selectedProfileNeedsIdentity {
                    inkOnlyProfileIdentityForm
                }
                credentialPicker
                Button {
                    showAssignmentConfirmation = true
                } label: {
                    Label(L10n.text("Review and assign"), systemImage: "checkmark.circle")
                }
                .buttonStyle(PremiumButtonStyle(prominent: true, compact: true))
                .disabled(!assignmentCanBeSubmitted)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var newProfileForm: some View {
        VStack(alignment: .leading, spacing: 7) {
            declaredIdentityForm
            HStack {
                Text(draftProfileRubric == nil ? L10n.text("No profile rubric") : L10n.text("Profile rubric ready"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Draw profile rubric…")) {
                    rubricEditorPurpose = .profile
                    showRubricEditor = true
                }
                .buttonStyle(PremiumButtonStyle(compact: true))
            }
            Toggle(L10n.text("Save this profile rubric separately"), isOn: $saveRubric)
                .disabled(draftProfileRubric == nil)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var inkOnlyProfileIdentityForm: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text("This profile contains a rubric only. Declare the signer identity for this assignment."))
                .font(.caption).foregroundStyle(.secondary)
            declaredIdentityForm
            if let rubric = selectedProfile?.rubric {
                HStack(spacing: 8) {
                    Image(nsImage: RubricDrawing.thumbnail(rubric))
                        .resizable().aspectRatio(3, contentMode: .fit).frame(height: 40)
                    Text(L10n.text("The saved rubric will be available only after you confirm reuse."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var declaredIdentityForm: some View {
        Group {
            TextField(L10n.text("Full name"), text: $fullName)
            Picker(L10n.text("Document type"), selection: $documentType) {
                ForEach(LeonardoIdentityDocumentType.allCases, id: \.rawValue) { type in
                    Text(documentTypeLabel(type)).tag(type)
                }
            }
            TextField(L10n.text("Document number"), text: $documentNumber)
            Toggle(L10n.text("Save identity details to my local profiles"), isOn: $saveIdentityDetails)
        }
    }

    private var credentialPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.guidedSigningCredentialIDs.isEmpty {
                Text(L10n.text("No personal credential is enrolled on this device."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker(L10n.text("Personal credential"), selection: $selectedCredentialID) {
                    ForEach(session.guidedSigningCredentialIDs, id: \.self) { id in
                        Text(id.suffix(12)).tag(id)
                    }
                }
            }
            Button(L10n.text("Enroll personal credential…")) { showCredentialEnrollment = true }
                .buttonStyle(PremiumButtonStyle(compact: true))
            Text(L10n.text("The private key is encrypted with a personal password and stored in the device keychain. Touch ID does not identify the signer."))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reviewSection(_ position: LeonardoSignerPosition) -> some View {
        if let progress = selectedProgress {
            VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("Review locations")).font(.subheadline.weight(.semibold))
                Spacer()
                positionStatusBadge(for: position.id)
            }
            if progress.state == .pending, progress.assignment != nil {
                Button(L10n.text("Begin review")) {
                    Task {
                        await session.beginGuidedPosition(position.id)
                        await refreshRenderedTargets()
                        advanceToNextTarget(for: position.id)
                    }
                }
                .buttonStyle(PremiumButtonStyle(prominent: true, compact: true))
            } else if progress.state == .paused {
                Button(L10n.text("Resume review")) {
                    Task {
                        await session.resumeGuidedPosition(positionID: position.id)
                        await refreshRenderedTargets()
                        advanceToNextTarget(for: position.id)
                    }
                }
                .buttonStyle(PremiumButtonStyle(prominent: true, compact: true))
            } else if progress.state == .signed {
                Label(L10n.text("This position is signed; its signed proof remains in the sidecar."), systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.green)
            } else if progress.state == .reviewing || progress.state == .readyToSign {
                if session.guidedSigningTargets.isEmpty {
                    ProgressView(L10n.text("Preparing the exact field locations…"))
                } else {
                    targetList(progress)
                    targetControls(progress)
                    HStack {
                        Button(L10n.text("Pause")) {
                            Task { await session.pauseGuidedPosition(positionID: position.id) }
                        }
                        .buttonStyle(PremiumButtonStyle(compact: true))
                        Spacer()
                        Button(L10n.text("Sign")) { showPassword = true }
                            .buttonStyle(PremiumButtonStyle(prominent: true, compact: true))
                            .disabled(progress.state != .readyToSign || !session.guidedSigningWorkflowOperable)
                    }
                }
            }
            if session.guidedSigningContentLocked {
                Label(L10n.text("The form is locked from the first confirmation."), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
                if session.guidedSigningCanStartRevision {
                    Button(L10n.text("Start a new revision for corrections…")) {
                        Task { await session.startGuidedSigningRevision() }
                    }
                    .buttonStyle(PremiumButtonStyle(compact: true))
                    .disabled(session.isProtected)
                }
                if session.isProtected {
                    Text(L10n.text("Unlock the document before creating a corrected revision."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func targetList(_ progress: LeonardoSigningPositionProgress) -> some View {
        // Keep the values captured by each row independent from the live
        // target array. Pausing clears `guidedSigningTargets`; indexing that
        // mutable array from a retained SwiftUI row can otherwise trap while
        // the list reconciles its children.
        let targets = GuidedSigningTargetRow.snapshot(session.guidedSigningTargets)
        return VStack(alignment: .leading, spacing: 4) {
            // Row identities remain stable when the same field appears more
            // than once. The occurrence is still carried in the navigation
            // call and never collapsed to a field ID alone.
            ForEach(targets) { row in
                let target = row.target
                let confirmed = progress.locations.contains {
                    $0.positionID == target.positionID
                        && $0.fieldID == target.fieldID
                        && $0.occurrence == target.occurrence
                }
                Button {
                    Task { @MainActor in
                        guard await session.renderer.hasFieldTarget(target.fieldID, occurrence: target.occurrence) else {
                            guard selectedPositionID == target.positionID else { return }
                            renderedTargetKeys.remove(targetKey(target))
                            targetAvailabilityChecked = true
                            session.guidedSigningStatus = L10n.text("This exact field occurrence is not available in the rendered document.")
                            return
                        }
                        guard selectedPositionID == target.positionID else { return }
                        renderedTargetKeys.insert(targetKey(target))
                        targetAvailabilityChecked = true
                        selectedTargetIndex = targets.firstIndex(where: { $0.id == row.id }) ?? 0
                        session.renderer.scroll(toField: target.fieldID, occurrence: target.occurrence)
                    }
                } label: {
                    HStack {
                        Image(systemName: confirmed ? "checkmark.circle.fill" : "circle")
                        Text(L10n.format("%@ · occurrence %d", fieldLabel(target.fieldID), target.occurrence + 1))
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(session.renderer.isReady && targetAvailabilityChecked
                          && !renderedTargetKeys.contains(targetKey(target)))
                .foregroundStyle(confirmed ? .green : (renderedTargetKeys.contains(targetKey(target)) ? .primary : .secondary))
            }
        }
    }

    @ViewBuilder
    private func targetControls(_ progress: LeonardoSigningPositionProgress) -> some View {
        if !session.renderer.isReady {
            ProgressView(L10n.text("Waiting for the rendered document…"))
        } else if !targetAvailabilityChecked {
            ProgressView(L10n.text("Checking rendered field locations…"))
        } else if let target = currentTarget,
                  renderedTargetKeys.contains(targetKey(target)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.guidedSigningContext(for: target))
                    .font(.caption).monospaced()
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Toggle(L10n.text("I have read this exact field context"), isOn: $contextRead)
                    .font(.caption)
                Picker(L10n.text("Rubric for this occurrence"), selection: $reuse) {
                    Text(L10n.text("New rubric")).tag(LeonardoRubricReuse.new)
                    if session.guidedSigningSession?.rubricByPosition[target.positionID] != nil {
                        Text(L10n.text("Reuse in this signer session")).tag(LeonardoRubricReuse.session)
                    }
                    if progress.assignment?.profileRubric != nil {
                        Text(L10n.text("Reuse saved profile rubric")).tag(LeonardoRubricReuse.profile)
                    }
                }
                if let rubric = rubricForCurrentChoice {
                    Image(nsImage: RubricDrawing.thumbnail(rubric)).resizable().aspectRatio(3, contentMode: .fit)
                        .frame(height: 55).accessibilityLabel(L10n.text("Selected rubric"))
                }
                if reuse == .new {
                    Button(L10n.text(locationRubric == nil ? "Draw rubric…" : "Replace rubric…")) {
                        rubricEditorPurpose = .location
                        showRubricEditor = true
                    }
                    .buttonStyle(PremiumButtonStyle(compact: true))
                } else {
                    Toggle(L10n.text("I explicitly confirm reusing this rubric"), isOn: $reuseConfirmed)
                        .font(.caption)
                }
                Button(L10n.text("Confirm exact occurrence")) {
                    Task {
                        await session.confirmGuidedLocation(target: target,
                            rubric: rubricForCurrentChoice ?? LeonardoRubric(), reuse: reuse,
                            reuseConfirmed: reuse == .new ? true : reuseConfirmed,
                            contextRead: contextRead)
                        advanceToNextTarget(for: target.positionID)
                    }
                }
                .buttonStyle(PremiumButtonStyle(prominent: true))
                .disabled(nextTargetIndex != selectedTargetIndex || !contextRead || rubricForCurrentChoice?.isValid != true
                          || (reuse != .new && !reuseConfirmed))
            }
        } else if currentTarget != nil {
            Label(L10n.text("This exact occurrence is not available in the rendered document; confirmation is blocked."),
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func targetKey(_ target: LeonardoSigningLocationTarget) -> String {
        "\(target.positionID)#\(target.fieldID)#\(target.occurrence)"
    }

    @MainActor
    private func refreshRenderedTargets() async {
        targetAvailabilityChecked = false
        let expectedPositionID = selectedPosition?.id
        let expectedTargets = session.guidedSigningTargets
        var available = Set<String>()
        for target in expectedTargets {
            if await session.renderer.hasFieldTarget(target.fieldID, occurrence: target.occurrence) {
                available.insert(targetKey(target))
            }
        }
        guard selectedPosition?.id == expectedPositionID,
              session.guidedSigningTargets == expectedTargets else { return }
        renderedTargetKeys = available
        targetAvailabilityChecked = true
        if let target = currentTarget, !available.contains(targetKey(target)) {
            session.guidedSigningStatus = L10n.text("A field occurrence is missing from the rendered document; confirmation is blocked.")
        }
    }

    private func refreshTargetsSoon() {
        Task { @MainActor in await refreshRenderedTargets() }
    }

    private func checkCurrentTarget() {
        guard let target = currentTarget else { return }
        Task { @MainActor in
            let available = await session.renderer.hasFieldTarget(target.fieldID, occurrence: target.occurrence)
            guard selectedPositionID == target.positionID, currentTarget == target else { return }
            if available {
                renderedTargetKeys.insert(targetKey(target))
            } else {
                renderedTargetKeys.remove(targetKey(target))
                session.guidedSigningStatus = L10n.text("This exact field occurrence is not available in the rendered document.")
            }
            targetAvailabilityChecked = true
        }
    }

    @MainActor
    private func advanceToNextTarget(for positionID: String) {
        guard selectedPositionID == positionID,
              let progress = session.guidedSigningSession?.positions[positionID],
              let next = session.guidedSigningTargets.firstIndex(where: { target in
                  !progress.locations.contains {
                      $0.positionID == target.positionID
                          && $0.fieldID == target.fieldID
                          && $0.occurrence == target.occurrence
                  }
              }) else { return }
        selectedTargetIndex = next
        contextRead = false
        reuseConfirmed = false
        let target = session.guidedSigningTargets[next]
        if renderedTargetKeys.contains(targetKey(target)) {
            session.renderer.scroll(toField: target.fieldID, occurrence: target.occurrence)
        }
    }

    private func integrityWarning(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("Signing review blocked"), systemImage: "exclamationmark.shield")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
            if session.guidedSigningCanStartRevision {
                Button(L10n.text("Start a new revision for corrections…")) {
                    Task { await session.startGuidedSigningRevision() }
                }
                .buttonStyle(PremiumButtonStyle(compact: true))
                .disabled(session.isProtected)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func assignSigner() {
        guard let positionID = selectedPosition?.id,
              let profile = profileForAssignment,
              let credential = selectedCredential else { return }
        Task {
            await session.assignGuidedSigner(positionID: positionID, profile: profile, credential: credential,
                                             saveOptions: LeonardoProfileSaveOptions(
                                                saveIdentityDetails: needsDeclaredIdentityInput && saveIdentityDetails,
                                                saveRubric: creatingProfile && saveRubric))
        }
    }

    private func assignedFieldLabels(for positionID: String) -> [String] {
        guard let document = session.leonardoDocument else { return [] }
        return document.metadata.fields.compactMap { fieldID, field in
            guard field.type == .rubric, field.signerPosition == positionID else { return nil }
            return field.label ?? fieldID
        }.sorted()
    }

    private func fieldLabel(_ fieldID: String) -> String {
        session.leonardoFieldDefinition(fieldID)?.label ?? fieldID
    }

    private func documentTypeLabel(_ type: LeonardoIdentityDocumentType) -> String {
        switch type {
        case .nationalID: return L10n.text("National ID")
        case .passport: return L10n.text("Passport")
        case .driverLicense: return L10n.text("Driver license")
        case .other: return L10n.text("Other document")
        }
    }

    private func statusIcon(for positionID: String) -> String {
        switch session.guidedSigningSession?.positions[positionID]?.state {
        case .some(.signed): return "checkmark.seal.fill"
        case .some(.readyToSign): return "checkmark.circle"
        case .some(.reviewing): return "eye"
        case .some(.paused): return "pause.circle"
        default: return "circle"
        }
    }

    private func statusColor(for positionID: String) -> Color {
        switch session.guidedSigningSession?.positions[positionID]?.state {
        case .some(.signed): return .green
        case .some(.readyToSign): return session.accentColor
        case .some(.paused): return .orange
        default: return .secondary
        }
    }

    private func stateLabel(_ state: LeonardoSigningPositionState) -> String {
        switch state {
        case .pending: return L10n.text("Pending")
        case .reviewing: return L10n.text("Reviewing")
        case .paused: return L10n.text("Paused")
        case .readyToSign: return L10n.text("Ready to sign")
        case .signed: return L10n.text("Signed")
        }
    }

}

/// Adds a declared identity for this assignment. Keeping the saved profile ID
/// lets the session reject reuse. Only explicit save consent persists identity.
struct GuidedSigningTransientProfile {
    static func make(
        savedProfile: LeonardoSignerProfile,
        identity: LeonardoDeclaredIdentity
    ) -> LeonardoSignerProfile {
        LeonardoSignerProfile(
            id: savedProfile.id,
            displayName: identity.fullName,
            identity: identity,
            verificationStatus: savedProfile.verificationStatus,
            rubric: savedProfile.rubric
        )
    }
}

/// A value snapshot for one rendered location. SwiftUI may retain a row while
/// the session changes (for example when Pause clears the active targets), so
/// row actions must never subscript the session's mutable target array.
struct GuidedSigningTargetRow: Identifiable, Equatable {
    let target: LeonardoSigningLocationTarget

    var id: String {
        "\(target.positionID)#\(target.fieldID)#\(target.occurrence)"
    }

    static func snapshot(_ targets: [LeonardoSigningLocationTarget]) -> [Self] {
        targets.map(Self.init)
    }
}

private struct GuidedSigningCredentialEnrollment: View {
    let onEnroll: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Enroll personal credential")).font(.title3.bold())
            Text(L10n.text("Choose a personal password. It encrypts the signing key before the device keychain stores it."))
                .font(.caption).foregroundStyle(.secondary)
            SecureField(L10n.text("Personal credential password"), text: $password)
            SecureField(L10n.text("Confirm password"), text: $confirmation)
            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }
                    .buttonStyle(PremiumButtonStyle(compact: true))
                Button(L10n.text("Enroll")) { onEnroll(password) }
                    .buttonStyle(PremiumButtonStyle(prominent: true, compact: true))
                    .disabled(password.count < 8 || password != confirmation)
            }
        }
        .padding(22).frame(width: 410)
    }
}

private struct GuidedSigningPassword: View {
    let onUnlock: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Authorize signature")).font(.title3.bold())
            Text(L10n.text("Enter the personal credential password to decrypt the encrypted signing key."))
                .font(.caption).foregroundStyle(.secondary)
            SecureField(L10n.text("Personal credential password"), text: $password)
            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }
                    .buttonStyle(PremiumButtonStyle(compact: true))
                Button(L10n.text("Sign")) { onUnlock(password) }
                    .buttonStyle(PremiumButtonStyle(prominent: true, compact: true)).disabled(password.isEmpty)
            }
        }
        .padding(22).frame(width: 410)
    }
}
