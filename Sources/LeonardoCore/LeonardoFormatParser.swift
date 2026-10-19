import Foundation

/// Parses and serializes the open, text-based MDLF format. The metadata block
/// is deliberately JSON rather than an implicit YAML dialect: JSON is a
/// strict subset of the commonly used front-matter tooling and every agent
/// can parse it without a private dependency.
public enum LeonardoFormatParser {
    private static let openingDelimiter = "---"
    private static let closingDelimiters: Set<String> = ["---", "..."]

    public static func parse(_ source: String) throws -> LeonardoDocument {
        let parts = try splitFrontMatter(source)
        guard let data = parts.metadata.data(using: .utf8) else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        try LeonardoJSONDuplicateKeyValidator.validate(parts.metadata)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        guard let format = dictionary["format"] as? String,
              format == LeonardoFormat.identifier else {
            throw LeonardoFormatError.missingFormatIdentifier
        }
        guard let formatVersion = dictionary["formatVersion"] as? Int else {
            throw LeonardoFormatError.missingFormatVersion
        }
        guard formatVersion > 0,
              formatVersion <= LeonardoFormat.currentVersion else {
            throw LeonardoFormatError.unsupportedVersion(formatVersion)
        }
        try LeonardoFormatMetadataSchema.validate(dictionary)
        let metadata: LeonardoMetadata
        do {
            metadata = try JSONDecoder().decode(LeonardoMetadata.self, from: data)
        } catch let error as LeonardoFormatError {
            throw error
        } catch {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        guard metadata.format == LeonardoFormat.identifier else {
            throw LeonardoFormatError.missingFormatIdentifier
        }
        guard metadata.formatVersion == formatVersion else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        guard metadata.formatVersion > 0,
              metadata.formatVersion <= LeonardoFormat.currentVersion else {
            throw LeonardoFormatError.unsupportedVersion(metadata.formatVersion)
        }
        try LeonardoFormatMetadataSafety.validate(metadata)
        return LeonardoDocument(body: parts.body, metadata: metadata)
    }

    public static func serialize(_ document: LeonardoDocument) throws -> String {
        guard document.metadata.format == LeonardoFormat.identifier else {
            throw LeonardoFormatError.missingFormatIdentifier
        }
        guard document.metadata.formatVersion > 0,
              document.metadata.formatVersion <= LeonardoFormat.currentVersion else {
            throw LeonardoFormatError.unsupportedVersion(document.metadata.formatVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document.metadata)
        } catch let error as LeonardoFormatError {
            throw error
        } catch {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        try LeonardoFormatMetadataSchema.validate(document.metadata)
        try LeonardoFormatMetadataSafety.validate(document.metadata)
        guard let metadata = String(data: data, encoding: .utf8) else {
            throw LeonardoFormatError.invalidMetadataJSON
        }
        return "\(openingDelimiter)\n\(metadata)\n\(openingDelimiter)\n\(document.body)"
    }

    public static func detect(_ source: String) -> LeonardoFormatDetection {
        guard let parts = try? splitFrontMatter(source) else { return .markdown }
        guard let data = parts.metadata.data(using: .utf8) else { return .markdown }
        do {
            try LeonardoJSONDuplicateKeyValidator.validate(parts.metadata)
        } catch {
            return containsLeonardoMarker(parts.metadata) ? .malformedLeonardo : .markdown
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return containsLeonardoMarker(parts.metadata) ? .malformedLeonardo : .markdown
        }
        guard let format = dictionary["format"] as? String,
              format == LeonardoFormat.identifier else {
            // A standard Markdown document may use ordinary YAML front matter
            // or a JSON example. Only the explicit mdlf marker opts it in.
            return .markdown
        }
        guard let version = dictionary["formatVersion"] as? Int else {
            return .malformedLeonardo
        }
        return .leonardo(version: version)
    }

    private static func containsLeonardoMarker(_ metadata: String) -> Bool {
        metadata.range(of: #""format"\s*:\s*"mdlf""#, options: .regularExpression) != nil
    }

    public static func modeHint(forPathExtension pathExtension: String) -> LeonardoFileModeHint? {
        switch pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mdlf": return .edit
        case "mdlr": return .fill
        default: return nil
        }
    }

    private static func splitFrontMatter(_ source: String) throws -> (metadata: String, body: String) {
        var source = source
        if source.first == "\u{FEFF}" { source.removeFirst() }
        let lines = lineSlices(source)
        guard lines.first.map({ String($0.text) }) == openingDelimiter else {
            throw LeonardoFormatError.missingFrontMatter
        }
        guard let closingIndex = lines.dropFirst().firstIndex(where: { line in
            closingDelimiters.contains(line.text.trimmingCharacters(in: .whitespaces))
        }) else {
            throw LeonardoFormatError.invalidFrontMatter
        }
        let metadataStart = lines[1].start
        let metadataEnd = lines[closingIndex].start
        let bodyStart = lines[closingIndex].next
        let metadata = String(source[metadataStart..<metadataEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !metadata.isEmpty else { throw LeonardoFormatError.invalidFrontMatter }
        return (metadata, String(source[bodyStart..<source.endIndex]))
    }

    private struct LineSlice {
        let text: Substring
        let start: String.Index
        let next: String.Index
    }

    private static func lineSlices(_ source: String) -> [LineSlice] {
        var result: [LineSlice] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let start = cursor
            while cursor < source.endIndex,
                  !source[cursor].isNewline {
                cursor = source.index(after: cursor)
            }
            let end = cursor
            if cursor < source.endIndex {
                let newline = source[cursor]
                cursor = source.index(after: cursor)
                if newline == "\r", cursor < source.endIndex, source[cursor] == "\n" {
                    cursor = source.index(after: cursor)
                }
            }
            result.append(LineSlice(text: source[start..<end], start: start, next: cursor))
        }
        if source.isEmpty || source.last?.isNewline == true {
            result.append(LineSlice(text: source[source.endIndex..<source.endIndex], start: source.endIndex, next: source.endIndex))
        }
        return result
    }
}

public enum LeonardoFormatValidator {
    private static let maximumPatternBytes = 512
    private static let maximumPatternInputBytes = 32_768
    private static let fieldIDPattern = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_.-]{0,63}$")
    private static let fieldTokenPattern = try! NSRegularExpression(pattern: "\\{\\{\\s*field:([A-Za-z][A-Za-z0-9_.-]{0,63})\\s*\\}\\}")
    private static let isoDateShape = try! NSRegularExpression(pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
    private static let emailPattern = try! NSRegularExpression(pattern: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
    private static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) { calendar.timeZone = timeZone }
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    public static func validate(
        _ document: LeonardoDocument,
        context: LeonardoValidationContext = .draft
    ) -> [LeonardoDiagnostic] {
        var diagnostics: [LeonardoDiagnostic] = []
        validateEnvelope(document.metadata, into: &diagnostics)
        validateFields(document.metadata, context: context, into: &diagnostics)
        validateReferences(document.body, fields: document.metadata.fields, into: &diagnostics)
        if let layout = document.metadata.layout {
            validateLayout(layout, into: &diagnostics)
        }
        return diagnostics
    }

    public static func isValid(
        _ document: LeonardoDocument,
        context: LeonardoValidationContext = .draft
    ) -> Bool {
        !validate(document, context: context).contains { $0.severity == .error }
    }

    private static func validateEnvelope(_ metadata: LeonardoMetadata, into diagnostics: inout [LeonardoDiagnostic]) {
        guard metadata.format == LeonardoFormat.identifier else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: "format.identifier", message: "The metadata format must be mdlf."))
            return
        }
        if metadata.formatVersion != LeonardoFormat.currentVersion {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: "format.version", message: "The metadata format version is unsupported."))
            return
        }
        if let revision = metadata.document.revision, revision < 1 {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: "document.revision", message: "Document revision must be positive."))
        }
        if metadata.document.kind == .form && metadata.fields.isEmpty {
            diagnostics.append(LeonardoDiagnostic(severity: .warning, code: "form.noFields", message: "This document is marked as a form but declares no fields."))
        }
    }

    private static func validateFields(
        _ metadata: LeonardoMetadata,
        context: LeonardoValidationContext,
        into diagnostics: inout [LeonardoDiagnostic]
    ) {
        for (fieldID, definition) in metadata.fields.sorted(by: { $0.key < $1.key }) {
            guard matches(fieldID, pattern: fieldIDPattern) else {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.id", message: "Field identifiers must start with a letter and contain only letters, numbers, dots, hyphens or underscores.", fieldID: fieldID))
                continue
            }
            if let minLength = definition.minLength, minLength < 0 {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.minLength", message: "Minimum length cannot be negative.", fieldID: fieldID))
            }
            if let maxLength = definition.maxLength, maxLength < 0 {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.maxLength", message: "Maximum length cannot be negative.", fieldID: fieldID))
            }
            if let minimum = definition.minimum, !minimum.isFinite {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.minimum", message: "Minimum must be finite.", fieldID: fieldID))
            }
            if let maximum = definition.maximum, !maximum.isFinite {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.maximum", message: "Maximum must be finite.", fieldID: fieldID))
            }
            if let minLength = definition.minLength,
               let maxLength = definition.maxLength,
               minLength > maxLength {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.lengthRange", message: "Minimum length cannot exceed maximum length.", fieldID: fieldID))
            }
            if let minimum = definition.minimum,
               let maximum = definition.maximum,
               minimum > maximum {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.numberRange", message: "Minimum cannot exceed maximum.", fieldID: fieldID))
            }
            if let pattern = definition.pattern {
                if pattern.utf8.count > maximumPatternBytes {
                    diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.patternLength", message: "Validation expressions are limited to 512 UTF-8 bytes.", fieldID: fieldID))
                } else if let reason = unsafePatternReason(pattern) {
                    diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.patternSafety", message: reason, fieldID: fieldID))
                } else if (try? NSRegularExpression(pattern: pattern)) == nil {
                    diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.pattern", message: "The validation expression is not a valid regular expression.", fieldID: fieldID))
                }
            }
            if definition.appearance != nil && definition.type != .checkbox {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.appearance", message: "Appearance is only supported for checkbox fields.", fieldID: fieldID))
            }
            validateOptions(definition, fieldID: fieldID, into: &diagnostics)
            let value = metadata.values[fieldID] ?? definition.defaultValue
            if value == nil || value?.isNullOrEmpty == true {
                if definition.required {
                    let severity: LeonardoDiagnosticSeverity = context == .submission ? .error : .warning
                    diagnostics.append(LeonardoDiagnostic(severity: severity, code: "field.required", message: validationMessage(definition, fallback: "A value is required."), fieldID: fieldID))
                }
                continue
            }
            if let value {
                validateValue(value, definition: definition, fieldID: fieldID, into: &diagnostics)
            }
        }
        for valueID in metadata.values.keys where metadata.fields[valueID] == nil {
            diagnostics.append(LeonardoDiagnostic(severity: .warning, code: "value.unknownField", message: "A value is present for an undeclared field.", fieldID: valueID))
        }
    }

    private static func validateOptions(
        _ definition: LeonardoFieldDefinition,
        fieldID: String,
        into diagnostics: inout [LeonardoDiagnostic]
    ) {
        var seen = Set<String>()
        for option in definition.options {
            guard !option.value.isEmpty else {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.optionEmpty", message: "Select options must have a value.", fieldID: fieldID))
                continue
            }
            if !seen.insert(option.value).inserted {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.optionDuplicate", message: "Select options must be unique.", fieldID: fieldID))
            }
        }
        if definition.type == .select && definition.options.isEmpty {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: "field.optionsMissing", message: "A select field must declare at least one option.", fieldID: fieldID))
        } else if definition.type != .select && !definition.options.isEmpty {
            diagnostics.append(LeonardoDiagnostic(severity: .warning, code: "field.optionsIgnored", message: "Options are ignored for this field type.", fieldID: fieldID))
        }
    }

    private static func validateValue(
        _ value: LeonardoJSONValue,
        definition: LeonardoFieldDefinition,
        fieldID: String,
        into diagnostics: inout [LeonardoDiagnostic]
    ) {
        switch definition.type {
        case .text, .multiline, .email, .url, .date, .select:
            guard let string = value.stringValue else {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.type", message: validationMessage(definition, fallback: "This field requires a string value."), fieldID: fieldID))
                return
            }
            if let minLength = definition.minLength, string.count < minLength {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.minLength", message: validationMessage(definition, fallback: "The value is shorter than the allowed minimum."), fieldID: fieldID))
            }
            if let maxLength = definition.maxLength, string.count > maxLength {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.maxLength", message: validationMessage(definition, fallback: "The value is longer than the allowed maximum."), fieldID: fieldID))
            }
            if definition.pattern != nil,
               string.utf8.count > maximumPatternInputBytes {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.patternInputLength", message: validationMessage(definition, fallback: "Values checked by a regular expression are limited to 32768 UTF-8 bytes."), fieldID: fieldID))
            } else if let pattern = definition.pattern,
                      let expression = safeExpression(pattern),
                      !matches(string, pattern: expression) {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.pattern", message: validationMessage(definition, fallback: "The value does not match the validation expression."), fieldID: fieldID))
            }
            switch definition.type {
            case .email where !matches(string, pattern: emailPattern):
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.email", message: validationMessage(definition, fallback: "The value is not a valid email address."), fieldID: fieldID))
            case .url where !isValidURL(string):
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.url", message: validationMessage(definition, fallback: "The value is not a valid URL."), fieldID: fieldID))
            case .date where !isValidISODate(string):
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.date", message: validationMessage(definition, fallback: "Dates must use YYYY-MM-DD."), fieldID: fieldID))
            case .select where !definition.options.contains(where: { $0.value == string }):
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.option", message: validationMessage(definition, fallback: "The value is not one of the allowed options."), fieldID: fieldID))
            default:
                break
            }
        case .number:
            guard let number = value.numberValue, number.isFinite else {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.type", message: validationMessage(definition, fallback: "This field requires a finite number."), fieldID: fieldID))
                return
            }
            if let minimum = definition.minimum, number < minimum {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.minimum", message: validationMessage(definition, fallback: "The number is below the allowed minimum."), fieldID: fieldID))
            }
            if let maximum = definition.maximum, number > maximum {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.maximum", message: validationMessage(definition, fallback: "The number exceeds the allowed maximum."), fieldID: fieldID))
            }
        case .checkbox:
            guard value.booleanValue != nil else {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "value.type", message: validationMessage(definition, fallback: "This field requires a boolean value."), fieldID: fieldID))
                return
            }
        }
    }

    private static func validateReferences(
        _ body: String,
        fields: [String: LeonardoFieldDefinition],
        into diagnostics: inout [LeonardoDiagnostic]
    ) {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        for match in fieldTokenPattern.matches(in: body, range: range) {
            guard match.numberOfRanges > 1,
                  let fieldRange = Range(match.range(at: 1), in: body) else { continue }
            let fieldID = String(body[fieldRange])
            guard fields[fieldID] == nil else { continue }
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: "body.unknownField", message: "The body references an undeclared field.", fieldID: fieldID))
        }
    }

    private static func validateLayout(_ layout: LeonardoLayout, into diagnostics: inout [LeonardoDiagnostic]) {
        if let page = layout.page {
            validateNonNegative(page.margins.top, code: "layout.margin", into: &diagnostics)
            validateNonNegative(page.margins.right, code: "layout.margin", into: &diagnostics)
            validateNonNegative(page.margins.bottom, code: "layout.margin", into: &diagnostics)
            validateNonNegative(page.margins.left, code: "layout.margin", into: &diagnostics)
            if page.size == .custom {
                validatePositive(page.widthPoints, code: "layout.pageWidth", into: &diagnostics)
                validatePositive(page.heightPoints, code: "layout.pageHeight", into: &diagnostics)
            }
        }
        if let background = layout.background {
            validateOpacity(background.opacity, code: "layout.backgroundOpacity", into: &diagnostics)
            validatePosition(background.position, into: &diagnostics)
            if let image = background.image { validateAssetReference(image, code: "layout.backgroundImage", into: &diagnostics) }
        }
        var imageOccurrences = Set<String>()
        for image in layout.images {
            validateAssetReference(image.source, code: "layout.imageSource", into: &diagnostics)
            if image.occurrence < 1 {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "layout.imageOccurrence", message: "Image occurrences are one-based."))
            }
            let key = "\(image.source)#\(image.occurrence)"
            if !imageOccurrences.insert(key).inserted {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "layout.imageDuplicate", message: "Image layout entries must identify unique occurrences."))
            }
            validateSize(image.size, into: &diagnostics)
            validatePosition(image.position, into: &diagnostics)
            validateOpacity(image.opacity, code: "layout.imageOpacity", into: &diagnostics)
        }
        var tableOccurrences = Set<Int>()
        for table in layout.tables {
            if table.occurrence < 1 {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "layout.tableOccurrence", message: "Table occurrences are one-based."))
            }
            if !tableOccurrences.insert(table.occurrence).inserted {
                diagnostics.append(LeonardoDiagnostic(severity: .error, code: "layout.tableDuplicate", message: "Table layout entries must identify unique occurrences."))
            }
            validateDimension(table.width, code: "layout.tableWidth", into: &diagnostics)
            for column in table.columns {
                validateDimension(column.width, code: "layout.columnWidth", into: &diagnostics)
                validateDimension(column.minimumWidth, code: "layout.columnMinimum", into: &diagnostics)
                validateDimension(column.maximumWidth, code: "layout.columnMaximum", into: &diagnostics)
            }
        }
    }

    private static func validateSize(_ size: LeonardoSize, into diagnostics: inout [LeonardoDiagnostic]) {
        validateDimension(size.width, code: "layout.width", into: &diagnostics)
        validateDimension(size.height, code: "layout.height", into: &diagnostics)
    }

    private static func validatePosition(_ position: LeonardoPosition, into diagnostics: inout [LeonardoDiagnostic]) {
        validateOffset(position.x, code: "layout.positionX", into: &diagnostics)
        validateOffset(position.y, code: "layout.positionY", into: &diagnostics)
        if position.placement == .flow, position.x != nil || position.y != nil {
            diagnostics.append(LeonardoDiagnostic(severity: .warning, code: "layout.flowOffset", message: "Flow placement ignores x and y offsets."))
        }
    }

    private static func validateOffset(
        _ dimension: LeonardoDimension?,
        code: String,
        into diagnostics: inout [LeonardoDiagnostic]
    ) {
        guard let dimension else { return }
        guard dimension.value.isFinite else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Layout offsets must be finite."))
            return
        }
        switch dimension.unit {
        case .points where abs(dimension.value) > 10_000:
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Point offsets must be between -10000 and 10000."))
        case .percent where abs(dimension.value) > 100:
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Percentage offsets must be between -100 and 100."))
        default:
            break
        }
    }

    private static func validateDimension(
        _ dimension: LeonardoDimension?,
        code: String,
        into diagnostics: inout [LeonardoDiagnostic]
    ) {
        guard let dimension else { return }
        guard dimension.value.isFinite else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Layout dimensions must be finite."))
            return
        }
        switch dimension.unit {
        case .points where dimension.value <= 0 || dimension.value > 10_000:
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Point dimensions must be greater than zero and at most 10000."))
        case .percent where dimension.value <= 0 || dimension.value > 100:
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Percentage dimensions must be greater than zero and at most 100."))
        default:
            break
        }
    }

    private static func validateAssetReference(_ source: String, code: String, into diagnostics: inout [LeonardoDiagnostic]) {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Asset references cannot be empty."))
            return
        }
        let scheme = URL(string: value)?.scheme?.lowercased()
        let unsafeScheme = scheme != nil && !["http", "https"].contains(scheme)
        let hasControlCharacter = value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        let hasBackslash = value.contains("\\")
        if value.hasPrefix("/")
            || hasBackslash
            || hasControlCharacter
            || unsafeScheme
            || value.split(separator: "/").contains(where: { $0 == ".." }) {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Asset references must be relative paths or safe web URLs."))
        }
    }

    private static func validateOpacity(_ value: Double, code: String, into diagnostics: inout [LeonardoDiagnostic]) {
        guard value.isFinite, (0...1).contains(value) else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Opacity must be between 0 and 1."))
            return
        }
    }

    private static func validatePositive(_ value: Double?, code: String, into diagnostics: inout [LeonardoDiagnostic]) {
        guard let value else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Custom page dimensions are required."))
            return
        }
        guard value.isFinite, value > 0, value <= 10_000 else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Page dimensions must be greater than zero and at most 10000 points."))
            return
        }
    }

    private static func validateNonNegative(_ value: Double, code: String, into diagnostics: inout [LeonardoDiagnostic]) {
        guard value.isFinite, value >= 0, value <= 10_000 else {
            diagnostics.append(LeonardoDiagnostic(severity: .error, code: code, message: "Margins must be finite values between 0 and 10000 points."))
            return
        }
    }

    private static func matches(_ value: String, pattern: NSRegularExpression) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(25))
        var found = false
        pattern.enumerateMatches(in: value, options: [.reportProgress], range: range) { result, _, stop in
            if result != nil {
                found = true
                stop.pointee = true
            } else if clock.now >= deadline {
                // ICU periodically reports progress even while backtracking.
                // Treat budget exhaustion as invalid instead of freezing the UI.
                stop.pointee = true
            }
        }
        return found
    }

    private static func isValidISODate(_ value: String) -> Bool {
        guard matches(value, pattern: isoDateShape) else { return false }
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              year >= 1 else { return false }
        let requested = DateComponents(calendar: gregorianUTC, timeZone: gregorianUTC.timeZone,
                                       year: year, month: month, day: day)
        guard let date = gregorianUTC.date(from: requested) else { return false }
        let normalized = gregorianUTC.dateComponents([.year, .month, .day], from: date)
        return normalized.year == year && normalized.month == month && normalized.day == day
    }

    private static func validationMessage(
        _ definition: LeonardoFieldDefinition,
        fallback: String
    ) -> String {
        guard let custom = definition.validationMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !custom.isEmpty else { return fallback }
        return custom
    }

    private static func safeExpression(_ pattern: String) -> NSRegularExpression? {
        guard pattern.utf8.count <= maximumPatternBytes,
              unsafePatternReason(pattern) == nil else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }

    private static func unsafePatternReason(_ pattern: String) -> String? {
        let forbiddenFragments = ["(?=", "(?!", "(?<=", "(?<!"]
        if forbiddenFragments.contains(where: { pattern.contains($0) })
            || pattern.range(of: #"\\(?:[1-9]|k<)"#, options: .regularExpression) != nil {
            return "Validation expressions cannot use backreferences or look-around constructs."
        }
        // V1 deliberately uses the intersection of the Python `re` and
        // ICU/NSRegularExpression dialects. Engine-specific escapes and
        // named/conditional/atomic groups would otherwise make the same
        // MDLF validate differently in the native app and agent helpers.
        let nonPortableFragments = [
            #"\p{"#, #"\P{"#, #"\X"#, #"\R"#, #"\N{"#,
            #"\A"#, #"\Z"#, #"\z"#,
            "(?<", "(?P<", "(?P=", "(?(", "(?>"
        ]
        if nonPortableFragments.contains(where: { pattern.contains($0) }) {
            return "Validation expressions must use the portable v1 regular-expression subset."
        }
        // A repeated group can make ICU backtracking exponential when it
        // contains alternatives or another repetition. V1 rejects all
        // quantified groups; simple character-class and literal quantifiers
        // remain available and values are capped before execution.
        if pattern.range(of: #"\)(?:[+*?]|\{\d)"#, options: .regularExpression) != nil {
            return "Validation expressions cannot quantify groups."
        }
        return nil
    }

    private static func isValidURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }
}
