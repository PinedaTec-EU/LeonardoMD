import Foundation

/// Applies the versioned MDLF JSON Schema to metadata before it is decoded or
/// written. The schema is a packaged resource so the native reader, the
/// plugin and external agents all consume the same vocabulary and bounds.
enum LeonardoFormatMetadataSchema {
    static func validate(_ value: Any) throws {
        let version = (value as? [String: Any])?["formatVersion"] as? Int
        do {
            try LeonardoJSONSchemaEvaluator.validate(value: value, schemaData: bundledSchemaData(for: version))
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
        try bundledSchemaData(for: LeonardoFormat.legacyVersion)
    }

    /// Returns the schema for a concrete wire-format version. Keeping the
    /// version in the resource name prevents a v2 signing document from being
    /// accidentally validated with the legacy v1 vocabulary.
    static func bundledSchemaData(for version: Int?) throws -> Data {
        guard let version,
              LeonardoFormat.supportedVersions.contains(version),
              let url = Bundle.module.url(forResource: "mdlf-v\(version).schema", withExtension: "json") else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LeonardoFormatError.invalidMetadataJSON
        }
    }
}
