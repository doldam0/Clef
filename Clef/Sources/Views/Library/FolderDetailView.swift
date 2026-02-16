import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @Query(sort: \Program.updatedAt, order: .reverse) private var allPrograms: [Program]
    let folder: Folder
    var onScoreTapped: (Score) -> Void
    var onProgramTapped: (Program) -> Void
    var onFolderTapped: (Folder) -> Void

    @State private var editingScore: Score?
    @State private var deletingScore: Score?
    @State private var isSelecting = false
    @State private var selectedScoreIds: Set<UUID> = []
    @State private var showDeleteSelectedAlert = false
    @State private var isImporting = false
    @State private var isCreatingSubfolder = false
    @State private var newSubfolderName = ""
    @State private var isCreatingProgram = false
    @State private var newProgramName = ""

    private var subFolders: [Folder] {
        folder.children.sorted { $0.name < $1.name }
    }

    private var folderPrograms: [Program] {
        folder.programs.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var folderScores: [Score] {
        folder.scores.sorted { $0.updatedAt > $1.updatedAt }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionView(title: String(localized: "Folders")) {
                    ForEach(subFolders) { child in
                        folderCard(for: child)
                    }
                    newSubfolderCard
                }

                sectionView(title: String(localized: "Programs")) {
                    ForEach(folderPrograms) { program in
                        programCard(for: program)
                    }
                    newProgramCard
                }

                if !folderScores.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Scores"))
                            .font(.title3.bold())
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(folderScores) { score in
                                scoreCard(for: score)
                            }
                        }
                        .padding(.horizontal, 16)
                        .dragToSelect(selectedIds: $selectedScoreIds, isSelecting: isSelecting, orderedIds: folderScores.map(\.id))
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button(allSelected ? String(localized: "Deselect All") : String(localized: "Select All")) {
                        withAnimation {
                            if allSelected {
                                selectedScoreIds.removeAll()
                            } else {
                                selectedScoreIds = Set(folderScores.map(\.id))
                            }
                        }
                    }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !allFolders.isEmpty {
                        Menu {
                            ForEach(allFolders) { targetFolder in
                                if targetFolder.id != folder.id {
                                    Button(targetFolder.name) {
                                        moveSelectedScores(to: targetFolder)
                                    }
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

                    if !allPrograms.isEmpty {
                        Menu {
                            ForEach(allPrograms) { program in
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { isImporting = true }) {
                            Label(String(localized: "Import Score"), systemImage: "doc.badge.plus")
                        }
                        Button(action: { isCreatingSubfolder = true }) {
                            Label(String(localized: "New Folder"), systemImage: "folder.badge.plus")
                        }
                        Button(action: { isCreatingProgram = true }) {
                            Label(String(localized: "New Program"), systemImage: "music.note.list")
                        }
                    } label: {
                        Label(String(localized: "Add"), systemImage: "plus")
                    }
                }

                if #available(iOS 26, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { isSelecting = true }
                    } label: {
                        Label(String(localized: "Select"), systemImage: "checkmark.circle")
                    }
                }
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
            ScoreMetadataEditorView(score: score, existingTags: [])
        }
        .alert(String(localized: "New Folder"), isPresented: $isCreatingSubfolder) {
            TextField(String(localized: "Folder Name"), text: $newSubfolderName)
            Button(String(localized: "Cancel"), role: .cancel) { newSubfolderName = "" }
            Button(String(localized: "Create")) { createSubfolder() }
        }
        .alert(String(localized: "New Program"), isPresented: $isCreatingProgram) {
            TextField(String(localized: "Program Name"), text: $newProgramName)
            Button(String(localized: "Cancel"), role: .cancel) { newProgramName = "" }
            Button(String(localized: "Create")) { createProgram() }
        }
        .scoreImporter(isPresented: $isImporting, folder: folder)
    }

    // MARK: - Section Layout

    private func sectionView<Content: View>(title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.title3.bold())
                    .padding(.horizontal, 16)
            }

            LazyVGrid(columns: gridColumns, spacing: 16) {
                content()
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Cards

    private func folderCard(for child: Folder) -> some View {
        Button {
            onFolderTapped(child)
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
                            Text("\(child.totalScoreCount)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(child.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
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
    }

    private var newSubfolderCard: some View {
        Button { isCreatingSubfolder = true } label: {
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
        .contextMenu(isSelecting ? nil : ContextMenu {
            Button {
                editingScore = score
            } label: {
                Label(String(localized: "Edit Info"), systemImage: "info.circle")
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

            if !allFolders.isEmpty {
                Menu {
                    ForEach(allFolders) { targetFolder in
                        Button(targetFolder.name) {
                            score.folder = targetFolder
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

            if !allPrograms.isEmpty {
                Menu {
                    ForEach(allPrograms) { program in
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

    // MARK: - Helpers

    private var allSelected: Bool {
        !folderScores.isEmpty && selectedScoreIds.count == folderScores.count
    }

    private func toggleSelection(_ score: Score) {
        if selectedScoreIds.contains(score.id) {
            selectedScoreIds.remove(score.id)
        } else {
            selectedScoreIds.insert(score.id)
        }
    }

    private func moveSelectedScores(to target: Folder?) {
        for score in folderScores where selectedScoreIds.contains(score.id) {
            score.folder = target
            score.updatedAt = .now
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }

    private func deleteSelectedScores() {
        for score in folderScores where selectedScoreIds.contains(score.id) {
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

    private func createSubfolder() {
        let trimmed = newSubfolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newSubfolderName = ""
            return
        }
        let subfolder = Folder(name: trimmed)
        subfolder.parent = folder
        modelContext.insert(subfolder)
        try? modelContext.save()
        newSubfolderName = ""
    }

    private func createProgram() {
        let trimmed = newProgramName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newProgramName = ""
            return
        }
        let program = Program(name: trimmed)
        program.folder = folder
        modelContext.insert(program)
        try? modelContext.save()
        newProgramName = ""
    }

    private func addSelectedScores(to program: Program) {
        for score in folderScores where selectedScoreIds.contains(score.id) {
            program.appendScore(score)
        }
        try? modelContext.save()
        selectedScoreIds.removeAll()
    }
}
