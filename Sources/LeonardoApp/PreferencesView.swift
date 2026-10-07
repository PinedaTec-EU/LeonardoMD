import SwiftUI
import LeonardoCore

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
            TabView {
                generalPreferences.tabItem { Label("General", systemImage: "gearshape") }
                ExtensionPreferences(session: session, projectScope: projectScope)
                    .tabItem { Label("Extensiones", systemImage: "puzzlepiece.extension") }
            }
            Text(projectScope ? "Se guarda en .leonardomd/project.json. No contiene credenciales." : "Las preferencias globales se aplican al visor individual y a proyectos que las heredan.")
                .font(.caption).foregroundStyle(.secondary)
        }.buttonStyle(PremiumButtonStyle()).padding(24).frame(width: 580, height: 540)
        .onAppear { projectScope = session.projectURL != nil }
        .sheet(isPresented: $editingPalette) { PaletteEditor(session: session, projectScope: projectScope).modifier(SessionAppearance(session: session)) }
    }

    private var generalPreferences: some View {
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
                    Toggle("Activar herramientas Git", isOn: Binding(get: { session.gitEnabled }, set: { session.setGitEnabled($0) }))
                }
            }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
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
