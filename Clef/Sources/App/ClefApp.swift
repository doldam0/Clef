import SwiftUI
import SwiftData

@main
struct ClefApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Score.self, PageAnnotation.self, Folder.self])
        .windowResizability(.contentMinSize)
    }
}
