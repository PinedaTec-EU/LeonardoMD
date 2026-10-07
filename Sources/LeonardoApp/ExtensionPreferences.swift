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
                Text(projectScope ? "Extensiones de este proyecto" : "Extensiones globales")
                    .font(.headline)
                if projectScope {
                    Toggle("Heredar extensiones globales", isOn: Binding(
                        get: { session.projectConfiguration.markdown == nil },
                        set: { session.inheritFeatures($0) }
                    )).accessibilityIdentifier("inherit-extensions-toggle")
                    Text("Al cambiar una extensión se crea una configuración propia del proyecto.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                extensionCard("Mermaid", description: "Diagramas dentro de tus documentos",
                              symbol: "point.3.connected.trianglepath.dotted",
                              enabled: Binding(get: { features.mermaidEnabled },
                                               set: { session.setMermaid($0, project: projectScope) }))
                extensionCard("Matemáticas", description: "Fórmulas con KaTeX", symbol: "sum",
                              enabled: Binding(get: { features.mathEnabled },
                                               set: { session.setMath($0, project: projectScope) }))
                Text("Las extensiones se cargan solo al activarlas. Los cambios se aplican al documento cuando utiliza este ámbito.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(PremiumSwitchStyle())
    }

    private func extensionCard(_ title: String, description: String, symbol: String, enabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: enabled) { Label(title, systemImage: symbol).font(.headline) }
                .accessibilityIdentifier(title.lowercased() + "-toggle")
            Text(description).font(.caption).foregroundStyle(.secondary)
            Text(enabled.wrappedValue ? "Activado" : "Desactivado")
                .font(.caption).foregroundStyle(enabled.wrappedValue ? session.accentColor : Color.secondary)
        }.padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enabled.wrappedValue ? session.accentColor.opacity(0.40) : .primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
    }
}
