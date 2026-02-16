import SwiftUI
import SwiftData
import PDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var scores: [Score]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var selectedScore: Score?
    @State private var isImporting = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showThumbnails = false
    @State private var currentPageIndex = 0
    @State private var selectedTags: Set<String> = []

    private var allTags: [String] {
        Array(Set(scores.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ScoreLibraryView(
                scores: scores,
                folders: folders,
                selectedScore: selectedScore,
                allTags: allTags,
                selectedTags: $selectedTags,
                onImport: { isImporting = true },
                onDelete: deleteScores,
                onScoreTapped: handleScoreTap
            )
        } detail: {
            if let score = selectedScore {
                ScoreReaderView(
                    score: score,
                    currentPageIndex: $currentPageIndex,
                    showThumbnails: $showThumbnails,
                    columnVisibility: $columnVisibility,
                    allTags: allTags
                )
                .id(score.id)
            } else {
                ContentUnavailableView {
                    Label("악보 선택", systemImage: "music.note.list")
                } description: {
                    Text("사이드바에서 악보를 선택하거나 새 악보를 가져오세요.")
                } actions: {
                    Button("악보 가져오기") {
                        isImporting = true
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
    }

    private func handleScoreTap(_ score: Score) {
        if selectedScore == score {
            showThumbnails.toggle()
        } else {
            selectedScore = score
            currentPageIndex = 0
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
