import SwiftUI

struct FileColorPreferences: View {
    @Bindable var session: AppSession
    let projectScope: Bool

    var body: some View {
        Group {
            if projectScope {
                Toggle(L10n.text("Inherit global file colors"), isOn: Binding(
                    get: { session.projectConfiguration.colorLeonardoFiles == nil },
                    set: { inherit in
                        session.projectConfiguration.colorLeonardoFiles = inherit ? nil : session.colorLeonardoFiles
                        session.persistSettings()
                    }))
            }
            Toggle(L10n.text("Color Leonardo files in wine"), isOn: Binding(
                get: { projectScope ? session.colorLeonardoFiles : session.globalPreferences.colorLeonardoFiles },
                set: { enabled in
                    if projectScope { session.projectConfiguration.colorLeonardoFiles = enabled }
                    else { session.globalPreferences.colorLeonardoFiles = enabled }
                    session.persistSettings()
                }))
                .disabled(projectScope && session.projectConfiguration.colorLeonardoFiles == nil)
                .accessibilityIdentifier("preferences-file-colors")
        }
    }
}
