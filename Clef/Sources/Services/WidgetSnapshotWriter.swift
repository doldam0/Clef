import Foundation
import SwiftData
import WidgetKit

/// Builds the widget snapshot (recent scores + folders with their contents) and
/// thumbnails from the SwiftData store and writes them into the App Group
/// container, then asks WidgetKit to refresh.
@MainActor
enum WidgetSnapshotWriter {
    private static let recentLimit = 12
    private static let perFolderLimit = 16

    static func update(using context: ModelContext) async {
        guard WidgetShared.containerURL != nil else { return }

        var recentDescriptor = FetchDescriptor<Score>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = recentLimit
        let recentScores = (try? context.fetch(recentDescriptor)) ?? []

        let folders = (try? context.fetch(
            FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)])
        )) ?? []

        let snapshot = WidgetSnapshot(
            recent: recentScores.map { WidgetItem(id: $0.id, kind: .score, title: $0.title) },
            folders: folders.map { folder in
                WidgetFolder(id: folder.id, name: folder.name, items: items(in: folder))
            }
        )

        await writeThumbnails(for: scoreIDs(in: snapshot), context: context)

        if let data = try? JSONEncoder().encode(snapshot), let url = WidgetShared.snapshotURL {
            try? data.write(to: url, options: .atomic)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Subfolders, then programs, then scores — matching the Browse view order.
    private static func items(in folder: Folder) -> [WidgetItem] {
        let subfolders = folder.children
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { WidgetItem(id: $0.id, kind: .folder, title: $0.name) }

        let programs = folder.programs
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { WidgetItem(id: $0.id, kind: .program, title: $0.name) }

        let scores = folder.scores
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { WidgetItem(id: $0.id, kind: .score, title: $0.title) }

        return Array((subfolders + programs + scores).prefix(perFolderLimit))
    }

    private static func scoreIDs(in snapshot: WidgetSnapshot) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in snapshot.recent where item.kind == .score { ids.insert(item.id) }
        for folder in snapshot.folders {
            for item in folder.items where item.kind == .score { ids.insert(item.id) }
        }
        return ids
    }

    private static func writeThumbnails(for ids: Set<UUID>, context: ModelContext) async {
        guard let dir = WidgetShared.thumbnailsDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for id in ids {
            guard let url = WidgetShared.thumbnailURL(for: id),
                  !FileManager.default.fileExists(atPath: url.path)
            else { continue }

            var descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let score = try? context.fetch(descriptor).first else { continue }

            if let image = await ThumbnailService.shared.thumbnail(for: score),
               let data = image.jpegData(compressionQuality: 0.7) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
