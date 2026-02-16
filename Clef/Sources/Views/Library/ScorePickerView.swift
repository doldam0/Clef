import SwiftUI
import SwiftData

struct ScorePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var allScores: [Score]
    let program: Program
    var onAdded: (() -> Void)?

    @State private var searchText = ""
    @State private var selectedIds: Set<UUID> = []

    private var existingScoreIds: Set<UUID> {
        Set(program.orderedItems.compactMap { $0.score?.id })
    }

    private var filteredScores: [Score] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scores = allScores.filter { !existingScoreIds.contains($0.id) }
        guard !query.isEmpty else { return scores }
        return scores.filter { score in
            score.title.localizedCaseInsensitiveContains(query)
                || (score.composer?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allScores.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Scores"), systemImage: "music.note")
                    } description: {
                        Text(String(localized: "Import scores to your library first"))
                    }
                } else if filteredScores.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    scoreList
                }
            }
            .navigationTitle(String(localized: "Add Scores"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: String(localized: "Search Scores"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add") + " (\(selectedIds.count))") {
                        addSelectedScores()
                        dismiss()
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
    }

    private var scoreList: some View {
        List(filteredScores) { score in
            Button {
                toggleSelection(score)
            } label: {
                HStack(spacing: 12) {
                    ScoreThumbnail(score: score)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(score.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(score.composer ?? String(localized: "Unknown Composer"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: selectedIds.contains(score.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedIds.contains(score.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleSelection(_ score: Score) {
        if selectedIds.contains(score.id) {
            selectedIds.remove(score.id)
        } else {
            selectedIds.insert(score.id)
        }
    }

    private func addSelectedScores() {
        let scoresToAdd = allScores.filter { selectedIds.contains($0.id) }
        for score in scoresToAdd {
            program.appendScore(score)
        }
        try? modelContext.save()
        onAdded?()
    }
}

private struct ScoreThumbnail: View {
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
