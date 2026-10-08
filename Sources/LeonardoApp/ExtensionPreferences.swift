import SwiftUI
import LeonardoCore

struct ExtensionPreferences: View {
    @Bindable var session: AppSession
    let projectScope: Bool

    private var features: MarkdownFeatures {
        projectScope ? session.features : session.globalPreferences.markdown
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(projectScope ? L10n.text("Project extensions") : L10n.text("Global extensions"))
                    .font(.headline)
                if projectScope {
                    Toggle(L10n.text("Inherit global extensions"), isOn: Binding(
                        get: { session.projectConfiguration.markdown == nil },
                        set: { session.inheritFeatures($0) }
                    )).accessibilityIdentifier("inherit-extensions-toggle")
                    Text(L10n.text("Changing an extension creates a project-specific configuration."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                extensionCard("Mermaid", identifier: "mermaid", description: L10n.text("Diagrams inside your documents"),
                              symbol: "point.3.connected.trianglepath.dotted",
                              enabled: Binding(get: { features.mermaidEnabled },
                                               set: { session.setMermaid($0, project: projectScope) }))
                extensionCard(L10n.text("Math"), identifier: "math", description: L10n.text("Formulas with KaTeX"), symbol: "sum",
                              enabled: Binding(get: { features.mathEnabled },
                                               set: { session.setMath($0, project: projectScope) }))
                Text(L10n.text("Extensions load only when enabled. Changes apply to documents using this scope."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(PremiumSwitchStyle())
    }

    private func extensionCard(_ title: String, identifier: String, description: String, symbol: String, enabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: enabled) { Label(title, systemImage: symbol).font(.headline) }
                .accessibilityIdentifier(identifier + "-toggle")
            Text(description).font(.caption).foregroundStyle(.secondary)
            Text(enabled.wrappedValue ? L10n.text("Enabled") : L10n.text("Disabled"))
                .font(.caption).foregroundStyle(enabled.wrappedValue ? session.accentColor : Color.secondary)
        }.padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enabled.wrappedValue ? session.accentColor.opacity(0.40) : .primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
    }
}
