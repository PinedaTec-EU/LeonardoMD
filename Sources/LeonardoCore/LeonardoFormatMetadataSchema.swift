import Foundation

/// Checks the JSON object shape before it is decoded into the typed model.
///
/// `Codable` intentionally ignores unknown keys. That is useful for many
/// application payloads, but it would make a Leonardo save silently discard a
/// property it did not understand. MDLF v1 therefore has a closed structural
/// vocabulary. A future vocabulary must use a new `formatVersion`; arbitrary
/// JSON remains allowed inside `values` and `defaultValue`.
enum LeonardoFormatMetadataSchema {
    private enum ObjectKind {
        case root
        case document
        case field
        case option
        case layout
        case page
        case margins
        case background
        case position
        case dimension
        case size
        case image
        case table
        case column
    }

    static func validate(_ value: Any) throws {
        guard let root = value as? [String: Any] else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        try validateObject(root, kind: .root, path: "")
    }

    private static func validateObject(
        _ object: [String: Any],
        kind: ObjectKind,
        path: String
    ) throws {
        let allowed: Set<String>
        switch kind {
        case .root:
            allowed = ["format", "formatVersion", "document", "fields", "values", "layout"]
        case .document:
            allowed = ["id", "title", "kind", "revision", "locale"]
        case .field:
            allowed = [
                "type", "label", "required", "readOnly", "minLength", "maxLength",
                "pattern", "minimum", "maximum", "options", "placeholder", "helpText",
                "validationMessage", "defaultValue"
            ]
        case .option:
            allowed = ["value", "label"]
        case .layout:
            allowed = ["page", "background", "images", "tables"]
        case .page:
            allowed = ["size", "orientation", "widthPoints", "heightPoints", "margins"]
        case .margins:
            allowed = ["top", "right", "bottom", "left"]
        case .background:
            allowed = ["color", "image", "opacity", "fit", "position"]
        case .position:
            allowed = ["placement", "x", "y", "anchor"]
        case .dimension:
            allowed = ["value", "unit"]
        case .size:
            allowed = ["width", "height", "preserveAspectRatio"]
        case .image:
            allowed = ["source", "occurrence", "size", "position", "fit", "opacity"]
        case .table:
            allowed = ["occurrence", "width", "columns", "repeatHeader", "allowRowBreak"]
        case .column:
            allowed = ["width", "minimumWidth", "maximumWidth"]
        }

        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw LeonardoFormatError.unknownMetadataKey(propertyPath(path, unknown))
        }
        let required: Set<String>
        switch kind {
        case .field:
            required = ["type"]
        case .option:
            required = ["value"]
        case .dimension:
            required = ["value", "unit"]
        case .image:
            required = ["source"]
        case .table:
            required = ["occurrence"]
        default:
            required = []
        }
        if let missing = required.sorted().first(where: { object[$0] == nil || object[$0] is NSNull }) {
            throw LeonardoFormatError.missingMetadataKey(propertyPath(path, missing))
        }

        switch kind {
        case .root:
            try optionalObject(object["document"], kind: .document, path: propertyPath(path, "document"))
            if let fields = try optionalObjectDictionary(object["fields"], path: propertyPath(path, "fields")) {
                for key in fields.keys.sorted() {
                    try optionalObject(fields[key], kind: .field, path: propertyPath(propertyPath(path, "fields"), key))
                }
            }
            // `values` and field `defaultValue` are intentionally open JSON.
            _ = try optionalObjectDictionary(object["values"], path: propertyPath(path, "values"))
            try optionalObject(object["layout"], kind: .layout, path: propertyPath(path, "layout"))
        case .field:
            if let options = try optionalArray(object["options"], path: propertyPath(path, "options")) {
                for (index, option) in options.enumerated() {
                    try optionalObject(option, kind: .option, path: "\(propertyPath(path, "options"))[\(index)]")
                }
            }
        case .layout:
            try optionalObject(object["page"], kind: .page, path: propertyPath(path, "page"))
            try optionalObject(object["background"], kind: .background, path: propertyPath(path, "background"))
            if let images = try optionalArray(object["images"], path: propertyPath(path, "images")) {
                for (index, image) in images.enumerated() {
                    try optionalObject(image, kind: .image, path: "\(propertyPath(path, "images"))[\(index)]")
                }
            }
            if let tables = try optionalArray(object["tables"], path: propertyPath(path, "tables")) {
                for (index, table) in tables.enumerated() {
                    try optionalObject(table, kind: .table, path: "\(propertyPath(path, "tables"))[\(index)]")
                }
            }
        case .page:
            try optionalObject(object["margins"], kind: .margins, path: propertyPath(path, "margins"))
        case .background:
            try optionalObject(object["position"], kind: .position, path: propertyPath(path, "position"))
        case .position:
            try optionalObject(object["x"], kind: .dimension, path: propertyPath(path, "x"))
            try optionalObject(object["y"], kind: .dimension, path: propertyPath(path, "y"))
        case .size:
            try optionalObject(object["width"], kind: .dimension, path: propertyPath(path, "width"))
            try optionalObject(object["height"], kind: .dimension, path: propertyPath(path, "height"))
        case .image:
            try optionalObject(object["size"], kind: .size, path: propertyPath(path, "size"))
            try optionalObject(object["position"], kind: .position, path: propertyPath(path, "position"))
        case .table:
            try optionalObject(object["width"], kind: .dimension, path: propertyPath(path, "width"))
            if let columns = try optionalArray(object["columns"], path: propertyPath(path, "columns")) {
                for (index, column) in columns.enumerated() {
                    try optionalObject(column, kind: .column, path: "\(propertyPath(path, "columns"))[\(index)]")
                }
            }
        case .document, .option, .margins, .dimension, .column:
            break
        }
    }

    private static func optionalObject(
        _ value: Any?,
        kind: ObjectKind,
        path: String
    ) throws {
        guard let value else { return }
        guard !(value is NSNull) else { throw LeonardoFormatError.invalidMetadataJSON }
        guard let object = value as? [String: Any] else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        try validateObject(object, kind: kind, path: path)
    }

    private static func optionalObjectDictionary(
        _ value: Any?,
        path _: String
    ) throws -> [String: Any]? {
        guard let value else { return nil }
        guard !(value is NSNull) else { throw LeonardoFormatError.invalidMetadataJSON }
        guard let object = value as? [String: Any] else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        return object
    }

    private static func optionalArray(_ value: Any?, path _: String) throws -> [Any]? {
        guard let value else { return nil }
        guard !(value is NSNull) else { throw LeonardoFormatError.invalidMetadataJSON }
        guard let array = value as? [Any] else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        return array
    }

    private static func propertyPath(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }
}
