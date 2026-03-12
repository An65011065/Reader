import SwiftUI

@main
struct LineaApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings = ReadingSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(settings)
        }
    }
}
