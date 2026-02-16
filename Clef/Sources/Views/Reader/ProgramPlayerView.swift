import SwiftUI
import SwiftData

struct ProgramPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let allTags: [String]

    @State private var currentScore: Score?
    @State private var showingEndAlert = false

    var body: some View {
        Group {
            if let score = currentScore {
                ScoreReaderView(score: score, allTags: allTags, onReachedEnd: advanceToNext)
                    .id(score.id)
                    .overlay(alignment: .topTrailing) {
                        if let positionText {
                            Text(positionText)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 12)
                                .padding(.trailing, 12)
                        }
                    }
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
        .alert("End of Program", isPresented: $showingEndAlert) {
            Button("Replay") {
                currentScore = program.orderedScores.first
            }
            Button("Close", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("You reached the end of \(program.name).")
        }
    }

    private var orderedScores: [Score] {
        program.orderedScores
    }

    private var positionText: String? {
        guard let currentScore,
              let index = orderedScores.firstIndex(where: { $0.id == currentScore.id }) else {
            return nil
        }
        return "\(index + 1) of \(orderedScores.count)"
    }

    private func advanceToNext() {
        guard let currentScore else { return }

        if let nextScore = program.nextScore(after: currentScore) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.currentScore = nextScore
            }
            return
        }

        showingEndAlert = true
    }
}
