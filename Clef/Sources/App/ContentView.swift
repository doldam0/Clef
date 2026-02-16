import SwiftUI
import SwiftData
import PDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var scores: [Score]
    @State private var isImporting = false
    @State private var navigationPath = NavigationPath()
    @State private var importedScoreForMetadata: Score?
    @State private var extractedMetadata: ExtractedMetadata?

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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $importedScoreForMetadata) { score in
            if let metadata = extractedMetadata {
                MetadataConfirmationView(score: score, extracted: metadata)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        var lastImportedScore: Score?

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let pdfData = try? Data(contentsOf: url) else { continue }

            let title = url.deletingPathExtension().lastPathComponent
            let score = Score(title: title, pdfData: pdfData)
            modelContext.insert(score)
            lastImportedScore = score
        }

        try? modelContext.save()

        if let score = lastImportedScore {
            Task {
                let metadata = await MetadataExtractor.shared.extract(from: score.pdfData)
                let hasDetectedData = metadata.title != nil
                    || metadata.composer != nil
                    || metadata.key != nil
                    || metadata.timeSignature != nil

                if hasDetectedData {
                    extractedMetadata = metadata
                    importedScoreForMetadata = score
                }
            }
        }
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
