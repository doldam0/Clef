import SwiftUI
import SwiftData

struct RecentScoresView: View {
    @Query(sort: \Score.updatedAt, order: .reverse) private var allScores: [Score]

    let onScoreTapped: (Score) -> Void
    let onImport: () -> Void
    @Binding var isSelecting: Bool
    @Binding var selectedScoreIds: Set<UUID>
    @Binding var editingScore: Score?
    @Binding var deletingScore: Score?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            if allScores.isEmpty {
                emptyLibraryView
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(allScores) { score in
                        scoreCard(for: score)
                    }
                }
                .padding(16)
                .dragToSelect(
                    selectedIds: $selectedScoreIds,
                    isSelecting: isSelecting,
                    orderedIds: allScores.map(\.id)
                )
            }
        }
    }

    private func scoreCard(for score: Score) -> some View {
        Button {
            if isSelecting {
                if selectedScoreIds.contains(score.id) {
                    selectedScoreIds.remove(score.id)
                } else {
                    selectedScoreIds.insert(score.id)
                }
            } else {
                onScoreTapped(score)
            }
        } label: {
            ScoreCardView(
                score: score,
                isSelecting: isSelecting,
                isSelected: selectedScoreIds.contains(score.id)
            )
        }
        .buttonStyle(.plain)
        .dragSelectFrame(id: score.id)
        .scoreContextMenu(
            score: score,
            isSelecting: isSelecting,
            onEdit: { editingScore = $0 },
            onDelete: { deletingScore = $0 }
        )
    }

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("No Scores", systemImage: "music.note")
        } description: {
            Text("Import PDF sheet music to get started")
        } actions: {
            Button(action: onImport) {
                Text("Import Score")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
