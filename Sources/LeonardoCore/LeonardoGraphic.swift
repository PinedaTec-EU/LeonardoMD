import Foundation

/// Page-space geometry, in physical points; array order is the stable Z tie-breaker.
public struct LeonardoGraphic: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var source: String?
    public var rubric: LeonardoRubric?
    public var page: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var z: Int

    public init(id: String = UUID().uuidString, label: String, source: String? = nil,
                rubric: LeonardoRubric? = nil, page: Int = 1, x: Double = 36, y: Double = 36,
                width: Double = 180, height: Double = 70, z: Int = 1) {
        self.id = id; self.label = label; self.source = source; self.rubric = rubric
        self.page = page; self.x = x; self.y = y; self.width = width; self.height = height; self.z = z
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 128 && !label.isEmpty && label.count <= 120
        && (1...999).contains(page) && (-10000...10000).contains(z)
        && [x, y, width, height].allSatisfy { $0.isFinite && abs($0) <= 10000 }
        && width > 0 && height > 0
        && ((source != nil && rubric == nil) || (source == nil && rubric?.isValid == true))
    }
}

public struct LeonardoInkPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum LeonardoInkStyle: String, Codable, CaseIterable, Sendable { case solid, brush }

public struct LeonardoInkStroke: Codable, Equatable, Sendable {
    public var color: String
    public var width: Double
    public var style: LeonardoInkStyle
    public var points: [LeonardoInkPoint]
    public init(color: String, width: Double, style: LeonardoInkStyle, points: [LeonardoInkPoint]) {
        self.color = color; self.width = width; self.style = style; self.points = points
    }
    public func segmentWidth(at index: Int) -> Double {
        guard style == .brush else { return width }
        let fraction = Double(index) / Double(max(1, points.count - 1))
        return width * max(0.08, sin(.pi * fraction))
    }
}

/// Normalized canvas coordinates (600 × 200), deliberately independent of Apple APIs.
public struct LeonardoRubric: Codable, Equatable, Sendable {
    public static let canvasWidth = 600.0
    public static let canvasHeight = 200.0
    public static let maximumStrokes = 256
    public static let maximumPoints = 20_000
    public var strokes: [LeonardoInkStroke]
    public init(strokes: [LeonardoInkStroke] = []) { self.strokes = strokes }
    public var isValid: Bool {
        !strokes.isEmpty && strokes.count <= Self.maximumStrokes
        && strokes.reduce(0, { $0 + $1.points.count }) <= Self.maximumPoints
        && strokes.allSatisfy { stroke in
            stroke.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
            && stroke.width.isFinite && stroke.width >= 0.5 && stroke.width <= 24
            && !stroke.points.isEmpty && stroke.points.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && (0...Self.canvasWidth).contains($0.x)
                && (0...Self.canvasHeight).contains($0.y)
            }
        }
    }
    public var jsonValue: LeonardoJSONValue? {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(LeonardoJSONValue.self, from: data)
    }
    public static func decode(_ value: LeonardoJSONValue?) -> Self? {
        guard let value, let data = try? JSONEncoder().encode(value),
              let result = try? JSONDecoder().decode(Self.self, from: data), result.isValid else { return nil }
        return result
    }
}
