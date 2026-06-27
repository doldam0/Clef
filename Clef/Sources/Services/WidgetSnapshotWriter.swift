import Foundation
import SwiftData
import WidgetKit

/// Builds the widget snapshot (recent scores + folders) and thumbnails from the
/// SwiftData store and writes them into the App Group container, then asks
/// WidgetKit to refresh.
@MainActor
enum WidgetSnapshotWriter {
    private static let recentLimit = 12
    private static let perFolderLimit = 12

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
            recent: recentScores.map(Self.widgetScore),
            folders: folders.map { folder in
                let scores = folder.scores
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(perFolderLimit)
                    .map(Self.widgetScore)
                return WidgetFolder(id: folder.id, name: folder.name, scores: Array(scores))
            }
        )

        // Cache thumbnails for every score the widget might show.
        var seen = Set<UUID>()
        let scoresNeedingThumbnails = (recentScores + folders.flatMap { Array($0.scores.prefix(perFolderLimit)) })
            .filter { seen.insert($0.id).inserted }
        await writeThumbnails(for: scoresNeedingThumbnails)

        if let data = try? JSONEncoder().encode(snapshot), let url = WidgetShared.snapshotURL {
            try? data.write(to: url, options: .atomic)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func widgetScore(_ score: Score) -> WidgetScore {
        WidgetScore(id: score.id, title: score.title, composer: score.composer)
    }

    private static func writeThumbnails(for scores: [Score]) async {
        guard let dir = WidgetShared.thumbnailsDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for score in scores {
            guard let url = WidgetShared.thumbnailURL(for: score.id),
                  !FileManager.default.fileExists(atPath: url.path)
            else { continue }

            if let image = await ThumbnailService.shared.thumbnail(for: score),
               let data = image.jpegData(compressionQuality: 0.7) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
