import SwiftUI
import LeonardoCore

struct DocumentInspector: View {
    @Bindable var session: AppSession
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if session.leonardoDocument?.isForm == true {
                LeonardoFormFields(session: session)
                Divider()
            }
            Text(L10n.text("In this document")).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.headings, id: \.line) { heading in
                        Button(heading.title) { session.jumpToHeading(heading.line) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(PremiumButtonStyle(compact: true)).padding(20).frame(width: 320).background(.regularMaterial)
    }
}

private struct LeonardoFormFields: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("Form fields"), systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .accessibilityIdentifier("leonardo-form-fields")
            if session.leonardoFieldIDs.isEmpty {
                Text(L10n.text("No declared fields"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(session.leonardoFieldIDs, id: \.self) { fieldID in
                            if let definition = session.leonardoFieldDefinition(fieldID) {
                                LeonardoFormFieldRow(session: session, fieldID: fieldID, definition: definition)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

private struct LeonardoFormFieldRow: View {
    @Bindable var session: AppSession
    let fieldID: String
    let definition: LeonardoFieldDefinition

    private var label: String {
        let base = definition.label?.isEmpty == false ? definition.label! : fieldID
        return definition.required ? "\(base) *" : base
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { session.leonardoFieldText(fieldID) },
            set: { _ = session.updateLeonardoField(fieldID, text: $0) }
        )
    }

    private var checkboxBinding: Binding<Bool> {
        Binding(
            get: { session.leonardoFieldBool(fieldID) },
            set: { _ = session.updateLeonardoCheckbox(fieldID, value: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if definition.type == .checkbox {
                if definition.resolvedAppearance == .switch {
                    Toggle(label, isOn: checkboxBinding)
                        .toggleStyle(PremiumSwitchStyle())
                } else {
                    Toggle(label, isOn: checkboxBinding)
                        .toggleStyle(.checkbox)
                }
            } else {
                Text(label)
                    .font(.caption.weight(.semibold))
                input
            }
            if let helpText = definition.helpText, !helpText.isEmpty {
                Text(helpText).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(session.leonardoFieldDiagnostics(fieldID), id: \.code) { diagnostic in
                Label(L10n.text(diagnostic.message), systemImage: diagnostic.severity == .error ? "exclamationmark.triangle" : "info.circle")
                    .font(.caption2)
                    .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("leonardo-field-\(fieldID)")
        .disabled(definition.readOnly || session.mode != .fill)
        .help(session.mode == .fill ? "" : L10n.text("Choose Fill form to enter values"))
    }

    @ViewBuilder private var input: some View {
        switch definition.type {
        case .multiline:
            TextEditor(text: textBinding)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
        case .select:
            Picker("", selection: textBinding) {
                Text("").tag("")
                ForEach(definition.options, id: \.value) { option in
                    Text(option.label ?? option.value).tag(option.value)
                }
            }
            .labelsHidden()
        case .number:
            TextField(label, text: textBinding)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        default:
            TextField(definition.placeholder ?? label, text: textBinding)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}
