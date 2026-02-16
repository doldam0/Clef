import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    let folder: Folder
    var onScoreTapped: (Score) -> Void
    var onProgramTapped: (Program) -> Void
    var onFolderTapped: (Folder) -> Void

    @State private var editingScore: Score?
    @State private var deletingScore: Score?
    @State private var isSelecting = false
    @State private var selectedScoreIds: Set<UUID> = []
    @State private var showDeleteSelectedAlert = false

    private var subFolders: [Folder] {
        folder.children.sorted { $0.name < $1.name }
    }

    private var folderPrograms: [Program] {
        folder.programs.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var folderScores: [Score] {
        folder.scores.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var isEmpty: Bool {
        subFolders.isEmpty && folderPrograms.isEmpty && folderScores.isEmpty
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            if isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Empty Folder"), systemImage: "folder")
                } description: {
                    Text(String(localized: "Import scores and move them to this folder"))
                }
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if !subFolders.isEmpty {
                        sectionView(title: String(localized: "Folders")) {
                            ForEach(subFolders) { child in
                                folderCard(for: child)
                            }
                        }
                    }

                    if !folderPrograms.isEmpty {
                        sectionView(title: String(localized: "Programs")) {
                            ForEach(folderPrograms) { program in
                                programCard(for: program)
                            }
                        }
                    }

                    if !folderScores.isEmpty {
                        sectionView(title: !subFolders.isEmpty || !folderPrograms.isEmpty ? String(localized: "Scores") : nil) {
                            ForEach(folderScores) { score in
                                scoreCard(for: score)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }
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
            ToolbarItemGroup(placement: .primaryAction) {
                if isSelecting {
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
                    if !folderScores.isEmpty {
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
}
