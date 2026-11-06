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

struct MobileRubricPreview: View {
    let rubric: LeonardoRubric
    var body: some View {
        MobileRubricCanvas(rubric: .constant(rubric), color: "#111111", width: 4,
                           style: .solid, isInteractive: false)
            .frame(maxWidth: .infinity).aspectRatio(3, contentMode: .fit)
            .background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35)))
    }
}

struct MobileRubricCanvas: View {
    @Binding var rubric: LeonardoRubric
    let color: String
    let width: Double
    let style: LeonardoInkStyle
    let isInteractive: Bool
    let canCommit: (LeonardoRubric) -> Bool
    @State private var livePoints: [LeonardoInkPoint] = []
    @Binding private var limitReached: Bool
    private static let maximumPoints = 600

    init(rubric: Binding<LeonardoRubric>, color: String, width: Double,
         style: LeonardoInkStyle, isInteractive: Bool,
         canCommit: @escaping (LeonardoRubric) -> Bool = { $0.isValid },
         limitReached: Binding<Bool> = .constant(false)) {
        self._rubric = rubric
        self.color = color
        self.width = width
        self.style = style
        self.isInteractive = isInteractive
        self.canCommit = canCommit
        self._limitReached = limitReached
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for stroke in rubric.strokes { draw(stroke, in: size, context: &context) }
                if !livePoints.isEmpty {
                    draw(LeonardoInkStroke(color: color, width: width, style: style, points: livePoints),
                         in: size, context: &context)
                }
            }
            .background(Color.white)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isInteractive else { return }
                guard drawingRect(in: geometry.size).contains(value.location) else { return }
                let point = normalized(value.location, in: geometry.size)
                let pointCount = rubric.strokes.reduce(0, { $0 + $1.points.count })
                guard rubric.strokes.count < LeonardoRubric.maximumStrokes else {
                    limitReached = true
                    return
                }
                guard pointCount + livePoints.count < Self.maximumPoints else {
                    limitReached = true
                    return
                }
                if livePoints.last.map({ distance($0, point) < 1.0 }) != true {
                    livePoints.append(point)
                }
            }.onEnded { _ in
                guard isInteractive, !livePoints.isEmpty else { livePoints.removeAll(); return }
                let pointCount = rubric.strokes.reduce(0, { $0 + $1.points.count })
                guard rubric.strokes.count < LeonardoRubric.maximumStrokes,
                      pointCount + livePoints.count <= Self.maximumPoints else {
                    livePoints.removeAll()
                    limitReached = true
                    return
                }
                var candidate = rubric
                candidate.strokes.append(LeonardoInkStroke(color: color, width: width, style: style,
                                                            points: livePoints))
                guard canCommit(candidate) else {
                    livePoints.removeAll()
                    limitReached = true
                    return
                }
                rubric = candidate
                livePoints.removeAll()
            })
        }
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> LeonardoInkPoint {
        let rect = drawingRect(in: size)
        let x = max(0, min(LeonardoRubric.canvasWidth,
            (((location.x - rect.minX) / max(1, rect.width)) * LeonardoRubric.canvasWidth).rounded()))
        let y = max(0, min(LeonardoRubric.canvasHeight,
            (((location.y - rect.minY) / max(1, rect.height)) * LeonardoRubric.canvasHeight).rounded()))
        return LeonardoInkPoint(x: x, y: y)
    }

    private func distance(_ left: LeonardoInkPoint, _ right: LeonardoInkPoint) -> Double {
        hypot(left.x - right.x, left.y - right.y)
    }

    private func drawingRect(in size: CGSize) -> CGRect {
        let drawingWidth = min(size.width, size.height * 3)
        let drawingHeight = drawingWidth / 3
        return CGRect(x: (size.width - drawingWidth) / 2, y: (size.height - drawingHeight) / 2,
                      width: drawingWidth, height: drawingHeight)
    }

    private func draw(_ stroke: LeonardoInkStroke, in size: CGSize, context: inout GraphicsContext) {
        guard !stroke.points.isEmpty else { return }
        let rect = drawingRect(in: size)
        let scale = min(rect.width / LeonardoRubric.canvasWidth,
                        rect.height / LeonardoRubric.canvasHeight)
        for (index, point) in stroke.points.enumerated() {
            let previous = stroke.points[max(0, index - 1)]
            let end = previous == point
                ? LeonardoInkPoint(x: point.x + 0.01, y: point.y)
                : point
            var path = Path()
            path.move(to: display(previous, in: size))
            path.addLine(to: display(end, in: size))
            context.stroke(path, with: .color(hexColor(stroke.color)),
                           style: StrokeStyle(lineWidth: stroke.segmentWidth(at: index) * scale,
                                              lineCap: .round, lineJoin: .round))
        }
    }

    private func display(_ point: LeonardoInkPoint, in size: CGSize) -> CGPoint {
        let rect = drawingRect(in: size)
        return CGPoint(x: rect.minX + point.x / LeonardoRubric.canvasWidth * rect.width,
                       y: rect.minY + point.y / LeonardoRubric.canvasHeight * rect.height)
    }

    private func hexColor(_ value: String) -> Color {
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let number = UInt64(hex, radix: 16) else { return .black }
        return Color(red: Double((number >> 16) & 0xff) / 255,
                     green: Double((number >> 8) & 0xff) / 255,
                     blue: Double(number & 0xff) / 255)
    }
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

    init(request: RubricRequest, library: MobileLibrary) {
        self.request = request
        self.library = library
        let draft = library.rubricDraft(requestID: request.id)
        _phase = State(initialValue: draft?.state == .submitted ? .submitted
            : request.state == .accepted || draft != nil ? .drawing : .awaitingApproval)
        _label = State(initialValue: draft?.label ?? request.labelHint ?? "Rúbrica")
        if let response = draft?.response {
            _rubric = State(initialValue: response.rubric)
            _frozen = State(initialValue: true)
        } else if let drawing = draft?.drawing {
            _rubric = State(initialValue: drawing)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    requestHeader
                    switch phase {
                    case .awaitingApproval, .accepting:
                        approvalControls
                    case .drawing, .sending:
                        if isSubmitted { submittedState } else { drawingControls }
                    case .submitted:
                        submittedState
                    }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Nueva rúbrica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("rubric-request-sheet")
        .onChange(of: rubric) { _, drawing in persistSnapshot(drawing: drawing, label: label) }
        .onChange(of: label) { _, value in persistSnapshot(drawing: rubric, label: value) }
    }

    private var requestHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Solicitud de \(request.requesterName)", systemImage: "laptopcomputer.and.iphone")
                .font(.headline)
            Text(request.labelHint.map { "Etiqueta sugerida: \($0)" } ?? "El ordenador espera una rúbrica manuscrita.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Solo se enviará el dibujo cuando pulses Enviar. Los documentos permanecen en modo lectura.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var approvalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if phase == .accepting { ProgressView("Comprobando solicitud…") }
            else {
                Button("Aceptar y dibujar", systemImage: "checkmark.circle.fill") { accept() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("rubric-accept")
                Button("Rechazar", role: .destructive) { reject() }
                    .accessibilityIdentifier("rubric-reject")
            }
        }
    }

    private var drawingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Nombre de la rúbrica", text: $label)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("rubric-label")
                .disabled(frozen || terminalBlocked || phase == .sending)
            HStack {
                Picker("Color", selection: $color) {
                    colorOption("Negro", "#111111")
                    colorOption("Azul", "#1C5D99")
                    colorOption("Rojo", "#A52A2A")
                }
                .pickerStyle(.menu).disabled(frozen || terminalBlocked || phase == .sending)
                Picker("Trazo", selection: $style) {
                    Text("Sólido").tag(LeonardoInkStyle.solid)
                    Text("Pincel").tag(LeonardoInkStyle.brush)
                }
                .pickerStyle(.menu).disabled(frozen || terminalBlocked || phase == .sending)
            }
            HStack {
                Text("Ancho")
                Slider(value: $width, in: 0.5...12, step: 0.5)
                    .accessibilityLabel("Ancho del trazo")
                    .disabled(frozen || terminalBlocked || phase == .sending)
                Text(width, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit().frame(width: 34)
            }
            if showingPreview || frozen {
                MobileRubricPreview(rubric: rubric)
                    .accessibilityIdentifier("rubric-preview")
            } else {
                MobileRubricCanvas(rubric: $rubric, color: color, width: width, style: style,
                                   isInteractive: !frozen && !terminalBlocked && phase != .sending,
                                   canCommit: { RubricResponse.fitsEncodedSize(label: label, rubric: $0) },
                                   limitReached: $limitReached)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(LeonardoRubric.canvasWidth / LeonardoRubric.canvasHeight, contentMode: .fit)
                    .accessibilityIdentifier("rubric-canvas")
            }
            if limitReached {
                Label("Límite alcanzado: máximo 256 trazos, 600 puntos y 24 KiB.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("rubric-limit")
            }
            if rubric.isValid && !drawingFitsResponseLimit && !frozen {
                Label("El dibujo supera el límite portátil de 24 KiB.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button("Deshacer", systemImage: "arrow.uturn.backward") {
                    if !rubric.strokes.isEmpty { rubric.strokes.removeLast() }
                }
                .disabled(frozen || terminalBlocked || rubric.strokes.isEmpty || phase == .sending)
                .accessibilityIdentifier("rubric-undo")
                Button("Limpiar", systemImage: "trash") {
                    limitReached = false
                    rubric = LeonardoRubric()
                }
                    .disabled(frozen || terminalBlocked || rubric.strokes.isEmpty || phase == .sending)
                    .accessibilityIdentifier("rubric-clear")
                Spacer()
                if terminalBlocked {
                    Label("Borrador bloqueado: pide una nueva solicitud", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if frozen {
                    Label("Vista previa bloqueada tras el envío", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button(showingPreview ? "Dibujar" : "Vista previa",
                           systemImage: showingPreview ? "pencil" : "eye") {
                        showingPreview.toggle()
                    }
                    .disabled(phase == .sending)
                    .accessibilityIdentifier("rubric-preview-toggle")
                }
            }
            if let draft = currentDraft, draft.state == .pendingSend, draft.response != nil {
                Button("Reintentar envío", systemImage: "arrow.clockwise") { retry(draft) }
                    .buttonStyle(.borderedProminent).disabled(phase == .sending)
                    .accessibilityIdentifier("rubric-retry")
            } else if terminalBlocked {
                Label("La solicitud ya no admite envíos (caducada, cancelada o revocada).",
                      systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Enviar rúbrica", systemImage: "paperplane.fill") { send() }
                    .buttonStyle(.borderedProminent)
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
                .font(.headline).foregroundStyle(.green)
            Text("El ordenador ha confirmado exactamente este dibujo para revisarlo.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Terminar") { dismiss() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("rubric-done")
        }
    }

    private func colorOption(_ title: String, _ value: String) -> some View {
        Text(title).tag(value)
    }

    private var drawingFitsResponseLimit: Bool {
        RubricResponse.fitsEncodedSize(label: label, rubric: rubric)
    }

    private var currentDraft: MobileRubricDraft? {
        library.rubricDraft(requestID: request.id)
    }

    private var terminalBlocked: Bool {
        currentDraft?.state == .blocked
    }

    private var isSubmitted: Bool {
        phase == .submitted || currentDraft?.state == .submitted
    }

    private func accept() {
        failure = nil; phase = .accepting
        Task {
            do {
                acceptedRequest = try await library.acceptRubricRequest(request)
                phase = .drawing
            } catch {
                phase = .awaitingApproval
                failure = "No se pudo aceptar la solicitud. Puedes intentarlo de nuevo."
            }
        }
    }

    private func reject() {
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
        Task {
            do {
                try await library.persistRubricDraft(requestID: request.id, label: label, drawing: savedDrawing)
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
                    await library.blockRubricDraft(requestID: request.id,
                                                   message: "La solicitud ya no admite envíos; pide una nueva solicitud.")
                    failure = "Este vínculo ya no admite la solicitud. Cierra esta tarjeta y pide una nueva."
                } else {
                    frozen = library.rubricDraft(requestID: request.id)?.response != nil
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
