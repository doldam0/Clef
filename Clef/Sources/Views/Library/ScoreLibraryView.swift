import SwiftUI
import SwiftData

private enum LibraryTab: Hashable {
    case recent
    case browse
}

struct ScoreLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var allScores: [Score]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    var onImport: () -> Void
    var onScoreTapped: (Score) -> Void
    var onProgramTapped: (Program) -> Void
    var onFolderTapped: (Folder) -> Void

    @State private var selectedTab: LibraryTab = .recent
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedScoreIds: Set<UUID> = []
    @State private var showDeleteSelectedAlert = false
    @State private var editingScore: Score?
    @State private var deletingScore: Score?

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

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        Group {
            if isSearchActive {
                searchResultsGrid
            } else {
                TabView(selection: $selectedTab) {
                    Tab(String(localized: "Recent"), systemImage: "clock", value: .recent) {
                        recentTab
                    }
                    Tab(String(localized: "Browse"), systemImage: "folder", value: .browse) {
                        BrowseCatalogView(
                            folder: nil,
                            onScoreTapped: onScoreTapped,
                            onProgramTapped: onProgramTapped,
                            onFolderTapped: onFolderTapped,
                            isSelecting: $isSelecting,
                            selectedScoreIds: $selectedScoreIds
                        )
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Library"))
        .searchable(text: $searchText, prompt: String(localized: "Search Scores"))
        .toolbar {
            if selectedTab != .browse || isSearchActive {
                recentToolbar
            }
        }
        .alert(String(localized: "Delete Score"), isPresented: .init(
            get: { deletingScore != nil },
            set: { if !$0 { deletingScore = nil } }
        )) {
            Button(String(localized: "Cancel"), role: .cancel) { deletingScore = nil }
            Button(String(localized: "Delete"), role: .destructive) { confirmDeleteScore() }
        } message: {
            if let score = deletingScore {
                Text("Are you sure you want to delete \"\(score.title)\"? This cannot be undone.")
            }
        }
        .sheet(item: $editingScore) { score in
            ScoreMetadataEditorView(score: score, existingTags: allTags)
        }
        .alert(String(localized: "Delete Selected"), isPresented: $showDeleteSelectedAlert) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete"), role: .destructive) { deleteSelectedScores() }
        } message: {
            Text("Delete \(selectedScoreIds.count) scores? This cannot be undone.")
        }
    }

    @ToolbarContentBuilder
    private var recentToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button(allSelected ? String(localized: "Deselect All") : String(localized: "Select All")) {
                    withAnimation {
                        if allSelected {
                            selectedScoreIds.removeAll()
                        } else {
                            selectedScoreIds = Set(visibleScores.map(\.id))
                        }
                    }
                }
            }
        }
        if isSelecting {
            ToolbarItemGroup(placement: .primaryAction) {
                if !folders.isEmpty {
                    Menu {
                        ForEach(folders) { folder in
                            Button(folder.name) {
                                moveSelectedScores(to: folder)
                            }
                        }
                        Divider()
                        Button(String(localized: "Remove from Folder")) {
                            moveSelectedScores(to: nil)
                        }
                    } label: {
                        Label(String(localized: "Move"), systemImage: "folder")
                    }
                    .disabled(selectedScoreIds.isEmpty)
                }

                if !programs.isEmpty {
                    Menu {
                        ForEach(programs) { program in
                            Button(program.name) {
                                addSelectedScores(to: program)
                            }
                        }
                    } label: {
                        Label(String(localized: "Add to Program"), systemImage: "music.note.list")
                    }
                    .disabled(selectedScoreIds.isEmpty)
                }

                Button(role: .destructive) {
                    showDeleteSelectedAlert = true
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
                .disabled(selectedScoreIds.isEmpty)

                Button {
                    withAnimation {
                        isSelecting = false
                        selectedScoreIds.removeAll()
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                }
            }
        } else {
            if !allScores.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { isSelecting = true }
                    } label: {
                        Text(String(localized: "Select"))
                    }
                }

                if #available(iOS 26, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: onImport) {
                        Label(String(localized: "Import Score"), systemImage: "doc.badge.plus")
                    }
                } label: {
                    Label(String(localized: "Add"), systemImage: "plus")
                }
            }
        }
    }

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

    private var recentTab: some View {
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
                .dragToSelect(selectedIds: $selectedScoreIds, isSelecting: isSelecting, orderedIds: allScores.map(\.id))
            }
        }
    }

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

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label(String(localized: "No Scores"), systemImage: "music.note")
        } description: {
            Text(String(localized: "Import PDF sheet music to get started"))
        } actions: {
            Button(action: onImport) {
                Text(String(localized: "Import Score"))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var visibleScores: [Score] {
        if isSearchActive { return searchResults }
        return allScores
    }

    private var allSelected: Bool {
        let visible = visibleScores
        return !visible.isEmpty && selectedScoreIds.count == visible.count
    }

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
