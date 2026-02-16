import SwiftUI
import SwiftData

@main
struct ClefApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([Score.self, PageAnnotation.self, Folder.self, Program.self, ProgramItem.self])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            Self.destroyStore()
            do {
                modelContainer = try ModelContainer(for: schema)
            } catch {
                fatalError("Failed to create ModelContainer after store reset: \(error)")
            }
        }
    }

    private static func destroyStore() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport.appendingPathComponent("default.store")
        for ext in ["", ".wal", ".shm"] {
            let url = ext.isEmpty ? storeURL : storeURL.appendingPathExtension(String(ext.dropFirst()))
            try? FileManager.default.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentMinSize)
    }
}
