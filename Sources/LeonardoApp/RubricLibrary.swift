import AppKit
import Foundation
import LeonardoCore
import Observation
import OSLog

struct SavedRubric: Codable, Identifiable {
    let id: String
    var label: String
    var rubric: LeonardoRubric
    let sourceRequestID: UUID?

    init(id: String, label: String, rubric: LeonardoRubric, sourceRequestID: UUID? = nil) {
        self.id = id; self.label = label; self.rubric = rubric; self.sourceRequestID = sourceRequestID
    }

    private enum CodingKeys: String, CodingKey { case id, label, rubric, sourceRequestID }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(String.self, forKey: .id),
                  label: try container.decode(String.self, forKey: .label),
                  rubric: try container.decode(LeonardoRubric.self, forKey: .rubric),
                  sourceRequestID: try container.decodeIfPresent(UUID.self, forKey: .sourceRequestID))
    }
}

@MainActor @Observable
final class RubricLibrary {
    static let shared = RubricLibrary()
    private(set) var entries: [SavedRubric] = []
    private(set) var loadError: String?
    private let url: URL
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "rubric-library")

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("LeonardoMD/Rubrics/library.json")) {
        self.url = url
        refresh()
    }

    func refresh() {
        do { entries = try readCurrent(); loadError = nil }
        catch { loadError = error.localizedDescription }
    }

    private func readCurrent() throws -> [SavedRubric] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let decoded = try JSONDecoder().decode([SavedRubric].self, from: data)
        let sourceIDs = decoded.compactMap(\.sourceRequestID)
        guard decoded.count <= 100, Set(decoded.map(\.id)).count == decoded.count,
              Set(sourceIDs).count == sourceIDs.count,
              decoded.allSatisfy({ $0.rubric.isValid && !$0.label.isEmpty && $0.label.count <= 120 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return decoded
    }

    @discardableResult
    func add(label: String, rubric: LeonardoRubric, sourceRequestID: UUID? = nil) throws -> SavedRubric {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rubric.isValid, !label.isEmpty, label.count <= 120 else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        var result: SavedRubric?
        try update { current in
            if let sourceRequestID, let index = current.firstIndex(where: { $0.sourceRequestID == sourceRequestID }) {
                let existing = current[index]
                let updated = SavedRubric(id: existing.id, label: label, rubric: rubric,
                                          sourceRequestID: sourceRequestID)
                result = updated
                var next = current; next[index] = updated
                return next
            }
            guard current.count < 100 else { throw CocoaError(.fileWriteOutOfSpace) }
            let added = SavedRubric(id: UUID().uuidString, label: label, rubric: rubric,
                                    sourceRequestID: sourceRequestID)
            result = added
            return current + [added]
        }
        guard let result else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    func remove(id: String) throws { try update { $0.filter { $0.id != id } } }

    private func update(_ change: ([SavedRubric]) throws -> [SavedRubric]) throws {
        // A stable, nonblocking sidecar lock coordinates atomically replaced JSON
        // across app instances without waiting on the main actor.
        let lock = try ProcessFileLock(at: ProcessFileLock.coordinationDirectory
            .appendingPathComponent(ProcessFileLock.key(for: url) + ".rubrics"))
        try withExtendedLifetime(lock) {
            let updated = try change(readCurrent())
            try persist(updated)
        }
    }

    private func persist(_ updated: [SavedRubric]) throws {
        let data = try JSONEncoder().encode(updated)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        entries = updated
        loadError = nil
        logger.info("Persisted rubric library entries=\(updated.count, privacy: .public)")
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
        NSGraphicsContext.current?.cgContext.scaleBy(x: rect.width / 600, y: rect.height / 200)
        for stroke in rubric.strokes {
            color(stroke.color).setStroke()
            for (index, point) in stroke.points.enumerated() {
                let previous = stroke.points[max(0, index - 1)]
                let path = NSBezierPath(); path.lineWidth = stroke.segmentWidth(at: index); path.lineCapStyle = .round
                path.move(to: NSPoint(x: previous.x, y: previous.y))
                path.line(to: NSPoint(x: point.x + (previous == point ? 0.01 : 0), y: point.y)); path.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func color(_ hex: String) -> NSColor {
        let rgb = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                       blue: Double(rgb & 255) / 255, alpha: 1)
    }
    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
    static func inspectorPreview(_ rubric: LeonardoRubric) -> NSImage {
        NSImage(size: NSSize(width: 600, height: 200), flipped: true) { rect in
            for y in stride(from: 0, to: 200, by: 20) {
                for x in stride(from: 0, to: 600, by: 20) {
                    NSColor(white: (x + y) % 40 == 0 ? 0.65 : 0.85, alpha: 1).setFill()
                    NSRect(x: x, y: y, width: 20, height: 20).fill()
                }
            }
            draw(rubric, in: rect); return true
        }
    }
    static func thumbnail(_ rubric: LeonardoRubric) -> NSImage {
        NSImage(size: NSSize(width: 90, height: 30), flipped: true) { rect in
            NSColor.white.setFill(); rect.fill(); draw(rubric, in: rect); return true
        }
    }
}
