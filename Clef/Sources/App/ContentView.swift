import SwiftUI
import SwiftData
import PDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var scores: [Score]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var isImporting = false
    @State private var selectedTags: Set<String> = []
    @State private var navigationPath = NavigationPath()

    private var allTags: [String] {
        Array(Set(scores.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScoreLibraryView(
                scores: scores,
                folders: folders,
                allTags: allTags,
                selectedTags: $selectedTags,
                onImport: { isImporting = true },
                onDelete: deleteScores,
                onScoreTapped: { score in
                    navigationPath.append(score.id)
                }
            )
            .navigationDestination(for: UUID.self) { scoreId in
                if let score = scores.first(where: { $0.id == scoreId }) {
                    ScoreReaderView(
                        score: score,
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
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let pdfData = try? Data(contentsOf: url) else { continue }

            let title = url.deletingPathExtension().lastPathComponent
            let score = Score(title: title, pdfData: pdfData)
            modelContext.insert(score)
        }

        try? modelContext.save()
    }

    private func deleteScores(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scores[index])
        }
        try? modelContext.save()
    }
}
