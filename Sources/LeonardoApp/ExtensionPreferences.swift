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
                if projectScope {
                    Toggle(L10n.text("Inherit global extensions"), isOn: Binding(
                        get: { session.projectConfiguration.markdown == nil },
                        set: { session.inheritFeatures($0) }
                    )).accessibilityIdentifier("inherit-extensions-toggle")
                    Text(L10n.text("Changing an extension creates a project-specific configuration."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                extensionCard(L10n.text("Mermaid"), identifier: "mermaid", description: L10n.text("Diagrams inside your documents"),
                              symbol: "point.3.connected.trianglepath.dotted",
                              enabled: Binding(get: { features.mermaidEnabled },
                                               set: { session.setMermaid($0, project: projectScope) }))
                extensionCard(L10n.text("Math"), identifier: "math", description: L10n.text("Formulas with KaTeX"), symbol: "sum",
                              enabled: Binding(get: { features.mathEnabled },
                                               set: { session.setMath($0, project: projectScope) }))
                extensionCard(L10n.text("Charts (Vega-Lite)"), identifier: "vega-lite", description: L10n.text("Inline data visualizations inside your documents"), symbol: "chart.bar.xaxis",
                              enabled: Binding(get: { features.vegaLiteEnabled },
                                               set: { session.setVegaLite($0, project: projectScope) }))
                extensionCard(L10n.text("Citations"), identifier: "citations", description: L10n.text("Bibliographies and references with Citation.js"), symbol: "text.book.closed",
                              enabled: Binding(get: { features.citationsEnabled },
                                               set: { session.setCitations($0, project: projectScope) }))
                extensionCard(L10n.text("Markdown extras"), identifier: "markdown-extensions", description: L10n.text("Footnotes and GitHub-style callouts"), symbol: "text.badge.plus",
                              enabled: Binding(get: { features.markdownExtensionsEnabled },
                                               set: { session.setMarkdownExtensions($0, project: projectScope) }))
                VStack(alignment: .leading, spacing: 6) {
                    Button(L10n.text("Reset extension warnings")) { ExtensionWarningPreferences.shared.reset() }
                        .accessibilityIdentifier("reset-extension-warnings")
                    Text(L10n.text("Ask again about disabled extensions in documents. This does not change enabled extensions."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("Charts and bibliography engines load only when used. Disabling an extension preserves the document source."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(PremiumSwitchStyle())
    }

    private func extensionCard(_ title: String, identifier: String, description: String, symbol: String, enabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: enabled) { Label(title, systemImage: symbol).font(.headline) }
                .accessibilityIdentifier(identifier + "-toggle")
            Text(description).font(.caption).foregroundStyle(.secondary)
        }.padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enabled.wrappedValue ? session.accentColor.opacity(0.40) : .primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
    }
}
