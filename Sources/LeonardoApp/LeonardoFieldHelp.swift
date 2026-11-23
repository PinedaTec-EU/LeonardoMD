import SwiftUI
import LeonardoCore

/// Context only: every value is edited at its placeholder in the document.
struct LeonardoFieldHelp: View {
    @Bindable var session: AppSession

    private var definition: LeonardoFieldDefinition? {
        session.selectedLeonardoFieldID.flatMap(session.leonardoFieldDefinition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(L10n.text("Field help"), systemImage: "info.circle").font(.headline)
                Spacer()
                Button { session.showInspector = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(L10n.text("Close field help"))
            }
            Divider()
            if let fieldID = session.selectedLeonardoFieldID, let definition {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(definition.label ?? fieldID).font(.title3.bold())
                        Text(definition.helpText ?? L10n.text("No additional help for this field."))
                        if let placeholder = definition.placeholder, !placeholder.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.text("Example")).font(.caption).foregroundStyle(.secondary)
                                Text(placeholder).textSelection(.enabled)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(session.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        ForEach(session.leonardoFieldDiagnostics(fieldID), id: \.code) { diagnostic in
                            Label(L10n.text(diagnostic.message), systemImage: "exclamationmark.circle")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 16)
                Divider()
                Text(L10n.text("Field properties")).font(.headline)
                property(definition.readOnly ? "Read only" : "Editable",
                         explanation: definition.readOnly ? "This value cannot be modified." : "You can modify this value.",
                         icon: definition.readOnly ? "lock" : "pencil")
                property(definition.required ? "Required" : "Optional",
                         explanation: definition.required ? "Complete this field before finalizing." : "You may leave this field empty.",
                         icon: definition.required ? "asterisk" : "minus.circle")
                Divider()
                Text(L10n.text("Help follows the field you select with (?)."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("Select (?) beside a field to see its help and properties."))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(24).frame(width: 320).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityIdentifier("leonardo-field-help")
    }

    private func property(_ title: String, explanation: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(session.accentColor)
                .frame(width: 36, height: 36)
                .background(session.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title)).font(.headline)
                Text(L10n.text(explanation)).font(.caption).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
