import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Score.updatedAt, order: .reverse) private var scores: [Score]
    @State private var isImporting = false
    @State private var navigationPath = NavigationPath()

    private var allTags: [String] {
        Array(Set(scores.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScoreLibraryView(
                onImport: { isImporting = true },
                onScoreTapped: { score in
                    navigationPath.append(ScoreNavigation.reader(score.id))
                },
                onProgramTapped: { program in
                    navigationPath.append(ProgramNavigation.detail(program.id))
                }
            )
            .navigationDestination(for: ScoreNavigation.self) { nav in
                switch nav {
                case .reader(let scoreId):
                    if let score = scores.first(where: { $0.id == scoreId }) {
                        ScoreReaderView(score: score, allTags: allTags)
                    }
                }
            }
            .navigationDestination(for: ProgramNavigation.self) { nav in
                switch nav {
                case .detail(let programId):
                    ProgramDestinationView(
                        programId: programId,
                        allTags: allTags,
                        onScoreTapped: { score in
                            navigationPath.append(ScoreNavigation.reader(score.id))
                        },
                        onPlayProgram: { program in
                            navigationPath.append(ProgramNavigation.play(program.id))
                        }
                    )
                case .play(let programId):
                    ProgramPlayerDestinationView(
                        programId: programId,
                        allTags: allTags
                    )
                }
            }
        }
        .scoreImporter(isPresented: $isImporting)
    }
}

// MARK: - Navigation Types

enum ScoreNavigation: Hashable {
    case reader(UUID)
}

enum ProgramNavigation: Hashable {
    case detail(UUID)
    case play(UUID)
}

// MARK: - Program Destination Wrappers

private struct ProgramDestinationView: View {
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    let programId: UUID
    let allTags: [String]
    let onScoreTapped: (Score) -> Void
    let onPlayProgram: (Program) -> Void

    var body: some View {
        if let program = programs.first(where: { $0.id == programId }) {
            ProgramDetailView(
                program: program,
                onScoreTapped: onScoreTapped,
                onPlayProgram: onPlayProgram
            )
        } else {
            ContentUnavailableView(
                "Program Not Found",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

private struct ProgramPlayerDestinationView: View {
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    let programId: UUID
    let allTags: [String]

    var body: some View {
        if let program = programs.first(where: { $0.id == programId }) {
            ProgramPlayerView(program: program, allTags: allTags)
        } else {
            ContentUnavailableView(
                "Program Not Found",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}
