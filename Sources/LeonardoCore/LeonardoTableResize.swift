import Foundation

/// Preview geometry in typographic points (CSS px × 72/96). A commit carries
/// the exact table source as well as its occurrence to reject stale layout.
public struct LeonardoTableResize: Codable, Sendable {
    public var occurrence: Int
    public var source: String
    public var widths: [Double]
    public var heights: [Double]

    public init(occurrence: Int, source: String, widths: [Double], heights: [Double]) {
        self.occurrence = occurrence; self.source = source
        self.widths = widths; self.heights = heights
    }

    public func applying(to original: LeonardoDocument) throws -> LeonardoDocument {
        let dimensions = widths + heights
        guard occurrence > 0, !source.isEmpty, !widths.isEmpty, !heights.isEmpty,
              dimensions.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10_000 }),
              widths.reduce(0, +) <= 10_000, heights.reduce(0, +) <= 10_000 else {
            throw LeonardoTableResizeError.invalidGeometry
        }
        var document = original
        var layout = document.metadata.layout ?? LeonardoLayout()
        let index = layout.tables.firstIndex { $0.occurrence == occurrence }
        var table = index.map { layout.tables[$0] } ?? LeonardoTableLayout(occurrence: occurrence)
        table.source = source
        table.width = LeonardoDimension(value: widths.reduce(0, +), unit: .points)
        table.height = LeonardoDimension(value: heights.reduce(0, +), unit: .points)
        table.rowHeights = heights
        table.columns = widths.enumerated().map { offset, width in
            var column = offset < table.columns.count ? table.columns[offset] : LeonardoTableColumnLayout()
            column.width = LeonardoDimension(value: width, unit: .points)
            return column
        }
        if let index { layout.tables[index] = table } else { layout.tables.append(table) }
        document.metadata.layout = layout
        // Serialization applies the same schema and semantic gates as loading.
        _ = try LeonardoFormatParser.serialize(document)
        return document
    }
}

public enum LeonardoTableResizeError: LocalizedError {
    case invalidGeometry
    public var errorDescription: String? { "Table dimensions must be positive and total at most 10000 points per axis." }
}
