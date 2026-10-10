import SwiftUI
import LeonardoCore

struct PreferencesView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var projectScope = false
    @State private var editingPalette = false
    @State private var selectedTab = "general"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.text("Preferences")).font(.title2.bold())
                Spacer()
                Button(L10n.text("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                @Bindable var languages = LanguageSettings.shared
                Picker(L10n.text("Language"), selection: $languages.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }.accessibilityIdentifier("interface-language")
            }
            Text(L10n.text("Interface language applies to all windows."))
                .font(.caption).foregroundStyle(.secondary)
            if session.projectURL != nil {
                PremiumSelection(selection: $projectScope, options: [false, true], title: { $0 ? L10n.text("This project") : L10n.text("Global") })
                    .accessibilityLabel(L10n.text("Scope"))
            }
            TabView(selection: $selectedTab) {
                generalPreferences.tag("general").tabItem { Label(L10n.text("General"), systemImage: "gearshape") }
                ExtensionPreferences(session: session, projectScope: projectScope)
                    .tag("extensions").tabItem { Label(L10n.text("Extensions"), systemImage: "puzzlepiece.extension") }
                MobileSyncPreferencesView(session: session, controller: .shared)
                    .tag("mobile").tabItem { Label("Little Leonardo", systemImage: "iphone") }
                DesktopPeerPreferencesView(session: session, controller: .shared)
                    .tag("peers").tabItem { Label(L10n.text("Linked Macs"), systemImage: "desktopcomputer") }
            }
            Text((selectedTab == "mobile" || selectedTab == "peers") ? L10n.text("Service and device settings belong to this Mac.") : projectScope ? L10n.text("Saved in .leonardomd/project.json. Contains no credentials.") : L10n.text("Global preferences apply to the standalone viewer and projects that inherit them."))
                .font(.caption).foregroundStyle(.secondary)
        }.buttonStyle(PremiumButtonStyle()).padding(24).frame(width: 580, height: 620)
        .onAppear { projectScope = session.projectURL != nil }
        .sheet(isPresented: $editingPalette) { PaletteEditor(session: session, projectScope: projectScope).modifier(SessionAppearance(session: session)) }
    }

    private var generalPreferences: some View {
            Form {
                Picker(L10n.text("Palette"), selection: Binding(get: { projectScope ? session.projectConfiguration.palette?.rawValue ?? "inherit" : session.globalPreferences.palette.rawValue }, set: { session.setPalette($0, project: projectScope) })) {
                    if projectScope { Text(L10n.text("Inherit global")).tag("inherit") }
                    ForEach(PaletteCatalog.all) { palette in Text(palette.displayName).tag(palette.id.rawValue) }
                }
                Picker(L10n.text("Paper effect"), selection: Binding(get: { projectScope ? session.projectConfiguration.paperEffect?.rawValue ?? "inherit" : session.globalPreferences.paperEffect.rawValue }, set: { session.setPaper($0, project: projectScope) })) {
                    if projectScope { Text(L10n.text("Inherit global")).tag("inherit") }
                    ForEach(PaperEffect.allCases, id: \.self) { effect in Text(effect.title).tag(effect.rawValue) }
                }
                Button(L10n.text("Customize / import palette…")) { editingPalette = true }
                Toggle(L10n.text("Show front matter"), isOn: $session.showFrontmatter)
                Toggle(L10n.text("Confirm external links"), isOn: $session.confirmExternalLinks)
                Toggle(L10n.text("Show hidden files"), isOn: $session.showHidden)
                if projectScope {
                    Toggle(L10n.text("Enable Git tools"), isOn: Binding(get: { session.gitEnabled }, set: { session.setGitEnabled($0) }))
                }
            }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
    }
}

extension PaperEffect {
    @MainActor var title: String {
        switch self {
        case .white: L10n.text("White paper")
        case .solid: L10n.text("Solid color")
        case .ruled: L10n.text("Ruled")
        case .grid: L10n.text("Grid")
        case .microgrid: L10n.text("Microgrid")
        case .parchment: L10n.text("Parchment")
        }
    }
}
