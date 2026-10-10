import SwiftUI

@main
struct LittleLeonardoApp: App {
    @State private var library = MobileLibrary()
    var body: some Scene {
        WindowGroup {
            MobileLibraryView(library: library)
                .task { await library.reload() }
        }
    }
}
