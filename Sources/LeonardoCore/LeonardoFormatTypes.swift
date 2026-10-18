import Foundation

/// The canonical identifier embedded in an MDLF/MDLR document.
public enum LeonardoFormat {
    public static let identifier = "mdlf"
    public static let currentVersion = 1
    public static let fieldTokenPrefix = "{{field:"
    public static let fieldTokenSuffix = "}}"
}

public enum LeonardoDocumentKind: String, Codable, CaseIterable, Sendable {
    case document
    case form
}

public struct LeonardoDocumentDescriptor: Codable, Equatable, Sendable {
    public var id: String?
    public var title: String?
    public var kind: LeonardoDocumentKind
    /// A semantic revision of the author's template. This is independent of
    /// the wire format version and is useful when a response is compared with
    /// a later revision of the same form.
    public var revision: Int?
    public var locale: String?

    public init(
        id: String? = nil,
        title: String? = nil,
        kind: LeonardoDocumentKind = .document,
        revision: Int? = nil,
        locale: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.revision = revision
        self.locale = locale
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, revision, locale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        kind = try container.decodeIfPresent(LeonardoDocumentKind.self, forKey: .kind) ?? .document
        revision = try container.decodeIfPresent(Int.self, forKey: .revision)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
    }
}

public enum LeonardoFieldType: String, Codable, CaseIterable, Sendable {
    case text
    case multiline
    case number
    case date
    case checkbox
    case select
    case email
    case url
}

public struct LeonardoFieldOption: Codable, Equatable, Sendable {
    public var value: String
    public var label: String?

    public init(value: String, label: String? = nil) {
        self.value = value
        self.label = label
    }
}

/// A JSON value is used for form data so agents and non-Leonardo editors do
/// not need a private string encoding for booleans and numbers.
public enum LeonardoJSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([LeonardoJSONValue])
    case object([String: LeonardoJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite else { throw LeonardoFormatError.nonFiniteNumber }
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([LeonardoJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: LeonardoJSONValue].self) {
            self = .object(value)
        } else {
            throw LeonardoFormatError.invalidJSONValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .boolean(value):
            try container.encode(value)
        case let .number(value):
            guard value.isFinite else { throw LeonardoFormatError.nonFiniteNumber }
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    public var booleanValue: Bool? {
        guard case let .boolean(value) = self else { return nil }
        return value
    }

    public var isNullOrEmpty: Bool {
        switch self {
        case .null: return true
        case let .string(value): return value.isEmpty
        case let .array(value): return value.isEmpty
        case let .object(value): return value.isEmpty
        case .boolean, .number: return false
        }
    }
}

public struct LeonardoFieldDefinition: Codable, Equatable, Sendable {
    public var type: LeonardoFieldType
    public var label: String?
    public var required: Bool
    public var readOnly: Bool
    public var minLength: Int?
    public var maxLength: Int?
    public var pattern: String?
    public var minimum: Double?
    public var maximum: Double?
    public var options: [LeonardoFieldOption]
    public var placeholder: String?
    public var helpText: String?
    public var defaultValue: LeonardoJSONValue?

    public init(
        type: LeonardoFieldType = .text,
        label: String? = nil,
        required: Bool = false,
        readOnly: Bool = false,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        options: [LeonardoFieldOption] = [],
        placeholder: String? = nil,
        helpText: String? = nil,
        defaultValue: LeonardoJSONValue? = nil
    ) {
        self.type = type
        self.label = label
        self.required = required
        self.readOnly = readOnly
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.options = options
        self.placeholder = placeholder
        self.helpText = helpText
        self.defaultValue = defaultValue
    }

    private enum CodingKeys: String, CodingKey {
        case type, label, required, readOnly, minLength, maxLength, pattern
        case minimum, maximum, options, placeholder, helpText, defaultValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(LeonardoFieldType.self, forKey: .type) ?? .text
        label = try container.decodeIfPresent(String.self, forKey: .label)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
        maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        options = try container.decodeIfPresent([LeonardoFieldOption].self, forKey: .options) ?? []
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        helpText = try container.decodeIfPresent(String.self, forKey: .helpText)
        defaultValue = try container.decodeIfPresent(LeonardoJSONValue.self, forKey: .defaultValue)
    }
}

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

public struct LeonardoMetadata: Codable, Equatable, Sendable {
    public var format: String
    public var formatVersion: Int
    public var document: LeonardoDocumentDescriptor
    public var fields: [String: LeonardoFieldDefinition]
    public var values: [String: LeonardoJSONValue]
    public var layout: LeonardoLayout?

    public init(
        format: String = LeonardoFormat.identifier,
        formatVersion: Int = LeonardoFormat.currentVersion,
        document: LeonardoDocumentDescriptor = LeonardoDocumentDescriptor(),
        fields: [String: LeonardoFieldDefinition] = [:],
        values: [String: LeonardoJSONValue] = [:],
        layout: LeonardoLayout? = nil
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.document = document
        self.fields = fields
        self.values = values
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case format, formatVersion, document, fields, values, layout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? LeonardoFormat.identifier
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? LeonardoFormat.currentVersion
        document = try container.decodeIfPresent(LeonardoDocumentDescriptor.self, forKey: .document) ?? LeonardoDocumentDescriptor()
        fields = try container.decodeIfPresent([String: LeonardoFieldDefinition].self, forKey: .fields) ?? [:]
        values = try container.decodeIfPresent([String: LeonardoJSONValue].self, forKey: .values) ?? [:]
        layout = try container.decodeIfPresent(LeonardoLayout.self, forKey: .layout)
    }
}

public struct LeonardoDocument: Equatable, Sendable {
    public var body: String
    public var metadata: LeonardoMetadata

    public init(body: String, metadata: LeonardoMetadata = LeonardoMetadata()) {
        self.body = body
        self.metadata = metadata
    }

    public var isForm: Bool { metadata.document.kind == .form || !metadata.fields.isEmpty }
}

public enum LeonardoFileModeHint: String, Codable, CaseIterable, Sendable {
    case edit
    case fill
}

public enum LeonardoFormatDetection: Equatable, Sendable {
    case markdown
    case leonardo(version: Int)
    case malformedLeonardo
}

public enum LeonardoFormatError: Error, Equatable, Sendable {
    case missingFrontMatter
    case invalidFrontMatter
    case invalidMetadataJSON
    case missingFormatIdentifier
    case missingFormatVersion
    case unsupportedVersion(Int)
    case nonFiniteNumber
    case invalidJSONValue
}

extension LeonardoFormatError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingFrontMatter: return "The document does not contain MDLF front matter."
        case .invalidFrontMatter: return "The MDLF front matter delimiters are invalid."
        case .invalidMetadataJSON: return "The MDLF metadata is not valid JSON."
        case .missingFormatIdentifier: return "The MDLF metadata does not identify the mdlf format."
        case .missingFormatVersion: return "The MDLF metadata must declare formatVersion."
        case let .unsupportedVersion(version): return "The MDLF format version \(version) is not supported."
        case .nonFiniteNumber: return "MDLF JSON numbers must be finite."
        case .invalidJSONValue: return "The MDLF metadata contains an unsupported JSON value."
        }
    }
}

public enum LeonardoDiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case warning
    case error
}

public struct LeonardoDiagnostic: Equatable, Sendable {
    public var severity: LeonardoDiagnosticSeverity
    public var code: String
    public var message: String
    public var fieldID: String?

    public init(
        severity: LeonardoDiagnosticSeverity,
        code: String,
        message: String,
        fieldID: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.fieldID = fieldID
    }
}

public enum LeonardoValidationContext: Sendable {
    case draft
    case submission
}
