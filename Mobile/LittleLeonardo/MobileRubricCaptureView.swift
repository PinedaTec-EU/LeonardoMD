import SwiftUI
import LeonardoCore
import LeonardoSync

private enum MobileRubricCapturePhase {
    case awaitingApproval
    case accepting
    case drawing
    case sending
    case submitted
}

struct MobileRubricCaptureView: View {
    let request: RubricRequest
    let library: MobileLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var phase: MobileRubricCapturePhase
    @State private var acceptedRequest: RubricRequest?
    @State private var rubric = LeonardoRubric()
    @State private var label: String
    @State private var color = "#111111"
    @State private var width = 4.0
    @State private var style = LeonardoInkStyle.solid
    @State private var showingPreview = false
    @State private var frozen = false
    @State private var limitReached = false
    @State private var failure: String?
    @State private var manuallyExpanded = false
    @State private var landscapeDismissed = false

    init(request: RubricRequest, library: MobileLibrary) {
        self.request = request
        self.library = library
        let draft = library.rubricDraft(for: request)
        _acceptedRequest = State(initialValue: draft?.request)
        _phase = State(initialValue: draft?.state == .submitted ? .submitted
            : draft != nil && draft?.state != .pendingAcceptance ? .drawing : .awaitingApproval)
        _label = State(initialValue: draft?.label ?? request.labelHint ?? "Rúbrica")
        if let response = draft?.response {
            _rubric = State(initialValue: response.rubric)
            _frozen = State(initialValue: true)
        } else if let drawing = draft?.drawing {
            _rubric = State(initialValue: drawing)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let expanded = canDraw && !showingPreview &&
                (manuallyExpanded || (landscape && !landscapeDismissed))
            NavigationStack {
                Group {
                    if expanded {
                        expandedDrawing(landscape: landscape)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                requestHeader
                                switch phase {
                                case .awaitingApproval, .accepting: approvalControls
                                case .drawing, .sending:
                                    if isSubmitted { submittedState } else { drawingControls }
                                case .submitted: submittedState
                                }
                                if let failure {
                                    Label(failure, systemImage: "exclamationmark.triangle")
                                        .font(.footnote).foregroundStyle(MobileClassic.heading)
                                }
                            }
                            .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
                        }.classicSurface()
                    }
                }
                .navigationTitle("Nueva rúbrica")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Cerrar") { dismiss() } }
                .toolbar(expanded ? .hidden : .visible, for: .navigationBar)
            }
            .onChange(of: landscape) { _, isLandscape in
                if !isLandscape {
                    manuallyExpanded = false
                    landscapeDismissed = false
                }
            }
        }
        .tint(MobileClassic.accent)
        .foregroundStyle(MobileClassic.ink)
        .background(MobileClassic.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rubric-request-sheet")
        .onChange(of: currentDraft?.state) { _, state in
            guard let draft = currentDraft else { return }
            if state == .blocked {
                failure = nil
            } else if state == .submitted {
                failure = nil
                phase = .submitted
            }
            else if state == .accepted, phase == .awaitingApproval || phase == .accepting {
                failure = nil
                acceptedRequest = draft.request
                rubric = draft.drawing ?? LeonardoRubric()
                label = draft.label
                phase = .drawing
            }
        }
        .onChange(of: rubric) { _, drawing in persistSnapshot(drawing: drawing, label: label) }
        .onChange(of: label) { _, value in persistSnapshot(drawing: rubric, label: value) }
    }

    private var requestHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Solicitud de \(request.requesterName)", systemImage: "laptopcomputer.and.iphone")
                .font(.headline).foregroundStyle(MobileClassic.heading)
            Text(request.labelHint.map { "Etiqueta sugerida: \($0)" } ?? "El ordenador espera una rúbrica manuscrita.")
                .font(.subheadline).foregroundStyle(MobileClassic.secondary)
            Text("Solo se enviará el dibujo cuando pulses Enviar. Los documentos permanecen en modo lectura.")
                .font(.footnote).foregroundStyle(MobileClassic.secondary)
        }
    }

    private var approvalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if terminalBlocked {
                Label("La solicitud ya no admite envíos (caducada, cancelada o revocada).",
                      systemImage: "lock.fill")
                    .accessibilityIdentifier("rubric-approval-blocked")
                Text("Cierra esta tarjeta y pide una nueva solicitud al ordenador.")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
            } else if phase == .accepting { ProgressView("Comprobando solicitud…") }
            else {
                Button("Aceptar y dibujar", systemImage: "checkmark.circle.fill") { accept() }
                    .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper).accessibilityIdentifier("rubric-accept")
                Button("Rechazar", role: .destructive) { reject() }
                    .accessibilityIdentifier("rubric-reject")
            }
        }
    }

    private var drawingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Nombre de la rúbrica", text: $label)
                .textInputAutocapitalization(.sentences)
                .padding(12).background(MobileClassic.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MobileClassic.border))
                .accessibilityIdentifier("rubric-label")
                .disabled(frozen || terminalBlocked || phase == .sending)
            if canDraw && !showingPreview {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Gira el dispositivo para dibujar con más espacio", systemImage: "rotate.right")
                        .font(.headline).foregroundStyle(MobileClassic.heading)
                    Text("Al volver a vertical, regresarás a esta página conservando tu dibujo.")
                        .font(.callout).foregroundStyle(MobileClassic.secondary)
                    Button("Ampliar lienzo", systemImage: "arrow.up.left.and.arrow.down.right") {
                        manuallyExpanded = true
                    }.foregroundStyle(MobileClassic.accent)
                        .accessibilityIdentifier("rubric-expand")
                }
            }
            inkTools
            if showingPreview || frozen {
                MobileRubricPreview(rubric: rubric)
                    .accessibilityIdentifier("rubric-preview")
            } else {
                drawingCanvas
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3, contentMode: .fit)
            }
            if limitReached {
                Label("Límite alcanzado: máximo 256 trazos, 600 puntos y 24 KiB.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
                    .accessibilityIdentifier("rubric-limit")
            }
            if rubric.isValid && !drawingFitsResponseLimit && !frozen {
                Label("El dibujo supera el límite portátil de 24 KiB.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
            }
            undoControls
            if terminalBlocked {
                Label("Borrador bloqueado: pide una nueva solicitud", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
            } else if frozen {
                Label("Vista previa bloqueada tras el envío", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
            } else {
                Button(showingPreview ? "Dibujar" : "Vista previa",
                       systemImage: showingPreview ? "pencil" : "eye") {
                    showingPreview.toggle()
                }
                .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper)
                .disabled(phase == .sending || rubric.strokes.isEmpty)
                .accessibilityIdentifier("rubric-preview-toggle")
            }
            if let draft = currentDraft, draft.state == .pendingSend, draft.response != nil {
                Button("Reintentar envío", systemImage: "arrow.clockwise") { retry(draft) }
                    .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper).disabled(phase == .sending)
                    .accessibilityIdentifier("rubric-retry")
            } else if terminalBlocked {
                Label("La solicitud ya no admite envíos (caducada, cancelada o revocada).",
                      systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(MobileClassic.secondary)
            } else {
                Button("Enviar rúbrica", systemImage: "paperplane.fill") { send() }
                    .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper)
                    .disabled(frozen || phase == .sending || !rubric.isValid || !drawingFitsResponseLimit
                              || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("rubric-send")
            }
            if phase == .sending { ProgressView("Enviando…") }
        }
    }

    private var submittedState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Rúbrica enviada", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(MobileClassic.heading)
            Text("El ordenador ha confirmado exactamente este dibujo para revisarlo.")
                .font(.footnote).foregroundStyle(MobileClassic.secondary)
            Button("Terminar") { dismiss() }
                .buttonStyle(.borderedProminent).foregroundStyle(MobileClassic.paper).accessibilityIdentifier("rubric-done")
        }
    }

    private var canDraw: Bool {
        phase == .drawing && !frozen && !terminalBlocked && !isSubmitted
    }

    private var inkTools: some View {
        MobileRubricInkTools(color: $color, width: $width, style: $style, enabled: canDraw)
    }

    private var drawingCanvas: some View {
        MobileRubricCanvas(rubric: $rubric, color: color, width: width, style: style,
            isInteractive: canDraw,
            canCommit: { canDraw && RubricResponse.fitsEncodedSize(label: label, rubric: $0) },
            limitReached: $limitReached)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MobileClassic.border))
            .accessibilityIdentifier("rubric-canvas")
    }

    private var undoControls: some View {
        HStack(spacing: 24) {
            Button("Deshacer", systemImage: "arrow.uturn.backward") {
                if !rubric.strokes.isEmpty { rubric.strokes.removeLast() }
            }.accessibilityIdentifier("rubric-undo")
            Button("Limpiar", systemImage: "trash") {
                limitReached = false
                rubric = LeonardoRubric()
            }.accessibilityIdentifier("rubric-clear")
        }.foregroundStyle(MobileClassic.accent)
            .disabled(!canDraw || rubric.strokes.isEmpty)
    }

    private func expandedDrawing(landscape: Bool) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    Button("Volver", systemImage: "arrow.left") {
                        manuallyExpanded = false
                        landscapeDismissed = landscape
                    }.foregroundStyle(MobileClassic.accent)
                        .accessibilityIdentifier("rubric-collapse")
                    inkTools
                    undoControls
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.fixedSize(horizontal: false, vertical: true)
            drawingCanvas.frame(maxWidth: .infinity, maxHeight: .infinity)
            if limitReached {
                Text("Límite alcanzado: máximo 256 trazos, 600 puntos y 24 KiB.")
                    .font(.caption).foregroundStyle(MobileClassic.heading)
            }
        }
        .padding(8)
        .background(MobileClassic.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rubric-expanded")
    }

    private var drawingFitsResponseLimit: Bool {
        RubricResponse.fitsEncodedSize(label: label, rubric: rubric)
    }

    private var currentDraft: MobileRubricDraft? {
        library.rubricDraft(for: request)
    }

    private var terminalBlocked: Bool {
        currentDraft?.state == .blocked
    }

    private var isSubmitted: Bool {
        phase == .submitted || currentDraft?.state == .submitted
    }

    private func accept() {
        guard !terminalBlocked else { return }
        failure = nil; phase = .accepting
        Task {
            do {
                acceptedRequest = try await library.acceptRubricRequest(request)
                phase = .drawing
            } catch {
                phase = .awaitingApproval
                failure = terminalBlocked ? nil
                    : "No se pudo aceptar la solicitud. Puedes intentarlo de nuevo."
            }
        }
    }

    private func reject() {
        guard !terminalBlocked else { return }
        failure = nil
        Task {
            do { try await library.rejectRubricRequest(request); dismiss() }
            catch { failure = "No se pudo rechazar la solicitud." }
        }
    }

    private func persistSnapshot(drawing: LeonardoRubric, label: String) {
        guard !frozen, !terminalBlocked, phase == .drawing,
              currentDraft?.state == .accepted else { return }
        let savedDrawing: LeonardoRubric?
        if drawing.strokes.isEmpty {
            // An empty canvas is an explicit unsent Clear. Persist it as nil
            // without tripping the portable payload validation.
            savedDrawing = nil
        } else if drawing.isValid && RubricResponse.fitsEncodedSize(label: label, rubric: drawing) {
            savedDrawing = drawing
        } else {
            // Never turn a nonempty invalid drawing into an empty draft: the
            // last valid persisted input remains recoverable after restart.
            failure = "El dibujo supera los límites portátiles; se conserva el último borrador válido."
            return
        }
        // Register this snapshot while handling the UI event. The observer
        // Task may run in any order without changing persistence order.
        let write = library.enqueueRubricDraftSnapshot(request: request,
                                                       label: label, drawing: savedDrawing)
        Task {
            do {
                try await write.value
            } catch {
                failure = "No se pudo guardar el borrador local. Inténtalo de nuevo antes de enviar."
            }
        }
    }

    private func send() {
        failure = nil; phase = .sending
        Task {
            do {
                _ = try await library.submitRubric(request: acceptedRequest ?? request,
                                                   label: label, rubric: rubric)
                phase = .submitted
            } catch {
                phase = .drawing
                if isTerminal(error) {
                    await library.blockRubricDraft(request: request,
                                                   message: "La solicitud ya no admite envíos; pide una nueva solicitud.")
                    failure = "Este vínculo ya no admite la solicitud. Cierra esta tarjeta y pide una nueva."
                } else {
                    frozen = library.rubricDraft(for: request)?.response != nil
                    failure = "No se pudo enviar. El dibujo está guardado y puedes reintentarlo."
                }
            }
        }
    }

    private func retry(_ draft: MobileRubricDraft) {
        failure = nil; phase = .sending
        Task {
            do { _ = try await library.retryRubricDraft(draft); phase = .submitted }
            catch { phase = .drawing; failure = "El envío sigue pendiente. Comprueba la conexión e inténtalo de nuevo." }
        }
    }

    private func isTerminal(_ error: Error) -> Bool {
        if let error = error as? RubricExchangeError {
            return [.expired, .invalidTransition, .unsupported, .notFound, .conflict].contains(error)
        }
        return (error as? SyncError) == .revoked
    }
}
