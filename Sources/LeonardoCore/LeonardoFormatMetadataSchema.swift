import Foundation

/// Applies the versioned MDLF JSON Schema to metadata before it is decoded or
/// written. The schema is a packaged resource so the native reader, the
/// plugin and external agents all consume the same vocabulary and bounds.
enum LeonardoFormatMetadataSchema {
    static func validate(_ value: Any) throws {
        do {
            try LeonardoJSONSchemaEvaluator.validate(value: value, schemaData: bundledSchemaData())
        } catch let error as LeonardoJSONSchemaFailure {
            switch error {
            case let .violation(path, kind):
                switch kind {
                case .missing:
                    throw LeonardoFormatError.missingMetadataKey(path)
                case .unknownProperty, .propertyName:
                    throw LeonardoFormatError.unknownMetadataKey(path)
                case .constraint:
                    throw LeonardoFormatError.invalidMetadataJSON
                }
            case .unsupportedSchema:
                throw LeonardoFormatError.invalidMetadataJSON
            }
        } catch {
            throw LeonardoFormatError.invalidMetadataJSON
        }
    }

    /// Validates the canonical encoder output. This closes the gap between
    /// parsed JSON and programmatically-created documents before serialization.
    static func validate(_ metadata: LeonardoMetadata) throws {
        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(metadata)
        } catch let error as LeonardoFormatError {
            throw error
        } catch {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        try validate(value)
    }

    /// Internal test hook used to compare the Core resource with the
    /// repository and plugin copies byte-for-byte.
    static func bundledSchemaData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "mdlf-v1.schema", withExtension: "json") else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LeonardoFormatError.invalidMetadataJSON
        }
    }
}
