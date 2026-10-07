import SwiftUI
import LeonardoCore

struct ExtensionInspector: View {
    @Bindable var session: AppSession
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Extensiones", systemImage: "puzzlepiece.extension").font(.title2.weight(.semibold))
            Text(session.projectURL == nil ? "Configuración global del visor" : "Configuración de este proyecto")
                .font(.caption).foregroundStyle(.secondary)
            extensionCard("Mermaid", description: "Diagramas dentro de tus documentos", symbol: "point.3.connected.trianglepath.dotted", enabled: Binding(get: { session.features.mermaidEnabled }, set: { session.setMermaid($0) }))
            extensionCard("Matemáticas", description: "Fórmulas con KaTeX", symbol: "sum", enabled: Binding(get: { session.features.mathEnabled }, set: { session.setMath($0) }))
            Text("Los motores se cargan solo al activarlos. Al desactivarlos se libera su contexto de ejecución.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("En este documento").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.headings, id: \.line) { heading in
                        Button(heading.title) { session.jumpToHeading(heading.line) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Button("Apariencia y preferencias…") { session.showPreferences = true }
        }.buttonStyle(PremiumButtonStyle(compact: true)).padding(20).frame(width: 260).background(.regularMaterial)
    }
    private func extensionCard(_ title: String, description: String, symbol: String, enabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: enabled) { Label(title, systemImage: symbol).font(.headline) }
                .toggleStyle(PremiumSwitchStyle()).accessibilityIdentifier(title.lowercased() + "-toggle")
            Text(description).font(.caption).foregroundStyle(.secondary)
            Text(enabled.wrappedValue ? "Activo" : "Motor descargado").font(.caption).foregroundStyle(enabled.wrappedValue ? session.accentColor : Color.secondary)
        }.padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enabled.wrappedValue ? session.accentColor.opacity(0.40) : .primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
    }
}

struct PreferencesView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var projectScope = false
    @State private var editingPalette = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Preferencias").font(.title2.bold())
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if session.projectURL != nil {
                PremiumSelection(selection: $projectScope, options: [false, true], title: { $0 ? "Este proyecto" : "Global" })
                    .accessibilityLabel("Ámbito")
            }
            Form {
                Picker("Paleta", selection: Binding(get: { projectScope ? session.projectConfiguration.palette?.rawValue ?? "inherit" : session.globalPreferences.palette.rawValue }, set: { session.setPalette($0, project: projectScope) })) {
                    if projectScope { Text("Heredar global").tag("inherit") }
                    ForEach(PaletteCatalog.all) { palette in Text(palette.displayName).tag(palette.id.rawValue) }
                }
                Picker("Efecto de hoja", selection: Binding(get: { projectScope ? session.projectConfiguration.paperEffect?.rawValue ?? "inherit" : session.globalPreferences.paperEffect.rawValue }, set: { session.setPaper($0, project: projectScope) })) {
                    if projectScope { Text("Heredar global").tag("inherit") }
                    ForEach(PaperEffect.allCases, id: \.self) { effect in Text(effect.title).tag(effect.rawValue) }
                }
                Button("Personalizar / importar paleta…") { editingPalette = true }
                Toggle("Mostrar frontmatter", isOn: $session.showFrontmatter)
                Toggle("Confirmar enlaces externos", isOn: $session.confirmExternalLinks)
                Toggle("Mostrar archivos ocultos", isOn: $session.showHidden)
                if projectScope {
                    Toggle("Heredar extensiones globales", isOn: Binding(get: { session.projectConfiguration.markdown == nil }, set: { session.inheritFeatures($0) }))
                    Toggle("Activar herramientas Git", isOn: Binding(get: { session.gitEnabled }, set: { session.setGitEnabled($0) }))
                }
            }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
            Text(projectScope ? "Se guarda en .leonardomd/project.json. No contiene credenciales." : "Las preferencias globales se aplican al visor individual y a proyectos que las heredan.")
                .font(.caption).foregroundStyle(.secondary)
        }.buttonStyle(PremiumButtonStyle()).padding(24).frame(width: 520, height: 460)
        .onAppear { projectScope = session.projectURL != nil }
        .sheet(isPresented: $editingPalette) { PaletteEditor(session: session, projectScope: projectScope).modifier(SessionAppearance(session: session)) }
    }
}

extension PaperEffect {
    var title: String {
        switch self {
        case .white: "Hoja blanca"
        case .solid: "Color sólido"
        case .ruled: "Rayada"
        case .grid: "Cuadrícula"
        case .microgrid: "Microcuadrícula"
        case .parchment: "Pergamino"
        }
    }
}
