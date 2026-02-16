import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var program: Program
    var onScoreTapped: (Score) -> Void
    var onPlayProgram: (Program) -> Void

    @State private var isImporting = false

    var body: some View {
        Group {
            if program.orderedItems.isEmpty {
                ContentUnavailableView {
                    Label("No Scores", systemImage: "music.note.list")
                } description: {
                    Text("Add scores to this program")
                } actions: {
                    Button(String(localized: "Import Score")) {
                        isImporting = true
                    }
                }
            } else {
                List {
                    ForEach(program.orderedItems) { item in
                        if let score = item.score {
                            Button {
                                onScoreTapped(score)
                            } label: {
                                ProgramScoreRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove(perform: moveItems)
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .navigationTitle(program.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    onPlayProgram(program)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    isImporting = true
                } label: {
                    Label(String(localized: "Import Score"), systemImage: "doc.badge.plus")
                }
            }
        }
        .scoreImporter(isPresented: $isImporting, program: program)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        program.moveItems(from: source, to: destination)
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { program.orderedItems[$0] }
        for item in itemsToDelete {
            if let score = item.score {
                program.removeScore(score)
            }
        }
        try? modelContext.save()
    }
}

private struct ProgramScoreRow: View {
    let item: ProgramItem

    var body: some View {
        HStack(spacing: 12) {
            Text("\(item.position + 1).")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            if let score = item.score {
                ScoreThumbnailView(score: score)

                VStack(alignment: .leading, spacing: 4) {
                    Text(score.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(score.composer ?? "Unknown Composer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.2))
                    .frame(width: 44, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Missing Score")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("This score is unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct ScoreThumbnailView: View {
    let score: Score

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 44, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: score.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: score)
        }
    }
}


