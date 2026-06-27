import WidgetKit
import SwiftUI

// MARK: - Recent Scores widget

struct RecentEntry: TimelineEntry {
    let date: Date
    let scores: [WidgetScore]
}

struct RecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentEntry {
        RecentEntry(date: Date(), scores: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
        completion(RecentEntry(date: Date(), scores: recentScores()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        completion(Timeline(entries: [RecentEntry(date: Date(), scores: recentScores())], policy: .never))
    }

    private func recentScores() -> [WidgetScore] {
        Array((WidgetShared.loadSnapshot()?.recent ?? []).prefix(8))
    }
}

struct RecentScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.recentWidgetKind, provider: RecentProvider()) { entry in
            ScoreGridView(title: "Recent", systemImage: "clock", scores: entry.scores)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Scores")
        .description("Your recently opened scores.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Folder widget

struct FolderEntry: TimelineEntry {
    let date: Date
    let title: String
    let scores: [WidgetScore]
}

struct FolderProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FolderEntry {
        FolderEntry(date: Date(), title: "Folder", scores: [])
    }

    func snapshot(for configuration: SelectFolderIntent, in context: Context) async -> FolderEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectFolderIntent, in context: Context) async -> Timeline<FolderEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SelectFolderIntent) -> FolderEntry {
        let snapshot = WidgetShared.loadSnapshot()
        guard let id = configuration.folder?.id,
              let folder = snapshot?.folders.first(where: { $0.id == id })
        else {
            return FolderEntry(date: Date(), title: configuration.folder?.name ?? "Folder", scores: [])
        }
        return FolderEntry(date: Date(), title: folder.name, scores: Array(folder.scores.prefix(8)))
    }
}

struct FolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetShared.folderWidgetKind,
            intent: SelectFolderIntent.self,
            provider: FolderProvider()
        ) { entry in
            ScoreGridView(title: entry.title, systemImage: "folder", scores: entry.scores)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Folder")
        .description("Scores in a folder you choose.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Shared view

struct ScoreGridView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let systemImage: String
    let scores: [WidgetScore]

    private var columns: Int { family == .systemSmall ? 2 : 4 }

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 4
        default: return 8
        }
    }

    private var smallWidgetURL: URL? {
        family == .systemSmall ? scores.first.map { WidgetShared.scoreURL($0.id) } : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if scores.isEmpty {
                Spacer()
                Text("No scores yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                    spacing: 8
                ) {
                    ForEach(scores.prefix(maxItems)) { score in
                        cell(for: score)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(smallWidgetURL)
    }

    @ViewBuilder
    private func cell(for score: WidgetScore) -> some View {
        // Small widgets allow only a single tap target (widgetURL above), so
        // their cells aren't individually linked.
        if family == .systemSmall {
            ScoreCell(score: score)
        } else {
            Link(destination: WidgetShared.scoreURL(score.id)) {
                ScoreCell(score: score)
            }
        }
    }
}

private struct ScoreCell: View {
    let score: WidgetScore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            thumbnail
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(verbatim: score.title)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = WidgetShared.thumbnailURL(for: score.id),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                )
        }
    }
}
