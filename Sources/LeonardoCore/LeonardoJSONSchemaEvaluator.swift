import Foundation
import CoreFoundation

enum LeonardoJSONSchemaFailure: Error {
    enum Kind {
        case constraint
        case missing
        case unknownProperty
        case propertyName
    }

    case unsupportedSchema(String)
    case violation(path: String, Kind)
}

/// A deliberately small, closed evaluator for the JSON Schema vocabulary used
/// by MDLF. It is data-driven: MDLF property names, types and bounds live in
/// `mdlf-v1.schema.json`, not in this evaluator.
struct LeonardoJSONSchemaEvaluator {
    private static let assertionKeywords: Set<String> = [
        "$defs", "$ref", "additionalProperties", "const", "enum", "items",
        "maxLength", "maximum", "minLength", "minimum", "pattern", "properties",
        "propertyNames", "required", "type"
    ]
    private static let annotationKeywords: Set<String> = [
        "$comment", "$id", "$schema", "default", "deprecated", "description",
        "examples", "readOnly", "title", "writeOnly"
    ]
    private static let allowedTypes: Set<String> = [
        "array", "boolean", "integer", "null", "number", "object", "string"
    ]

    static func validate(value: Any, schemaData: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: schemaData),
              let rootObject = root as? [String: Any] else {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("schema root is not an object")
        }
        let evaluator = Self(root: rootObject)
        try evaluator.validateSchema(rootObject, location: "$")
        try evaluator.validateValue(value, schema: rootObject, path: "")
    }

    private let root: [String: Any]

    private init(root: [String: Any]) {
        self.root = root
    }

    private func validateSchema(_ schema: Any, location: String) throws {
        if schema is Bool { return }
        guard let object = schema as? [String: Any] else {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): schema must be an object or boolean")
        }

        let allowed = Self.assertionKeywords.union(Self.annotationKeywords)
        let unknown = object.keys.filter { !allowed.contains($0) }.sorted()
        if let first = unknown.first {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): unsupported keyword \(first)")
        }

        if let type = object["type"] {
            let names: [String]
            if let name = type as? String {
                names = [name]
            } else if let array = type as? [Any], !array.isEmpty,
                      array.allSatisfy({ $0 is String }) {
                names = array.compactMap { $0 as? String }
            } else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): invalid type assertion")
            }
            guard names.allSatisfy(Self.allowedTypes.contains) else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): unsupported type assertion")
            }
        }

        if let required = object["required"] {
            guard let array = required as? [Any], array.allSatisfy({ $0 is String }) else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): required must be an array of strings")
            }
            let names = array.compactMap { $0 as? String }
            guard Set(names).count == names.count else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): required contains duplicate property names")
            }
        }

        if let properties = object["properties"] {
            guard let properties = properties as? [String: Any] else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): properties must be an object")
            }
            for name in properties.keys.sorted() {
                guard let child = properties[name] else {
                    throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): missing property schema")
                }
                try validateSchema(child, location: "\(location).properties[\(name)]")
            }
        }

        if let definitions = object["$defs"] {
            guard let definitions = definitions as? [String: Any] else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): $defs must be an object")
            }
            for name in definitions.keys.sorted() {
                guard let child = definitions[name] else {
                    throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): missing definition schema")
                }
                try validateSchema(child, location: "\(location).$defs[\(name)]")
            }
        }

        if let propertyNames = object["propertyNames"] {
            try validateSchema(propertyNames, location: "\(location).propertyNames")
        }
        if let items = object["items"] {
            try validateSchema(items, location: "\(location).items")
        }
        if let additional = object["additionalProperties"], !(additional is Bool) {
            try validateSchema(additional, location: "\(location).additionalProperties")
        }

        if let reference = object["$ref"] {
            _ = try resolve(reference)
        }
        if let enumValues = object["enum"], !(enumValues is [Any]) {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): enum must be an array")
        }
        if let pattern = object["pattern"] {
            guard let pattern = pattern as? String,
                  (try? NSRegularExpression(pattern: pattern)) != nil else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): invalid regular expression")
            }
        }
        for key in ["minLength", "maxLength"] {
            if let value = object[key], !isNonNegativeInteger(value) {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): \(key) must be a non-negative integer")
            }
        }
        for key in ["minimum", "maximum"] {
            if let value = object[key], !isFiniteNumber(value) {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("\(location): \(key) must be a finite number")
            }
        }
    }

    private func validateValue(_ value: Any, schema: Any, path: String) throws {
        if let boolean = schema as? Bool {
            if !boolean {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
            return
        }
        guard let object = schema as? [String: Any] else {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("schema must be an object or boolean")
        }

        if let reference = object["$ref"] {
            try validateValue(value, schema: try resolve(reference), path: path)
        }

        if let type = object["type"] {
            let names: [String]
            if let name = type as? String {
                names = [name]
            } else if let array = type as? [Any] {
                names = array.compactMap { $0 as? String }
            } else {
                throw LeonardoJSONSchemaFailure.unsupportedSchema("invalid type assertion")
            }
            guard names.contains(where: { matchesType(value, name: $0) }) else {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
        }

        if let constant = object["const"], !jsonEqual(value, constant) {
            throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
        }
        if let enumValues = object["enum"] as? [Any],
           !enumValues.contains(where: { jsonEqual(value, $0) }) {
            throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
        }

        if let string = value as? String {
            let length = string.unicodeScalars.count
            if let minimum = integer(object["minLength"]), length < minimum {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
            if let maximum = integer(object["maxLength"]), length > maximum {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
            if let pattern = object["pattern"] as? String,
               !matches(string, pattern: pattern) {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
        }
        if let number = number(value) {
            if let minimum = numeric(object["minimum"]), number < minimum {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
            if let maximum = numeric(object["maximum"]), number > maximum {
                throw LeonardoJSONSchemaFailure.violation(path: path, .constraint)
            }
        }

        if let objectValue = value as? [String: Any] {
            if let required = object["required"] as? [Any] {
                for name in required.compactMap({ $0 as? String }) where objectValue[name] == nil {
                    throw LeonardoJSONSchemaFailure.violation(path: keyPath(path, name), .missing)
                }
            }
            if let propertyNames = object["propertyNames"] {
                for name in objectValue.keys.sorted() {
                    do {
                        try validateValue(name, schema: propertyNames, path: keyPath(path, name))
                    } catch let error as LeonardoJSONSchemaFailure {
                        switch error {
                        case .violation:
                            throw LeonardoJSONSchemaFailure.violation(path: keyPath(path, name), .propertyName)
                        case .unsupportedSchema:
                            throw error
                        }
                    }
                }
            }
            let properties = object["properties"] as? [String: Any] ?? [:]
            for name in properties.keys.sorted() where objectValue[name] != nil {
                guard let value = objectValue[name], let schema = properties[name] else {
                    throw LeonardoJSONSchemaFailure.unsupportedSchema("missing property schema")
                }
                try validateValue(value, schema: schema, path: keyPath(path, name))
            }
            if let additional = object["additionalProperties"] {
                let known = Set(properties.keys)
                let extras = objectValue.keys.filter { !known.contains($0) }.sorted()
                if let allowed = additional as? Bool {
                    if !allowed, let first = extras.first {
                        throw LeonardoJSONSchemaFailure.violation(path: keyPath(path, first), .unknownProperty)
                    }
                } else {
                    for name in extras {
                        guard let value = objectValue[name] else {
                            throw LeonardoJSONSchemaFailure.unsupportedSchema("missing additional property value")
                        }
                        try validateValue(value, schema: additional, path: keyPath(path, name))
                    }
                }
            }
        }
        if let arrayValue = value as? [Any], let items = object["items"] {
            for (index, item) in arrayValue.enumerated() {
                try validateValue(item, schema: items, path: indexPath(path, index))
            }
        }
    }

    private func resolve(_ reference: Any) throws -> Any {
        guard let reference = reference as? String,
              reference.hasPrefix("#/$defs/") else {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("unsupported $ref")
        }
        let name = String(reference.dropFirst("#/$defs/".count))
        guard !name.isEmpty, !name.contains("/"), !name.contains("~"),
              let definitions = root["$defs"] as? [String: Any],
              let schema = definitions[name] else {
            throw LeonardoJSONSchemaFailure.unsupportedSchema("unknown $ref")
        }
        return schema
    }

    private func matches(_ value: String, pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, options: [], range: range) != nil
    }

    private func matchesType(_ value: Any, name: String) -> Bool {
        switch name {
        case "null": return value is NSNull
        case "boolean": return isBoolean(value)
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "number": return number(value) != nil
        case "integer":
            guard let value = number(value) else { return false }
            return value.rounded() == value
        default: return false
        }
    }

    private func number(_ value: Any) -> Double? {
        guard !isBoolean(value), let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private func numeric(_ value: Any?) -> Double? {
        guard let value else { return nil }
        return number(value)
    }

    private func integer(_ value: Any?) -> Int? {
        guard let value, !isBoolean(value), let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private func isNonNegativeInteger(_ value: Any) -> Bool {
        guard let value = integer(value) else { return false }
        return value >= 0
    }

    private func isFiniteNumber(_ value: Any) -> Bool {
        number(value) != nil
    }

    private func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func jsonEqual(_ left: Any, _ right: Any) -> Bool {
        if isBoolean(left) || isBoolean(right) {
            return isBoolean(left) && isBoolean(right) && (left as? Bool) == (right as? Bool)
        }
        if let leftNumber = number(left), let rightNumber = number(right) {
            return leftNumber == rightNumber
        }
        if let leftString = left as? String, let rightString = right as? String {
            return leftString == rightString
        }
        if left is NSNull || right is NSNull {
            return left is NSNull && right is NSNull
        }
        if let leftArray = left as? [Any], let rightArray = right as? [Any] {
            return leftArray.count == rightArray.count
                && zip(leftArray, rightArray).allSatisfy { jsonEqual($0, $1) }
        }
        if let leftObject = left as? [String: Any], let rightObject = right as? [String: Any] {
            return leftObject.count == rightObject.count
                && leftObject.keys.allSatisfy { key in
                    guard let rightValue = rightObject[key], let leftValue = leftObject[key] else { return false }
                    return jsonEqual(leftValue, rightValue)
                }
        }
        return false
    }

    private func keyPath(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    private func indexPath(_ path: String, _ index: Int) -> String {
        path.isEmpty ? "[\(index)]" : "\(path)[\(index)]"
    }
}
