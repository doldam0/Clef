import WidgetKit
import SwiftUI

// MARK: - Recent Scores widget

struct RecentEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
}

struct RecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentEntry {
        RecentEntry(date: Date(), items: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
        completion(RecentEntry(date: Date(), items: recentItems()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        completion(Timeline(entries: [RecentEntry(date: Date(), items: recentItems())], policy: .never))
    }

    private func recentItems() -> [WidgetItem] {
        WidgetShared.loadSnapshot()?.recent ?? []
    }
}

struct RecentScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.recentWidgetKind, provider: RecentProvider()) { entry in
            ItemGridView(header: Text("Recent"), systemImage: "clock", items: entry.items)
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
    let items: [WidgetItem]
}

struct FolderProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FolderEntry {
        FolderEntry(date: Date(), title: "Folder", items: [])
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
            return FolderEntry(date: Date(), title: configuration.folder?.name ?? "", items: [])
        }
        return FolderEntry(date: Date(), title: folder.name, items: folder.items)
    }
}

struct FolderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetShared.folderWidgetKind,
            intent: SelectFolderIntent.self,
            provider: FolderProvider()
        ) { entry in
            ItemGridView(header: Text(verbatim: entry.title), systemImage: "folder", items: entry.items)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Folder")
        .description("Subfolders, programs, and scores in a folder you choose.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Shared view

struct ItemGridView: View {
    @Environment(\.widgetFamily) private var family
    /// Localized for the Recent widget; the raw folder name for the Folder widget.
    let header: Text
    let systemImage: String
    let items: [WidgetItem]

    private var columns: Int { family == .systemSmall ? 2 : 4 }

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 4
        default: return 8
        }
    }

    private var smallWidgetURL: URL? {
        family == .systemSmall ? items.first.map(WidgetShared.deepLink) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { header } icon: { Image(systemName: systemImage) }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if items.isEmpty {
                Spacer()
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                    spacing: 8
                ) {
                    ForEach(items.prefix(maxItems)) { item in
                        cell(for: item)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(smallWidgetURL)
    }

    @ViewBuilder
    private func cell(for item: WidgetItem) -> some View {
        // Small widgets allow only a single tap target (widgetURL above), so
        // their cells aren't individually linked.
        if family == .systemSmall {
            ItemCell(item: item)
        } else {
            Link(destination: WidgetShared.deepLink(item)) {
                ItemCell(item: item)
            }
        }
    }
}

private struct ItemCell: View {
    let item: WidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            artwork
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(verbatim: item.title)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch item.kind {
        case .score:
            if let url = WidgetShared.thumbnailURL(for: item.id),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                iconTile("music.note")
            }
        case .folder:
            iconTile("folder.fill")
        case .program:
            iconTile("music.note.list")
        }
    }

    private func iconTile(_ systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .overlay(
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}
