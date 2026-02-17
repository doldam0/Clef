import SwiftUI
import SwiftData

enum LibraryTab: Hashable {
    case recent
    case browse
}

struct ScoreLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var allScores: [Score]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    let tab: LibraryTab
    @Binding var searchText: String
    var onImport: () -> Void
    var onScoreTapped: (Score) -> Void
    var onProgramTapped: (Program) -> Void
    var onFolderTapped: (Folder) -> Void

    @State private var isSelecting = false
    @State private var selectedScoreIds: Set<UUID> = []
    @State private var showDeleteSelectedAlert = false
    @State private var editingScore: Score?
    @State private var deletingScore: Score?
    @State private var browseIsImporting = false
    @State private var browseIsCreatingFolder = false
    @State private var browseIsCreatingProgram = false

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var allTags: [String] {
        Array(Set(allScores.flatMap(\.tags))).sorted()
    }

    private var searchResults: [Score] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allScores }
        return allScores.filter { score in
            score.title.localizedCaseInsensitiveContains(query)
                || (score.composer?.localizedCaseInsensitiveContains(query) ?? false)
                || score.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectableScores: [Score] {
        if isSearchActive { return searchResults }
        switch tab {
        case .recent: return allScores
        case .browse: return allScores.filter { $0.folder == nil }
        }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        Group {
            if isSearchActive {
                searchResultsGrid
            } else {
                switch tab {
                case .recent:
                    RecentScoresView(
                        onScoreTapped: onScoreTapped,
                        onImport: onImport,
                        isSelecting: $isSelecting,
                        selectedScoreIds: $selectedScoreIds,
                        editingScore: $editingScore,
                        deletingScore: $deletingScore
                    )
                case .browse:
                    BrowseCatalogView(
                        folder: nil,
                        onScoreTapped: onScoreTapped,
                        onProgramTapped: onProgramTapped,
                        onFolderTapped: onFolderTapped,
                        isSelecting: $isSelecting,
                        selectedScoreIds: $selectedScoreIds,
                        isImporting: $browseIsImporting,
                        isCreatingFolder: $browseIsCreatingFolder,
                        isCreatingProgram: $browseIsCreatingProgram,
                        showsToolbar: false
                    )
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Scores")
        .toolbar {
            LibraryToolbar(
                isSelecting: $isSelecting,
                selectedScoreIds: $selectedScoreIds,
                showDeleteSelectedAlert: $showDeleteSelectedAlert,
                selectableScores: selectableScores,
                folders: folders,
                programs: programs,
                onImport: {
                    if tab == .browse && !isSearchActive {
                        browseIsImporting = true
                    } else {
                        onImport()
                    }
                },
                onCreateFolder: { browseIsCreatingFolder = true },
                onCreateProgram: { browseIsCreatingProgram = true },
                onMoveToFolder: { moveSelectedScores(to: $0) },
                onAddToProgram: { addSelectedScores(to: $0) }
            )
        }
        .alert("Delete Score", isPresented: .init(
            get: { deletingScore != nil },
            set: { if !$0 { deletingScore = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletingScore = nil }
            Button("Delete", role: .destructive) { confirmDeleteScore() }
        } message: {
            if let score = deletingScore {
                Text("Are you sure you want to delete \"\(score.title)\"? This cannot be undone.")
            }
        }
        .sheet(item: $editingScore) { score in
            ScoreMetadataEditorView(score: score, existingTags: allTags)
        }
        .alert("Delete Selected", isPresented: $showDeleteSelectedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteSelectedScores() }
        } message: {
            Text("Delete \(selectedScoreIds.count) scores? This cannot be undone.")
        }
        .scoreImporter(isPresented: $browseIsImporting)
    }

    // MARK: - Content

    private var searchResultsGrid: some View {
        ScrollView {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(searchResults) { score in
                        scoreCard(for: score)
                    }
                }
                .padding(16)
                .dragToSelect(selectedIds: $selectedScoreIds, isSelecting: isSelecting, orderedIds: searchResults.map(\.id))
            }
        }
    }

    // MARK: - Components

    private func scoreCard(for score: Score) -> some View {
        Button {
            if isSelecting {
                toggleSelection(score)
            } else {
                onScoreTapped(score)
            }
        } label: {
            ScoreCardView(score: score, isSelecting: isSelecting, isSelected: selectedScoreIds.contains(score.id))
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

    // MARK: - Actions

    private func toggleSelection(_ score: Score) {
        if selectedScoreIds.contains(score.id) {
            selectedScoreIds.remove(score.id)
        } else {
            selectedScoreIds.insert(score.id)
        }
    }

    private func moveSelectedScores(to folder: Folder?) {
        for score in allScores where selectedScoreIds.contains(score.id) {
            score.folder = folder
            score.updatedAt = .now
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }

    private func deleteSelectedScores() {
        for score in allScores where selectedScoreIds.contains(score.id) {
            modelContext.delete(score)
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }

    private func addSelectedScores(to program: Program) {
        for score in allScores where selectedScoreIds.contains(score.id) {
            program.appendScore(score)
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }

    private func confirmDeleteScore() {
        guard let score = deletingScore else { return }
        modelContext.delete(score)
        try? modelContext.save()
        deletingScore = nil
    }
}
