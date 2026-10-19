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

/// Presentation of a boolean form field; the stored answer remains a boolean.
public enum LeonardoFieldAppearance: String, Codable, CaseIterable, Sendable {
    case checkbox
    case `switch`
}

public struct LeonardoFieldDefinition: Codable, Equatable, Sendable {
    public var type: LeonardoFieldType
    public var appearance: LeonardoFieldAppearance?

    public var resolvedAppearance: LeonardoFieldAppearance { appearance ?? .checkbox }
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
    /// Optional user-facing text shown when the current value is invalid.
    public var validationMessage: String?
    public var defaultValue: LeonardoJSONValue?

    public init(
        type: LeonardoFieldType = .text,
        appearance: LeonardoFieldAppearance? = nil,
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
        validationMessage: String? = nil,
        defaultValue: LeonardoJSONValue? = nil
    ) {
        self.type = type
        self.appearance = appearance
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
        self.validationMessage = validationMessage
        self.defaultValue = defaultValue
    }

    private enum CodingKeys: String, CodingKey {
        case type, appearance, label, required, readOnly, minLength, maxLength, pattern
        case minimum, maximum, options, placeholder, helpText, validationMessage, defaultValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(LeonardoFieldType.self, forKey: .type) ?? .text
        appearance = try container.decodeIfPresent(LeonardoFieldAppearance.self, forKey: .appearance)
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
        validationMessage = try container.decodeIfPresent(String.self, forKey: .validationMessage)
        defaultValue = try container.decodeIfPresent(LeonardoJSONValue.self, forKey: .defaultValue)
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
    case missingMetadataKey(String)
    case unknownMetadataKey(String)
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
        case let .missingMetadataKey(path): return "The MDLF metadata is missing a required property: \(path)."
        case let .unknownMetadataKey(path): return "The MDLF v1 metadata contains an unknown property: \(path)."
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
