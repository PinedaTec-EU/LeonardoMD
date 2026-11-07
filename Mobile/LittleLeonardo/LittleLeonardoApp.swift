import SwiftUI

@main
struct LittleLeonardoApp: App {
    @State private var library = MobileLibrary()
    @State private var ready = false

    init() { MobileClassic.configureAppearance() }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if ready { MobileLibraryView(library: library) }
                else { MobileStartupView() }
            }
            .tint(MobileClassic.accent)
            .preferredColorScheme(.light)
            .task {
                do {
                    let demo = MobileDemoStore()
                    for language in MobileDemoStore.Language.allCases { _ = try demo.load(language) }
                } catch { library.error = error.localizedDescription }
                await library.reload()
                ready = true
            }
        }
    }
}
