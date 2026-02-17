import SwiftUI
import SwiftData

struct BrowseCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @Query(sort: \Program.updatedAt, order: .reverse) private var allPrograms: [Program]
    @Query(sort: \Score.updatedAt, order: .reverse) private var allScores: [Score]

    let folder: Folder?
    var onScoreTapped: (Score) -> Void
    var onProgramTapped: (Program) -> Void
    var onFolderTapped: (Folder) -> Void

    @Binding var isSelecting: Bool
    @Binding var selectedScoreIds: Set<UUID>
    @Binding var isImporting: Bool
    @Binding var isCreatingFolder: Bool
    @Binding var isCreatingProgram: Bool
    var showsToolbar: Bool = true

    @State private var searchText = ""
    @State private var editingScore: Score?
    @State private var deletingScore: Score?
    @State private var showDeleteSelectedAlert = false
    @State private var newFolderName = ""
    @State private var newProgramName = ""
    @State private var renamingFolder: Folder?
    @State private var folderRenameText = ""
    @State private var renamingProgram: Program?
    @State private var programRenameText = ""

    private var subFolders: [Folder] {
        if let folder {
            return folder.children.sorted { $0.name < $1.name }
        }
        return allFolders.filter { $0.parent == nil }
    }

    private var visiblePrograms: [Program] {
        if let folder {
            return folder.programs.sorted { $0.updatedAt > $1.updatedAt }
        }
        return allPrograms.filter { $0.folder == nil }
    }

    private var visibleScores: [Score] {
        if let folder {
            return folder.scores.sorted { $0.updatedAt > $1.updatedAt }
        }
        return allScores.filter { $0.folder == nil }
    }

    private var isSearchActive: Bool {
        showsToolbar && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        isSearchActive ? searchResults : visibleScores
    }

    private var allTags: [String] {
        Array(Set(allScores.flatMap(\.tags))).sorted()
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        mainContent
            .toolbar {
                if showsToolbar {
                    LibraryToolbar(
                        isSelecting: $isSelecting,
                        selectedScoreIds: $selectedScoreIds,
                        showDeleteSelectedAlert: $showDeleteSelectedAlert,
                        selectableScores: selectableScores,
                        folders: allFolders,
                        programs: allPrograms,
                        currentFolder: folder,
                        onImport: { isImporting = true },
                        onCreateFolder: { isCreatingFolder = true },
                        onCreateProgram: { isCreatingProgram = true },
                        onMoveToFolder: { moveSelectedScores(to: $0) },
                        onAddToProgram: { addSelectedScores(to: $0) }
                    )
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
            .alert(String(localized: "Delete Selected"), isPresented: $showDeleteSelectedAlert) {
                Button(String(localized: "Cancel"), role: .cancel) {}
                Button(String(localized: "Delete"), role: .destructive) { deleteSelectedScores() }
            } message: {
                Text("Delete \(selectedScoreIds.count) scores? This cannot be undone.")
            }
            .sheet(item: $editingScore) { score in
                ScoreMetadataEditorView(score: score, existingTags: allTags)
            }
            .alert(String(localized: "New Folder"), isPresented: $isCreatingFolder) {
                TextField(String(localized: "Folder Name"), text: $newFolderName)
                Button(String(localized: "Cancel"), role: .cancel) { newFolderName = "" }
                Button(String(localized: "Create")) { createFolder() }
            }
            .alert(String(localized: "New Program"), isPresented: $isCreatingProgram) {
                TextField(String(localized: "Program Name"), text: $newProgramName)
                Button(String(localized: "Cancel"), role: .cancel) { newProgramName = "" }
                Button(String(localized: "Create")) { createProgram() }
            }
            .alert(String(localized: "Rename Folder"), isPresented: .init(
                get: { renamingFolder != nil },
                set: { if !$0 { renamingFolder = nil } }
            )) {
                TextField(String(localized: "Folder Name"), text: $folderRenameText)
                Button(String(localized: "Cancel"), role: .cancel) { renamingFolder = nil }
                Button(String(localized: "Rename")) { commitFolderRename() }
            }
            .alert(String(localized: "Rename Program"), isPresented: .init(
                get: { renamingProgram != nil },
                set: { if !$0 { renamingProgram = nil } }
            )) {
                TextField(String(localized: "Program Name"), text: $programRenameText)
                Button(String(localized: "Cancel"), role: .cancel) { renamingProgram = nil }
                Button(String(localized: "Rename")) { commitProgramRename() }
            }
            .scoreImporter(isPresented: $isImporting, folder: folder)
    }

    // MARK: - Content

    @ViewBuilder
    private var mainContent: some View {
        if showsToolbar {
            contentView
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: String(localized: "Search Scores")
                )
        } else {
            contentView
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if isSearchActive {
            searchResultsGrid
        } else {
            browseGrid
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
                .dragToSelect(
                    selectedIds: $selectedScoreIds,
                    isSelecting: isSelecting,
                    orderedIds: searchResults.map(\.id)
                )
            }
        }
    }

    private var browseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionView(title: String(localized: "Folders")) {
                    ForEach(subFolders) { child in
                        FolderCardView(folder: child) {
                            onFolderTapped(child)
                        }
                        .contextMenu {
                            Button {
                                beginFolderRename(child)
                            } label: {
                                Label(String(localized: "Rename"), systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteFolder(child)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                    NewItemCardView(title: String(localized: "New Folder")) {
                        isCreatingFolder = true
                    }
                }

                sectionView(title: String(localized: "Programs")) {
                    ForEach(visiblePrograms) { program in
                        ProgramCardView(program: program) {
                            onProgramTapped(program)
                        }
                        .contextMenu {
                            Button {
                                beginProgramRename(program)
                            } label: {
                                Label(String(localized: "Rename"), systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteProgram(program)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                    NewItemCardView(title: String(localized: "New Program")) {
                        isCreatingProgram = true
                    }
                }

                if !visibleScores.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Scores"))
                            .font(.title3.bold())
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(visibleScores) { score in
                                scoreCard(for: score)
                            }
                        }
                        .padding(.horizontal, 16)
                        .dragToSelect(
                            selectedIds: $selectedScoreIds,
                            isSelecting: isSelecting,
                            orderedIds: visibleScores.map(\.id)
                        )
                    }
                }

                if subFolders.isEmpty && visiblePrograms.isEmpty && visibleScores.isEmpty {
                    emptyView
                        .padding(.top, 40)
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Components

    private func sectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 16)

            LazyVGrid(columns: gridColumns, spacing: 16) {
                content()
            }
            .padding(.horizontal, 16)
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

    private var emptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "No Scores"), systemImage: "music.note")
        } description: {
            Text(String(localized: "Import PDF sheet music to get started"))
        } actions: {
            Button(action: { isImporting = true }) {
                Text(String(localized: "Import Score"))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ score: Score) {
        if selectedScoreIds.contains(score.id) {
            selectedScoreIds.remove(score.id)
        } else {
            selectedScoreIds.insert(score.id)
        }
    }

    private func moveSelectedScores(to target: Folder?) {
        for score in selectableScores where selectedScoreIds.contains(score.id) {
            score.folder = target
            score.updatedAt = .now
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }

    private func addSelectedScores(to program: Program) {
        for score in selectableScores where selectedScoreIds.contains(score.id) {
            program.appendScore(score)
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }

    private func deleteSelectedScores() {
        for score in selectableScores where selectedScoreIds.contains(score.id) {
            modelContext.delete(score)
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

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newFolderName = ""
            return
        }
        let newFolder = Folder(name: trimmed)
        if let folder {
            newFolder.parent = folder
        }
        modelContext.insert(newFolder)
        try? modelContext.save()
        newFolderName = ""
    }

    private func createProgram() {
        let trimmed = newProgramName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newProgramName = ""
            return
        }
        let program = Program(name: trimmed)
        if let folder {
            program.folder = folder
        }
        modelContext.insert(program)
        try? modelContext.save()
        newProgramName = ""
    }

    private func beginFolderRename(_ folder: Folder) {
        folderRenameText = folder.name
        renamingFolder = folder
    }

    private func commitFolderRename() {
        guard let folder = renamingFolder,
              !folderRenameText.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            renamingFolder = nil
            return
        }
        folder.name = folderRenameText.trimmingCharacters(in: .whitespaces)
        folder.updatedAt = .now
        try? modelContext.save()
        renamingFolder = nil
    }

    private func beginProgramRename(_ program: Program) {
        programRenameText = program.name
        renamingProgram = program
    }

    private func commitProgramRename() {
        guard let program = renamingProgram,
              !programRenameText.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            renamingProgram = nil
            return
        }
        program.name = programRenameText.trimmingCharacters(in: .whitespaces)
        program.updatedAt = .now
        try? modelContext.save()
        renamingProgram = nil
    }

    private func deleteFolder(_ folder: Folder) {
        for score in folder.scores {
            score.folder = nil
        }
        modelContext.delete(folder)
        try? modelContext.save()
    }

    private func deleteProgram(_ program: Program) {
        modelContext.delete(program)
        try? modelContext.save()
    }
}
