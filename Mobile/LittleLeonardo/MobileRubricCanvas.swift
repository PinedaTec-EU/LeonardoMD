import SwiftUI
import LeonardoCore

struct MobileRubricPreview: View {
    let rubric: LeonardoRubric
    var body: some View {
        MobileRubricCanvas(rubric: .constant(rubric), color: "#111111", width: 4,
                           style: .solid, isInteractive: false)
            .frame(maxWidth: .infinity).aspectRatio(3, contentMode: .fit)
            .background(MobileClassic.canvas).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MobileClassic.border))
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
            .background(MobileClassic.canvas)
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
            }.onEnded { _ in commitLiveStroke() })
            // Points are already in portable coordinates. Commit an active
            // stroke before the old canvas disappears during a layout change.
            .onChange(of: geometry.size) { _, _ in commitLiveStroke() }
            .onDisappear { commitLiveStroke() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lienzo de rúbrica")
        .accessibilityValue("\(rubric.strokes.count) trazos")
        .accessibilityAddTraits(isInteractive ? .allowsDirectInteraction : [])
    }

    private func commitLiveStroke() {
        guard isInteractive, !livePoints.isEmpty else { livePoints.removeAll(); return }
        let points = livePoints
        livePoints.removeAll()
        let pointCount = rubric.strokes.reduce(0) { $0 + $1.points.count }
        guard rubric.strokes.count < LeonardoRubric.maximumStrokes,
              pointCount + points.count <= Self.maximumPoints else {
            limitReached = true
            return
        }
        var candidate = rubric
        candidate.strokes.append(LeonardoInkStroke(color: color, width: width, style: style, points: points))
        guard canCommit(candidate) else { limitReached = true; return }
        rubric = candidate
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
