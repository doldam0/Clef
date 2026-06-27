import Foundation

/// A PDF ready to be imported. The bytes are read up front so importing doesn't
/// depend on a security-scoped URL still being valid later, and the title is
/// preserved from the original file name.
struct ImportFile: Identifiable {
    let id = UUID()
    let title: String
    let data: Data
}

/// Holds files received via "Open in Clef" until the UI can ask where to put
/// them. A singleton because the scene delegate (UIKit) and the SwiftUI view
/// hierarchy both need to reach it.
@MainActor
final class ImportInbox: ObservableObject {
    static let shared = ImportInbox()

    @Published var pending: [ImportFile] = []

    private init() {}

    func add(_ files: [ImportFile]) {
        pending.append(contentsOf: files)
    }

    func take() -> [ImportFile] {
        let files = pending
        pending.removeAll()
        return files
    }

    func clear() {
        pending.removeAll()
    }

    /// Reads incoming file URLs into `ImportFile`s, skipping non-PDFs and
    /// unreadable files. Files the system copied into our Inbox are removed
    /// after reading; open-in-place originals are left untouched.
    nonisolated static func read(_ urls: [URL]) -> [ImportFile] {
        var files: [ImportFile] = []
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            files.append(ImportFile(title: title, data: data))

            if url.path.contains("/Inbox/") {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return files
    }
}
