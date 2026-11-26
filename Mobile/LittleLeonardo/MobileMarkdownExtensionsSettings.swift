import SwiftUI
import LeonardoCore

struct MobileMarkdownExtensionsSettings: View {
    @ObservedObject var preferences: MobileMarkdownPreferences
    let spanish: Bool

    var body: some View {
        Section(spanish ? "Extensiones de documentos" : "Document extensions") {
            ForEach(BuiltInExtension.allCases) { item in
                Toggle(isOn: enabledBinding(for: item)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label(for: item))
                        Text(purpose(for: item))
                            .font(.caption)
                            .foregroundStyle(MobileClassic.secondary)
                    }
                }
                .accessibilityIdentifier("mobile-extension-\(item.rawValue)-toggle")
            }

            Text(spanish
                ? "Estas preferencias se guardan en este dispositivo y se aplican a los documentos recibidos. El documento permanece de solo lectura."
                : "These preferences stay on this device and apply to received documents. Documents remain read-only.")
                .font(.caption)

            Button(spanish ? "Restablecer avisos de extensiones" : "Reset extension warnings",
                   systemImage: "arrow.counterclockwise") {
                preferences.resetExtensionWarnings()
            }
            .accessibilityIdentifier("reset-mobile-extension-warnings")

            Text(spanish
                ? "Restablecer avisos no cambia las extensiones activadas."
                : "Resetting warnings does not change enabled extensions.")
                .font(.caption)
        }
        .listRowBackground(MobileClassic.inset)
    }

    private func enabledBinding(for item: BuiltInExtension) -> Binding<Bool> {
        Binding(
            get: { preferences.features[keyPath: item.flag] },
            set: { preferences.setEnabled($0, for: item) }
        )
    }

    private func label(for item: BuiltInExtension) -> String {
        switch item {
        case .mermaid: "Mermaid"
        case .math: spanish ? "Matemáticas (KaTeX)" : "Math (KaTeX)"
        case .charts: spanish ? "Gráficos (Vega-Lite)" : "Charts (Vega-Lite)"
        case .citations: spanish ? "Citas" : "Citations"
        case .extras: spanish ? "Extras de Markdown" : "Markdown extras"
        }
    }

    private func purpose(for item: BuiltInExtension) -> String {
        switch item {
        case .mermaid: spanish ? "Diagramas en documentos" : "Diagrams inside documents"
        case .math: spanish ? "Fórmulas con KaTeX" : "Formulas with KaTeX"
        case .charts: spanish ? "Visualizaciones de datos" : "Data visualizations"
        case .citations: spanish ? "Bibliografías y referencias" : "Bibliographies and references"
        case .extras: spanish ? "Notas al pie y avisos de GitHub" : "Footnotes and GitHub-style callouts"
        }
    }
}
