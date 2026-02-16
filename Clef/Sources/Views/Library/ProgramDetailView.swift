import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var program: Program
    @Query(sort: \Score.title) private var allScores: [Score]
    var onScoreTapped: (Score) -> Void
    var onPlayProgram: (Program) -> Void

    @State private var isShowingScorePicker = false

    private var availableScores: [Score] {
        let existingIDs = Set(program.orderedScores.map(\.id))
        return allScores.filter { !existingIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if program.orderedItems.isEmpty {
                ContentUnavailableView {
                    Label("No Scores", systemImage: "music.note.list")
                } description: {
                    Text("Add scores to this program")
                } actions: {
                    Button("Add Scores") {
                        isShowingScorePicker = true
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

                Button("Add Scores") {
                    isShowingScorePicker = true
                }
            }
        }
        .sheet(isPresented: $isShowingScorePicker) {
            ScorePickerSheet(availableScores: availableScores) { scores in
                addScores(scores)
            }
        }
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

    private func addScores(_ scores: [Score]) {
        for score in scores {
            program.appendScore(score)
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

private struct ScorePickerSheet: View {
    let availableScores: [Score]
    let onAdd: ([Score]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedScores: Set<UUID> = []
    @State private var searchText = ""

    private var filteredScores: [Score] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableScores }

        return availableScores.filter { score in
            score.title.localizedCaseInsensitiveContains(trimmed)
                || (score.composer?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Text("Add Scores")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    let selected = availableScores.filter { selectedScores.contains($0.id) }
                    onAdd(selected)
                    dismiss()
                }
                .disabled(selectedScores.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            if filteredScores.isEmpty {
                ContentUnavailableView {
                    Label("No Scores", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search")
                }
            } else {
                List(filteredScores) { score in
                    Button {
                        toggleSelection(for: score)
                    } label: {
                        HStack(spacing: 12) {
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

                            Spacer()

                            Image(systemName: selectedScores.contains(score.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedScores.contains(score.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $searchText, prompt: "Search scores")
            }
        }
    }

    private func toggleSelection(for score: Score) {
        if selectedScores.contains(score.id) {
            selectedScores.remove(score.id)
        } else {
            selectedScores.insert(score.id)
        }
    }
}
