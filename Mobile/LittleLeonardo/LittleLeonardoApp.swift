import SwiftUI

@main
struct LittleLeonardoApp: App {
    @State private var library = MobileLibrary()
    var body: some Scene {
        WindowGroup {
            MobileLibraryView(library: library)
                .task {
                    do {
                        let demo = MobileDemoStore()
                        for language in MobileDemoStore.Language.allCases { _ = try demo.load(language) }
                    } catch { library.error = error.localizedDescription }
                    await library.reload()
                }
        }
    }
}
