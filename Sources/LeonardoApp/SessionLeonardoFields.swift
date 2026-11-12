import Foundation
import LeonardoCore

extension AppSession {
    var leonardoDocument: LeonardoDocument? {
        guard documentKind.isLeonardo else { return nil }
        return try? LeonardoFormatParser.parse(content)
    }

    var leonardoFieldIDs: [String] {
        leonardoDocument?.metadata.fields.keys.sorted() ?? []
    }

    func leonardoFieldDefinition(_ fieldID: String) -> LeonardoFieldDefinition? {
        leonardoDocument?.metadata.fields[fieldID]
    }

    func leonardoFieldValue(_ fieldID: String) -> LeonardoJSONValue? {
        guard let document = leonardoDocument,
              let definition = document.metadata.fields[fieldID] else { return nil }
        return document.metadata.values[fieldID] ?? definition.defaultValue
    }

    func leonardoFieldText(_ fieldID: String) -> String {
        guard let value = leonardoFieldValue(fieldID) else { return "" }
        switch value {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .array, .object: return ""
        case .null: return ""
        }
    }

    func leonardoFieldBool(_ fieldID: String) -> Bool {
        leonardoFieldValue(fieldID)?.booleanValue ?? false
    }

    func leonardoFieldDiagnostics(_ fieldID: String) -> [LeonardoDiagnostic] {
        guard let document = leonardoDocument else { return [] }
        return LeonardoFormatValidator.validate(document, context: .draft).filter { $0.fieldID == fieldID }
    }

    @discardableResult
    func updateLeonardoField(_ fieldID: String, text: String) -> Bool {
        guard let definition = leonardoFieldDefinition(fieldID) else { return false }
        let value: LeonardoJSONValue
        if definition.type == .number, let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite {
            value = .number(number)
        } else if definition.type == .number, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = .null
        } else {
            value = .string(text)
        }
        return updateLeonardoField(fieldID, value: value)
    }

    @discardableResult
    func updateLeonardoCheckbox(_ fieldID: String, value: Bool) -> Bool {
        guard let definition = leonardoFieldDefinition(fieldID), definition.type == .checkbox else { return false }
        return updateLeonardoField(fieldID, value: .boolean(value))
    }

    var canFillLeonardoForm: Bool {
        documentURL != nil && documentKind.isLeonardo && mode == .fill
            && !stopped && !isClosing && !busy && !isSyncSuspended && !isCapturingPreview
    }

    func showLeonardoFieldHelp(_ fieldID: String) {
        guard mode == .fill, leonardoFieldDefinition(fieldID) != nil else { return }
        selectedLeonardoFieldID = fieldID
        showInspector = true
        focus = false
    }

    /// All form entry points share authorization; the source padlock is independent.
    func updateLeonardoFields(expected: String, changes: [String: LeonardoJSONValue]) -> String? {
        guard canFillLeonardoForm, content == expected,
              let current = leonardoDocument,
              let document = current.applyingFormValues(changes) else { return nil }
        guard let replacement = try? LeonardoFormatParser.serialize(document) else { return nil }
        if replacement != content {
            applyDocumentEdit(replacement, form: true)
        }
        return replacement
    }

    private func updateLeonardoField(
        _ fieldID: String,
        value: LeonardoJSONValue
    ) -> Bool {
        updateLeonardoFields(expected: content, changes: [fieldID: value]) != nil
    }
}
