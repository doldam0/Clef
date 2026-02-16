import SwiftUI
import SwiftData

struct ScoreLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    let scores: [Score]
    let folders: [Folder]
    let selectedScore: Score?
    let allTags: [String]
    @Binding var selectedTags: Set<String>
    var onImport: () -> Void
    var onDelete: (IndexSet) -> Void
    var onScoreTapped: (Score) -> Void

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renamingFolder: Folder?
    @State private var renameText = ""
    @State private var renamingScore: Score?
    @State private var scoreRenameText = ""
    @State private var editingScore: Score?

    var body: some View {
        VStack(spacing: 0) {
            if !allTags.isEmpty {
                tagFilterBar
                    .padding(.vertical, 8)
                Divider()
            }

            List {
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders) { folder in
                        FolderRow(
                            folder: folder,
                            selectedScore: selectedScore,
                            selectedTags: selectedTags,
                            onScoreTapped: onScoreTapped,
                            onScoreRename: { beginScoreRename($0) },
                            onScoreEdit: { editingScore = $0 },
                            onRename: { beginRename(folder) },
                            onDelete: { deleteFolder(folder) }
                        )
                    }
                }
            }

            Section(folders.isEmpty ? "Scores" : "Uncategorized") {
                ForEach(unfolderedScores) { score in
                    Button { onScoreTapped(score) } label: {
                        ScoreRow(score: score, folders: folders, modelContext: modelContext, onRename: { beginScoreRename(score) }, onEdit: { editingScore = score })
                    }
                    .listRowBackground(
                        score == selectedScore ? Color.accentColor.opacity(0.15) : nil
                    )
                }
                .onDelete { offsets in
                    let scoresToDelete = offsets.map { unfolderedScores[$0] }
                    for score in scoresToDelete {
                        if let index = scores.firstIndex(of: score) {
                            onDelete(IndexSet(integer: index))
                        }
                    }
                }
            }
        }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: onImport) {
                        Label("Import Score", systemImage: "doc.badge.plus")
                    }
                    Button(action: { isCreatingFolder = true }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { createFolder() }
        }
        .alert("Rename Folder", isPresented: .init(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Rename") { commitRename() }
        }
        .alert("Rename Score", isPresented: .init(
            get: { renamingScore != nil },
            set: { if !$0 { renamingScore = nil } }
        )) {
            TextField("Score Name", text: $scoreRenameText)
            Button("Cancel", role: .cancel) { renamingScore = nil }
            Button("Rename") { commitScoreRename() }
        }
        .sheet(item: $editingScore) { score in
            ScoreMetadataEditorView(score: score, existingTags: allTags)
        }
    }

    private var filteredScores: [Score] {
        guard !selectedTags.isEmpty else { return scores }
        return scores.filter { score in
            selectedTags.isSubset(of: Set(score.tags))
        }
    }

    private var unfolderedScores: [Score] {
        filteredScores.filter { $0.folder == nil }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    let isSelected = selectedTags.contains(tag)
                    Button {
                        if isSelected {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        Text(tag)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color(.systemGray5), in: Capsule())
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func createFolder() {
        guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else {
            newFolderName = ""
            return
        }
        let folder = Folder(name: newFolderName.trimmingCharacters(in: .whitespaces))
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
    }

    private func beginRename(_ folder: Folder) {
        renameText = folder.name
        renamingFolder = folder
    }

    private func commitRename() {
        guard let folder = renamingFolder,
              !renameText.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            renamingFolder = nil
            return
        }
        folder.name = renameText.trimmingCharacters(in: .whitespaces)
        folder.updatedAt = .now
        try? modelContext.save()
        renamingFolder = nil
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

    private func deleteFolder(_ folder: Folder) {
        for score in folder.scores {
            score.folder = nil
        }
        modelContext.delete(folder)
        try? modelContext.save()
    }
}

private struct FolderRow: View {
    let folder: Folder
    let selectedScore: Score?
    let selectedTags: Set<String>
    var onScoreTapped: (Score) -> Void
    var onScoreRename: (Score) -> Void
    var onScoreEdit: (Score) -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false

    private var filteredScores: [Score] {
        let sorted = folder.scores.sorted(by: { $0.updatedAt > $1.updatedAt })
        guard !selectedTags.isEmpty else { return sorted }
        return sorted.filter { selectedTags.isSubset(of: Set($0.tags)) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(filteredScores) { score in
                Button { onScoreTapped(score) } label: {
                    ScoreRow(score: score, folders: [], modelContext: nil, onRename: { onScoreRename(score) }, onEdit: { onScoreEdit(score) })
                }
                .listRowBackground(
                    score == selectedScore ? Color.accentColor.opacity(0.15) : nil
                )
            }
        } label: {
            Label(folder.name, systemImage: "folder")
                .badge(filteredScores.count)
                .contextMenu {
                    Button(action: onRename) {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }
}

private struct ScoreRow: View {
    let score: Score
    let folders: [Folder]
    let modelContext: ModelContext?
    var onRename: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(score.title)
                .font(.headline)
                .lineLimit(1)

            if let composer = score.composer {
                Text(composer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !score.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(score.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.12), in: Capsule())
                    }
                    if score.tags.count > 3 {
                        Text("+\(score.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit Info", systemImage: "info.circle")
                }
            }

            if let onRename {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }
            }

            if !folders.isEmpty, let modelContext {
                Menu("Move to Folder") {
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            score.folder = folder
                            score.updatedAt = .now
                            try? modelContext.save()
                        }
                    }
                    if score.folder != nil {
                        Divider()
                        Button("Move to Uncategorized") {
                            score.folder = nil
                            score.updatedAt = .now
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
    }
}
