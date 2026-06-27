import Foundation

/// Shared between the app and the widget extension (this file must belong to
/// both targets). The app writes a lightweight snapshot of the library into the
/// App Group container; the widget reads it. This keeps the widget out of the
/// main SwiftData store entirely.
enum WidgetShared {
    static let appGroupID = "group.com.doldam0.Clef"
    static let recentWidgetKind = "ClefRecentWidget"
    static let folderWidgetKind = "ClefFolderWidget"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget_snapshot.json")
    }

    static var thumbnailsDirectory: URL? {
        containerURL?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static func thumbnailURL(for id: UUID) -> URL? {
        thumbnailsDirectory?.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Deep link a widget item opens in the app (handled in ContentView).
    static func deepLink(_ item: WidgetItem) -> URL {
        URL(string: "clef://\(item.kind.rawValue)/\(item.id.uuidString)")!
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

struct WidgetSnapshot: Codable {
    var recent: [WidgetItem] = []
    var folders: [WidgetFolder] = []
}

/// A folder/program/score entry as shown in a widget.
struct WidgetItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case folder
        case program
        case score
    }

    var id: UUID
    var kind: Kind
    var title: String
}

struct WidgetFolder: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Subfolders, then programs, then scores — the order shown in the widget.
    var items: [WidgetItem]
}
