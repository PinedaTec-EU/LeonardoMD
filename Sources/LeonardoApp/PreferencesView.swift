import SwiftUI
import LeonardoCore

struct PreferencesView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var projectScope = false
    @State private var editingPalette = false
    @State private var selectedTab: String
    private let associations: MarkdownAssociations
    private let updates: ApplicationUpdates

    init(session: AppSession, updates: ApplicationUpdates = .shared, associations: MarkdownAssociations = .shared, selectedTab: String = "general") {
        self.session = session
        self.updates = updates
        self.associations = associations
        _selectedTab = State(initialValue: selectedTab)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.text("Preferences")).font(.title2.bold())
                Spacer()
                Button(L10n.text("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TabView(selection: $selectedTab) {
                generalPreferences.tag("general").tabItem { Label(L10n.text("General"), systemImage: "gearshape") }
                VStack(spacing: 0) {
                    scopeHeader("Extensions")
                    ExtensionPreferences(session: session, projectScope: projectScope)
                }
                .tag("extensions").tabItem { Label(L10n.text("Extensions"), systemImage: "puzzlepiece.extension") }
                macPreferences("Service and device settings belong to this Mac.") {
                    MobileSyncPreferencesView(session: session, controller: .shared)
                }
                    .tag("mobile").tabItem { Label("Little Leonardo", systemImage: "iphone") }
                macPreferences("Service and device settings belong to this Mac.") {
                    DesktopPeerPreferencesView(session: session, controller: .shared)
                }
                    .tag("peers").tabItem { Label(L10n.text("Linked Macs"), systemImage: "desktopcomputer") }
                macPreferences("Update preferences apply to all windows on this Mac.") {
                    UpdatePreferencesView(updates: updates)
                }
                    .tag("updates").tabItem { Label(L10n.text("Updates"), systemImage: "arrow.triangle.2.circlepath") }
            }
        }.buttonStyle(PremiumButtonStyle()).padding(24).frame(width: 580, height: 620)
        .onAppear { projectScope = session.projectURL != nil }
        .onChange(of: session.projectURL) { _, root in
            if root == nil { projectScope = false }
        }
        .sheet(isPresented: $editingPalette) { PaletteEditor(session: session, projectScope: projectScope).modifier(SessionAppearance(session: session)) }
    }

    private func macPreferences<Content: View>(_ explanation: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(L10n.text(explanation)).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    private func scopeHeader(_ title: String) -> some View {
        PreferencesScopeHeader(title: title, projectURL: session.projectURL, projectScope: $projectScope)
    }

    private var generalPreferences: some View {
        VStack(spacing: 0) {
            scopeHeader("General")
            Form {
                Section(L10n.text("Appearance")) {
                    appearancePreferences
                    if projectScope {
                        Text(L10n.text("Saved in .leonardomd/project.json. Contains no credentials."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L10n.text("On this Mac")) {
                    @Bindable var languages = LanguageSettings.shared
                    Picker(L10n.text("Language"), selection: $languages.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                        }
                    }.accessibilityIdentifier("interface-language")
                    Text(L10n.text("Interface language applies to all windows."))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker(L10n.text("When opening an MDLZ package"), selection: Binding(get: { session.packageOpenPreference }, set: { session.packageOpenPreference = $0 })) {
                        ForEach(LeonardoPackageOpenPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    Toggle(L10n.text("Migrate Markdown to MDLF when saving"), isOn: Binding(get: { session.migrateMarkdownOnSave }, set: { session.migrateMarkdownOnSave = $0 }))
                    Toggle(L10n.text("Show front matter"), isOn: $session.showFrontmatter)
                    Toggle(L10n.text("Confirm external links"), isOn: $session.confirmExternalLinks)
                    Toggle(L10n.text("Show hidden files"), isOn: $session.showHidden)
                }
                MarkdownAssociationPreferences(associations: associations)
            }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
        }
    }

    private var appearancePreferences: some View {
        Group {
            Picker(L10n.text("Palette"), selection: Binding(get: { projectScope ? session.projectConfiguration.palette?.rawValue ?? "inherit" : session.globalPreferences.palette.rawValue }, set: { session.setPalette($0, project: projectScope) })) {
                if projectScope { Text(L10n.text("Inherit global")).tag("inherit") }
                ForEach(PaletteCatalog.all) { palette in Text(palette.displayName).tag(palette.id.rawValue) }
            }.accessibilityIdentifier("preferences-palette")
            Picker(L10n.text("Paper effect"), selection: Binding(get: { projectScope ? session.projectConfiguration.paperEffect?.rawValue ?? "inherit" : session.globalPreferences.paperEffect.rawValue }, set: { session.setPaper($0, project: projectScope) })) {
                if projectScope { Text(L10n.text("Inherit global")).tag("inherit") }
                ForEach(PaperEffect.allCases, id: \.self) { effect in Text(effect.title).tag(effect.rawValue) }
            }.accessibilityIdentifier("preferences-paper")
            Button(L10n.text("Customize / import palette…")) { editingPalette = true }
            if projectScope {
                Toggle(L10n.text("Enable Git tools"), isOn: Binding(get: { session.gitEnabled }, set: { session.setGitEnabled($0) }))
            }
        }
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
