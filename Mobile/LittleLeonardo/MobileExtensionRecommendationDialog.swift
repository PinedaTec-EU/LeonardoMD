import SwiftUI
import LeonardoCore

struct MobileExtensionRecommendationDialog: View {
    let request: MobileExtensionRecommendation
    let spanish: Bool
    let respond: (MobileExtensionRecommendationChoice, Bool) -> Void
    @State private var choice = MobileExtensionRecommendationChoice()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: "puzzlepiece.extension")
                    .font(.title2.bold())
                    .foregroundStyle(MobileClassic.heading)
                Text(message)
                Text(scope).font(.callout).foregroundStyle(MobileClassic.secondary)

                ForEach(request.extensions) { item in
                    Toggle(isOn: selectionBinding(for: item)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label(for: item)).font(.headline)
                            Text(purpose(for: item)).font(.caption).foregroundStyle(MobileClassic.secondary)
                        }
                    }
                    .accessibilityIdentifier("enable-mobile-extension-\(item.rawValue)")
                }

                Toggle(suppressWarningLabel, isOn: Binding(
                    get: { choice.suppressWarnings },
                    set: { choice.suppressWarnings = $0 }
                ))
                .accessibilityIdentifier("suppress-mobile-extension-warnings")

                HStack {
                    Spacer()
                    Button(notNow) { respond(choice, false) }
                        .accessibilityIdentifier("not-now-mobile-extensions")
                    Button(enableSelected) { respond(choice, true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(choice.enabledExtensions.isEmpty)
                        .accessibilityIdentifier("enable-selected-mobile-extensions")
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .classicSurface()
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("mobile-extension-recommendation")
    }

    private var title: String { spanish ? "¿Activar extensiones del documento?" : "Enable document extensions?" }
    private var message: String {
        spanish
            ? "Este documento usa extensiones integradas desactivadas. Activa las que quieras para mostrar su contenido."
            : "This document uses disabled built-in extensions. Enable the ones you want to display its content."
    }
    private var scope: String {
        spanish
            ? "Las preferencias se aplican a Little Leonardo en este dispositivo."
            : "Preferences apply to Little Leonardo on this device."
    }
    private var suppressWarningLabel: String { spanish ? "No volver a mostrar este aviso" : "Do not show this warning again" }
    private var notNow: String { spanish ? "Ahora no" : "Not now" }
    private var enableSelected: String { spanish ? "Activar seleccionadas" : "Enable selected" }

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
        case .charts: spanish ? "Gráficos de datos dentro del documento" : "Inline data visualizations"
        case .citations: spanish ? "Bibliografías y referencias locales" : "Local bibliographies and references"
        case .extras: spanish ? "Notas al pie y avisos de GitHub" : "Footnotes and GitHub-style callouts"
        }
    }

    private func selectionBinding(for item: BuiltInExtension) -> Binding<Bool> {
        Binding(
            get: { choice.enabledExtensions.contains(item) },
            set: { isEnabled in
                if isEnabled { choice.enabledExtensions.insert(item) }
                else { choice.enabledExtensions.remove(item) }
            }
        )
    }
}
