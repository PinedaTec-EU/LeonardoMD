import AppKit
import Foundation
import LeonardoCore
import Observation

struct SavedRubric: Codable, Identifiable {
    let id: String
    var label: String
    var rubric: LeonardoRubric
}

@MainActor @Observable
final class RubricLibrary {
    static let shared = RubricLibrary()
    private(set) var entries: [SavedRubric] = []
    private(set) var loadError: String?
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("LeonardoMD/Rubrics/library.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let decoded = try JSONDecoder().decode([SavedRubric].self, from: data)
            guard decoded.count <= 100, Set(decoded.map(\.id)).count == decoded.count,
                  decoded.allSatisfy({ $0.rubric.isValid && !$0.label.isEmpty && $0.label.count <= 120 }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            entries = decoded
        } catch { loadError = error.localizedDescription }
    }

    func add(label: String, rubric: LeonardoRubric) throws {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loadError == nil, entries.count < 100, rubric.isValid, !label.isEmpty, label.count <= 120 else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        try persist(entries + [SavedRubric(id: UUID().uuidString, label: label, rubric: rubric)])
    }

    func remove(id: String) throws { try persist(entries.filter { $0.id != id }) }

    private func persist(_ updated: [SavedRubric]) throws {
        guard loadError == nil else { throw CocoaError(.fileReadCorruptFile) }
        let data = try JSONEncoder().encode(updated)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        entries = updated
    }
}

struct RubricRequest: Identifiable {
    let id = UUID()
    let documentURL: URL?
    let source: String
    let fieldID: String?
    var savesToLibrary: Bool { fieldID == nil }
}

/// Drawing and menu thumbnails use the same tapered-segment geometry as the portable renderer.
enum RubricDrawing {
    static func draw(_ rubric: LeonardoRubric, in rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(scaleByX: rect.width / 600, byY: rect.height / 200)
        transform.concat()
        for stroke in rubric.strokes {
            let rgb = UInt32(stroke.color.dropFirst(), radix: 16) ?? 0
            NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                    blue: Double(rgb & 255) / 255, alpha: 1).setStroke()
            for (index, point) in stroke.points.enumerated() {
                let previous = stroke.points[max(0, index - 1)]
                let path = NSBezierPath(); path.lineWidth = stroke.segmentWidth(at: index); path.lineCapStyle = .round
                path.move(to: NSPoint(x: previous.x, y: previous.y))
                path.line(to: NSPoint(x: point.x + (previous == point ? 0.01 : 0), y: point.y)); path.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func thumbnail(_ rubric: LeonardoRubric) -> NSImage {
        NSImage(size: NSSize(width: 90, height: 30), flipped: true) { rect in
            NSColor.white.setFill(); rect.fill(); draw(rubric, in: rect); return true
        }
    }
}
