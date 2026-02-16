import SwiftUI
import SwiftData

private enum LibraryTab: String, CaseIterable, Identifiable {
    case recent
    case browse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: String(localized: "Recent")
        case .browse: String(localized: "Browse")
        }
    }

    var icon: String {
        switch self {
        case .recent: "clock"
        case .browse: "folder"
        }
    }
}

struct ScoreLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.updatedAt, order: .reverse) private var allScores: [Score]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    var onImport: () -> Void
    var onScoreTapped: (Score) -> Void
    var onProgramTapped: (Program) -> Void

    @State private var selectedTab: LibraryTab = .recent
    @State private var searchText = ""
    @State private var selectedFolder: Folder?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isCreatingProgram = false
    @State private var newProgramName = ""
    @State private var renamingScore: Score?
    @State private var scoreRenameText = ""
    @State private var renamingFolder: Folder?
    @State private var folderRenameText = ""
    @State private var renamingProgram: Program?
    @State private var programRenameText = ""
    @State private var editingScore: Score?
    @State private var deletingScore: Score?
    @State private var isSelecting = false
    @State private var selectedScoreIds: Set<UUID> = []
    @State private var showDeleteSelectedAlert = false
    @State private var moveToFolderScores: [Score]?

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

    private var unfolderedScores: [Score] {
        allScores.filter { $0.folder == nil }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if isSearchActive {
                searchResultsGrid
            } else if selectedTab == .recent {
                recentTab
            } else {
                browseTab
            }

            if !isSearchActive {
                tabBar
            }
        }
        .navigationTitle(String(localized: "Library"))
        .searchable(text: $searchText, prompt: String(localized: "Search Scores"))
        .toolbar {
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
            ToolbarItemGroup(placement: .primaryAction) {
                if isSelecting {
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
                } else {
                    Menu {
                        Button(action: onImport) {
                            Label(String(localized: "Import Score"), systemImage: "doc.badge.plus")
                        }
                        Button(action: { isCreatingFolder = true }) {
                            Label(String(localized: "New Folder"), systemImage: "folder.badge.plus")
                        }
                        Button(action: { isCreatingProgram = true }) {
                            Label(String(localized: "New Program"), systemImage: "music.note.list")
                        }
                    } label: {
                        Label(String(localized: "Add"), systemImage: "plus")
                    }

                    if !allScores.isEmpty {
                        Button {
                            withAnimation { isSelecting = true }
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                        }
                    }
                }
            }
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
        .alert(String(localized: "Rename Program"), isPresented: .init(
            get: { renamingProgram != nil },
            set: { if !$0 { renamingProgram = nil } }
        )) {
            TextField(String(localized: "Program Name"), text: $programRenameText)
            Button(String(localized: "Cancel"), role: .cancel) { renamingProgram = nil }
            Button(String(localized: "Rename")) { commitProgramRename() }
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

    private var tabBar: some View {
        HStack(spacing: 0) {
            Spacer()
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                        selectedFolder = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.subheadline)
                        Text(tab.label)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? AnyShapeStyle(.tint.opacity(0.15))
                            : AnyShapeStyle(.clear),
                        in: Capsule()
                    )
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)

                if tab != LibraryTab.allCases.last {
                    Spacer().frame(width: 8)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .background(.bar)
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
            }
        }
    }

    @ViewBuilder
    private var browseTab: some View {
        if let folder = selectedFolder {
            folderDetailView(for: folder)
        } else {
            browseCatalogView
        }
    }

    private var rootFolders: [Folder] {
        folders.filter { $0.parent == nil }
    }

    private var rootPrograms: [Program] {
        programs.filter { $0.folder == nil }
    }

    private var browseCatalogView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !rootFolders.isEmpty || true {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Folders"))
                            .font(.title3.bold())
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(rootFolders) { folder in
                                folderCard(for: folder)
                            }
                            newFolderCard
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if !rootPrograms.isEmpty || true {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Programs"))
                            .font(.title3.bold())
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(rootPrograms) { program in
                                programCard(for: program)
                            }
                            newProgramCard
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if !unfolderedScores.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Uncategorized"))
                            .font(.title3.bold())
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(unfolderedScores) { score in
                                scoreCard(for: score)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if rootFolders.isEmpty && rootPrograms.isEmpty && unfolderedScores.isEmpty {
                    emptyLibraryView
                        .padding(.top, 40)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private func folderDetailView(for folder: Folder) -> some View {
        let subFolders = folder.children.sorted { $0.name < $1.name }
        let folderPrograms = folder.programs.sorted { $0.updatedAt > $1.updatedAt }
        let folderScores = folder.scores.sorted { $0.updatedAt > $1.updatedAt }
        let isEmpty = subFolders.isEmpty && folderPrograms.isEmpty && folderScores.isEmpty

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    withAnimation { selectedFolder = folder.parent }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(folder.parent?.name ?? String(localized: "Browse"))
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 16)

                if isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "Empty Folder"), systemImage: "folder")
                    } description: {
                        Text(String(localized: "Import scores and move them to this folder"))
                    }
                    .padding(.top, 40)
                } else {
                    if !subFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "Folders"))
                                .font(.title3.bold())
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(subFolders) { child in
                                    folderCard(for: child)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if !folderPrograms.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "Programs"))
                                .font(.title3.bold())
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(folderPrograms) { program in
                                    programCard(for: program)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if !folderScores.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            if !subFolders.isEmpty || !folderPrograms.isEmpty {
                                Text(String(localized: "Scores"))
                                    .font(.title3.bold())
                                    .padding(.horizontal, 16)
                            }

                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(folderScores) { score in
                                    scoreCard(for: score)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(folder.name)
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
        .disabled(false)
        .contextMenu(isSelecting ? nil : ContextMenu {
            Button {
                editingScore = score
            } label: {
                Label(String(localized: "Edit Info"), systemImage: "info.circle")
            }

            Button {
                beginScoreRename(score)
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }

            Button {
                score.isFavorite.toggle()
                score.updatedAt = .now
                try? modelContext.save()
            } label: {
                Label(
                    score.isFavorite
                        ? String(localized: "Unfavorite")
                        : String(localized: "Favorite"),
                    systemImage: score.isFavorite ? "heart.slash" : "heart"
                )
            }

            if !folders.isEmpty {
                Menu {
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            score.folder = folder
                            score.updatedAt = .now
                            try? modelContext.save()
                        }
                    }
                    if score.folder != nil {
                        Divider()
                        Button(String(localized: "Remove from Folder")) {
                            score.folder = nil
                            score.updatedAt = .now
                            try? modelContext.save()
                        }
                    }
                } label: {
                    Label(String(localized: "Move to Folder"), systemImage: "folder")
                }
            }

            if !programs.isEmpty {
                Menu {
                    ForEach(programs) { program in
                        Button(program.name) {
                            program.appendScore(score)
                            try? modelContext.save()
                        }
                    }
                } label: {
                    Label(String(localized: "Add to Program"), systemImage: "music.note.list")
                }
            }

            Divider()

            Button(role: .destructive) {
                deletingScore = score
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        })
    }

    private func folderCard(for folder: Folder) -> some View {
        Button {
            withAnimation { selectedFolder = folder }
        } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.opacity(0.1))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.tint)
                            Text("\(folder.totalScoreCount)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(folder.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                beginFolderRename(folder)
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    private func programCard(for program: Program) -> some View {
        Button {
            onProgramTapped(program)
        } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.orange.opacity(0.1))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note.list")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)
                            Text("\(program.items.count)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(program.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
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

    private var newFolderCard: some View {
        Button { isCreatingFolder = true } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(.tertiary)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "New Folder"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(" ")
                    .font(.headline)
            }
        }
        .buttonStyle(.plain)
    }

    private var newProgramCard: some View {
        Button { isCreatingProgram = true } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(.tertiary)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "New Program"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(" ")
                    .font(.headline)
            }
        }
        .buttonStyle(.plain)
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

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newFolderName = ""
            return
        }
        let folder = Folder(name: trimmed, parent: selectedFolder)
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
    }

    private func createProgram() {
        let trimmed = newProgramName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newProgramName = ""
            return
        }
        let program = Program(name: trimmed, folder: selectedFolder)
        modelContext.insert(program)
        try? modelContext.save()
        newProgramName = ""
    }

    private func beginScoreRename(_ score: Score) {
        scoreRenameText = score.title
        renamingScore = score
    }

    private func commitScoreRename() {
        guard let score = renamingScore,
              !scoreRenameText.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            renamingScore = nil
            return
        }
        score.title = scoreRenameText.trimmingCharacters(in: .whitespaces)
        score.updatedAt = .now
        try? modelContext.save()
        renamingScore = nil
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
        if selectedFolder?.id == folder.id {
            selectedFolder = nil
        }
    }

    private func deleteProgram(_ program: Program) {
        modelContext.delete(program)
        try? modelContext.save()
    }

    private func confirmDeleteScore() {
        guard let score = deletingScore else { return }
        modelContext.delete(score)
        try? modelContext.save()
        deletingScore = nil
    }

    private var visibleScores: [Score] {
        if isSearchActive { return searchResults }
        if selectedTab == .browse, let folder = selectedFolder {
            return folder.scores.sorted { $0.updatedAt > $1.updatedAt }
        }
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
}
