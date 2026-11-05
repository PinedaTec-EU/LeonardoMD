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
    @State private var livePoints: [LeonardoInkPoint] = []
    private static let maximumPoints = 600

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for stroke in rubric.strokes { draw(stroke, in: size, context: &context) }
                if livePoints.count > 1 {
                    draw(LeonardoInkStroke(color: color, width: width, style: style, points: livePoints),
                         in: size, context: &context)
                }
            }
            .background(Color.white)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isInteractive else { return }
                let point = normalized(value.location, in: geometry.size)
                if livePoints.last.map({ distance($0, point) < 1.0 }) != true,
                   rubric.strokes.reduce(0, { $0 + $1.points.count }) + livePoints.count < Self.maximumPoints {
                    livePoints.append(point)
                }
            }.onEnded { _ in
                guard isInteractive, !livePoints.isEmpty else { livePoints.removeAll(); return }
                rubric.strokes.append(LeonardoInkStroke(color: color, width: width, style: style,
                                                        points: livePoints))
                livePoints.removeAll()
            })
        }
        .frame(minHeight: 90)
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> LeonardoInkPoint {
        let drawingWidth = min(size.width, size.height * 3)
        let drawingHeight = drawingWidth / 3
        let origin = CGPoint(x: (size.width - drawingWidth) / 2, y: (size.height - drawingHeight) / 2)
        let x = max(0, min(LeonardoRubric.canvasWidth,
            (((location.x - origin.x) / max(1, drawingWidth)) * LeonardoRubric.canvasWidth).rounded()))
        let y = max(0, min(LeonardoRubric.canvasHeight,
            (((location.y - origin.y) / max(1, drawingHeight)) * LeonardoRubric.canvasHeight).rounded()))
        return LeonardoInkPoint(x: x, y: y)
    }

    private func distance(_ left: LeonardoInkPoint, _ right: LeonardoInkPoint) -> Double {
        hypot(left.x - right.x, left.y - right.y)
    }

    private func draw(_ stroke: LeonardoInkStroke, in size: CGSize, context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        path.move(to: display(first, in: size))
        for point in stroke.points.dropFirst() { path.addLine(to: display(point, in: size)) }
        let scale = min(size.width / LeonardoRubric.canvasWidth,
                        size.height / LeonardoRubric.canvasHeight)
        context.stroke(path, with: .color(hexColor(stroke.color)),
                       style: StrokeStyle(lineWidth: max(0.5, stroke.width * scale),
                                          lineCap: .round, lineJoin: .round))
    }

    private func display(_ point: LeonardoInkPoint, in size: CGSize) -> CGPoint {
        let drawingWidth = min(size.width, size.height * 3)
        let drawingHeight = drawingWidth / 3
        let origin = CGPoint(x: (size.width - drawingWidth) / 2, y: (size.height - drawingHeight) / 2)
        return CGPoint(x: origin.x + point.x / LeonardoRubric.canvasWidth * drawingWidth,
                       y: origin.y + point.y / LeonardoRubric.canvasHeight * drawingHeight)
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
    @State private var failure: String?

    init(request: RubricRequest, library: MobileLibrary) {
        self.request = request
        self.library = library
        let draft = library.rubricDraft(requestID: request.id)
        _phase = State(initialValue: request.state == .accepted || draft != nil ? .drawing : .awaitingApproval)
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
                        drawingControls
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
                .disabled(frozen || phase == .sending)
            HStack {
                Picker("Color", selection: $color) {
                    colorOption("Negro", "#111111")
                    colorOption("Azul", "#1C5D99")
                    colorOption("Rojo", "#A52A2A")
                }
                .pickerStyle(.menu).disabled(frozen || phase == .sending)
                Picker("Trazo", selection: $style) {
                    Text("Sólido").tag(LeonardoInkStyle.solid)
                    Text("Pincel").tag(LeonardoInkStyle.brush)
                }
                .pickerStyle(.menu).disabled(frozen || phase == .sending)
            }
            HStack {
                Text("Ancho")
                Slider(value: $width, in: 0.5...12, step: 0.5)
                    .accessibilityLabel("Ancho del trazo")
                    .disabled(frozen || phase == .sending)
                Text(width, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit().frame(width: 34)
            }
            if showingPreview || frozen {
                MobileRubricPreview(rubric: rubric)
                    .accessibilityIdentifier("rubric-preview")
            } else {
                MobileRubricCanvas(rubric: $rubric, color: color, width: width, style: style,
                                   isInteractive: !frozen && phase != .sending)
                    .accessibilityIdentifier("rubric-canvas")
            }
            HStack {
                Button("Deshacer", systemImage: "arrow.uturn.backward") {
                    if !rubric.strokes.isEmpty { rubric.strokes.removeLast() }
                }
                .disabled(frozen || rubric.strokes.isEmpty || phase == .sending)
                .accessibilityIdentifier("rubric-undo")
                Button("Limpiar", systemImage: "trash") { rubric = LeonardoRubric() }
                    .disabled(frozen || rubric.strokes.isEmpty || phase == .sending)
                    .accessibilityIdentifier("rubric-clear")
                Spacer()
                Button(showingPreview || frozen ? "Dibujar" : "Vista previa",
                       systemImage: showingPreview || frozen ? "pencil" : "eye") {
                    if !frozen { showingPreview.toggle() }
                }
                .disabled(phase == .sending)
                .accessibilityIdentifier("rubric-preview-toggle")
            }
            if let draft = library.rubricDraft(requestID: request.id), draft.response != nil,
               draft.state != .blocked {
                Button("Reintentar envío", systemImage: "arrow.clockwise") { retry(draft) }
                    .buttonStyle(.borderedProminent).disabled(phase == .sending)
                    .accessibilityIdentifier("rubric-retry")
            } else if let draft = library.rubricDraft(requestID: request.id), draft.state == .blocked {
                Label("La solicitud ya no admite envíos (caducada, cancelada o revocada).",
                      systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Enviar rúbrica", systemImage: "paperplane.fill") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(frozen || phase == .sending || !rubric.isValid
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
            Text("El ordenador recibirá exactamente este dibujo para revisarlo.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Terminar") { dismiss() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("rubric-done")
        }
    }

    private func colorOption(_ title: String, _ value: String) -> some View {
        Text(title).tag(value)
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
        guard !frozen, phase == .drawing else { return }
        // An empty canvas is a valid unsent draft state. Persist it as nil so
        // Clear removes previously saved strokes without tripping payload validation.
        let savedDrawing = drawing.isValid ? drawing : nil
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
                frozen = library.rubricDraft(requestID: request.id)?.response != nil
                phase = .drawing
                failure = "No se pudo enviar. El dibujo está guardado y puedes reintentarlo."
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
}
