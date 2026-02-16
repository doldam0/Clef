import SwiftUI
import SwiftData

struct ProgramPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let allTags: [String]

    @State private var currentScore: Score?

    var body: some View {
        Group {
            if let score = currentScore {
                scoreReaderView(for: score)
            } else {
                ContentUnavailableView(
                    "No Scores in Program",
                    systemImage: "music.note.list",
                    description: Text("Add at least one score to play this program.")
                )
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if currentScore == nil {
                currentScore = program.orderedScores.first
            }
        }
    }

    private func scoreReaderView(for score: Score) -> some View {
        let nextAction: (() -> Void)? = hasNext ? { advanceToNext() } : nil
        let prevAction: (() -> Void)? = hasPrevious ? { goToPrevious() } : nil
        let swipeEndAction: (() -> Void)? = hasNext ? { advanceToNext() } : nil
        let swipeStartAction: (() -> Void)? = hasPrevious ? { goToPrevious() } : nil

        return ScoreReaderView(
            score: score,
            allTags: allTags,
            onSwipePastEnd: swipeEndAction,
            onSwipePastStart: swipeStartAction,
            onNextScore: nextAction,
            onPreviousScore: prevAction,
            programScores: orderedScores,
            onSelectProgramScore: { selected in
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentScore = selected
                }
            }
        )
        .id(score.id)
    }

    private var orderedScores: [Score] {
        program.orderedScores
    }

    private var currentIndex: Int? {
        guard let currentScore else { return nil }
        return orderedScores.firstIndex(where: { $0.id == currentScore.id })
    }

    private var hasNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex + 1 < orderedScores.count
    }

    private var hasPrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    private func advanceToNext() {
        guard let currentScore,
              let nextScore = program.nextScore(after: currentScore) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            self.currentScore = nextScore
        }
    }

    private func goToPrevious() {
        guard let currentIndex, currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentScore = orderedScores[currentIndex - 1]
        }
    }
}
