import Foundation

public enum LeonardoDimensionUnit: String, Codable, CaseIterable, Sendable {
    case points
    case percent
}

public struct LeonardoDimension: Codable, Equatable, Sendable {
    public var value: Double
    public var unit: LeonardoDimensionUnit

    public init(value: Double, unit: LeonardoDimensionUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum LeonardoPlacement: String, Codable, CaseIterable, Sendable {
    case flow
    case relative
    case absolute
}

public enum LeonardoAnchor: String, Codable, CaseIterable, Sendable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing
}

public struct LeonardoPosition: Codable, Equatable, Sendable {
    public var placement: LeonardoPlacement
    public var x: LeonardoDimension?
    public var y: LeonardoDimension?
    public var anchor: LeonardoAnchor

    public init(
        placement: LeonardoPlacement = .flow,
        x: LeonardoDimension? = nil,
        y: LeonardoDimension? = nil,
        anchor: LeonardoAnchor = .topLeading
    ) {
        self.placement = placement
        self.x = x
        self.y = y
        self.anchor = anchor
    }

    private enum CodingKeys: String, CodingKey { case placement, x, y, anchor }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placement = try container.decodeIfPresent(LeonardoPlacement.self, forKey: .placement) ?? .flow
        x = try container.decodeIfPresent(LeonardoDimension.self, forKey: .x)
        y = try container.decodeIfPresent(LeonardoDimension.self, forKey: .y)
        anchor = try container.decodeIfPresent(LeonardoAnchor.self, forKey: .anchor) ?? .topLeading
    }
}

public struct LeonardoSize: Codable, Equatable, Sendable {
    public var width: LeonardoDimension?
    public var height: LeonardoDimension?
    public var preserveAspectRatio: Bool

    public init(
        width: LeonardoDimension? = nil,
        height: LeonardoDimension? = nil,
        preserveAspectRatio: Bool = true
    ) {
        self.width = width
        self.height = height
        self.preserveAspectRatio = preserveAspectRatio
    }

    private enum CodingKeys: String, CodingKey { case width, height, preserveAspectRatio }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(LeonardoDimension.self, forKey: .width)
        height = try container.decodeIfPresent(LeonardoDimension.self, forKey: .height)
        preserveAspectRatio = try container.decodeIfPresent(Bool.self, forKey: .preserveAspectRatio) ?? true
    }
}

public enum LeonardoImageFit: String, Codable, CaseIterable, Sendable {
    case contain
    case cover
    case fill
    case none
}

public struct LeonardoBackground: Codable, Equatable, Sendable {
    public var color: String?
    public var image: String?
    public var opacity: Double
    public var fit: LeonardoImageFit
    public var position: LeonardoPosition

    public init(
        color: String? = nil,
        image: String? = nil,
        opacity: Double = 1,
        fit: LeonardoImageFit = .cover,
        position: LeonardoPosition = LeonardoPosition()
    ) {
        self.color = color
        self.image = image
        self.opacity = opacity
        self.fit = fit
        self.position = position
    }

    private enum CodingKeys: String, CodingKey { case color, image, opacity, fit, position }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        fit = try container.decodeIfPresent(LeonardoImageFit.self, forKey: .fit) ?? .cover
        position = try container.decodeIfPresent(LeonardoPosition.self, forKey: .position) ?? LeonardoPosition()
    }
}

public enum LeonardoPageSize: String, Codable, CaseIterable, Sendable {
    case a4
    case letter
    case custom
}

public enum LeonardoPageOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

public struct LeonardoMargins: Codable, Equatable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double = 36, right: Double = 36, bottom: Double = 36, left: Double = 36) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    private enum CodingKeys: String, CodingKey { case top, right, bottom, left }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        top = try container.decodeIfPresent(Double.self, forKey: .top) ?? 36
        right = try container.decodeIfPresent(Double.self, forKey: .right) ?? 36
        bottom = try container.decodeIfPresent(Double.self, forKey: .bottom) ?? 36
        left = try container.decodeIfPresent(Double.self, forKey: .left) ?? 36
    }
}

public struct LeonardoPageLayout: Codable, Equatable, Sendable {
    public var size: LeonardoPageSize
    public var orientation: LeonardoPageOrientation
    public var widthPoints: Double?
    public var heightPoints: Double?
    public var margins: LeonardoMargins

    public init(
        size: LeonardoPageSize = .a4,
        orientation: LeonardoPageOrientation = .portrait,
        widthPoints: Double? = nil,
        heightPoints: Double? = nil,
        margins: LeonardoMargins = LeonardoMargins()
    ) {
        self.size = size
        self.orientation = orientation
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.margins = margins
    }

    private enum CodingKeys: String, CodingKey { case size, orientation, widthPoints, heightPoints, margins }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(LeonardoPageSize.self, forKey: .size) ?? .a4
        orientation = try container.decodeIfPresent(LeonardoPageOrientation.self, forKey: .orientation) ?? .portrait
        widthPoints = try container.decodeIfPresent(Double.self, forKey: .widthPoints)
        heightPoints = try container.decodeIfPresent(Double.self, forKey: .heightPoints)
        margins = try container.decodeIfPresent(LeonardoMargins.self, forKey: .margins) ?? LeonardoMargins()
    }
}

public struct LeonardoImageLayout: Codable, Equatable, Sendable {
    /// Relative asset path or URL exactly as used by the matching Markdown image.
    public var source: String
    /// One-based occurrence for repeated images with the same source.
    public var occurrence: Int
    public var size: LeonardoSize
    public var position: LeonardoPosition
    public var fit: LeonardoImageFit
    public var opacity: Double

    public init(
        source: String,
        occurrence: Int = 1,
        size: LeonardoSize = LeonardoSize(),
        position: LeonardoPosition = LeonardoPosition(),
        fit: LeonardoImageFit = .contain,
        opacity: Double = 1
    ) {
        self.source = source
        self.occurrence = occurrence
        self.size = size
        self.position = position
        self.fit = fit
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey { case source, occurrence, size, position, fit, opacity }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        occurrence = try container.decodeIfPresent(Int.self, forKey: .occurrence) ?? 1
        size = try container.decodeIfPresent(LeonardoSize.self, forKey: .size) ?? LeonardoSize()
        position = try container.decodeIfPresent(LeonardoPosition.self, forKey: .position) ?? LeonardoPosition()
        fit = try container.decodeIfPresent(LeonardoImageFit.self, forKey: .fit) ?? .contain
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }
}

public struct LeonardoTableColumnLayout: Codable, Equatable, Sendable {
    public var width: LeonardoDimension?
    public var minimumWidth: LeonardoDimension?
    public var maximumWidth: LeonardoDimension?

    public init(
        width: LeonardoDimension? = nil,
        minimumWidth: LeonardoDimension? = nil,
        maximumWidth: LeonardoDimension? = nil
    ) {
        self.width = width
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
    }

    private enum CodingKeys: String, CodingKey { case width, minimumWidth, maximumWidth }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(LeonardoDimension.self, forKey: .width)
        minimumWidth = try container.decodeIfPresent(LeonardoDimension.self, forKey: .minimumWidth)
        maximumWidth = try container.decodeIfPresent(LeonardoDimension.self, forKey: .maximumWidth)
    }
}

public struct LeonardoTableLayout: Codable, Equatable, Sendable {
    /// One-based occurrence in document order. This avoids non-standard table
    /// comments and remains deterministic for any Markdown parser.
    public var occurrence: Int
    public var width: LeonardoDimension?
    public var columns: [LeonardoTableColumnLayout]
    public var repeatHeader: Bool
    public var allowRowBreak: Bool

    public init(
        occurrence: Int,
        width: LeonardoDimension? = nil,
        columns: [LeonardoTableColumnLayout] = [],
        repeatHeader: Bool = true,
        allowRowBreak: Bool = true
    ) {
        self.occurrence = occurrence
        self.width = width
        self.columns = columns
        self.repeatHeader = repeatHeader
        self.allowRowBreak = allowRowBreak
    }

    private enum CodingKeys: String, CodingKey { case occurrence, width, columns, repeatHeader, allowRowBreak }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occurrence = try container.decodeIfPresent(Int.self, forKey: .occurrence) ?? 1
        width = try container.decodeIfPresent(LeonardoDimension.self, forKey: .width)
        columns = try container.decodeIfPresent([LeonardoTableColumnLayout].self, forKey: .columns) ?? []
        repeatHeader = try container.decodeIfPresent(Bool.self, forKey: .repeatHeader) ?? true
        allowRowBreak = try container.decodeIfPresent(Bool.self, forKey: .allowRowBreak) ?? true
    }
}

public struct LeonardoLayout: Codable, Equatable, Sendable {
    public var page: LeonardoPageLayout?
    public var background: LeonardoBackground?
    public var images: [LeonardoImageLayout]
    public var tables: [LeonardoTableLayout]

    public init(
        page: LeonardoPageLayout? = nil,
        background: LeonardoBackground? = nil,
        images: [LeonardoImageLayout] = [],
        tables: [LeonardoTableLayout] = []
    ) {
        self.page = page
        self.background = background
        self.images = images
        self.tables = tables
    }

    private enum CodingKeys: String, CodingKey { case page, background, images, tables }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeIfPresent(LeonardoPageLayout.self, forKey: .page)
        background = try container.decodeIfPresent(LeonardoBackground.self, forKey: .background)
        images = try container.decodeIfPresent([LeonardoImageLayout].self, forKey: .images) ?? []
        tables = try container.decodeIfPresent([LeonardoTableLayout].self, forKey: .tables) ?? []
    }
}
