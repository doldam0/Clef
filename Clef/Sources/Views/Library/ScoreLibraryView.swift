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
                Section("폴더") {
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

            Section(folders.isEmpty ? "악보" : "미분류") {
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
        .navigationTitle("라이브러리")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: onImport) {
                        Label("악보 가져오기", systemImage: "doc.badge.plus")
                    }
                    Button(action: { isCreatingFolder = true }) {
                        Label("새 폴더", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("추가", systemImage: "plus")
                }
            }
        }
        .alert("새 폴더", isPresented: $isCreatingFolder) {
            TextField("폴더 이름", text: $newFolderName)
            Button("취소", role: .cancel) { newFolderName = "" }
            Button("생성") { createFolder() }
        }
        .alert("폴더 이름 변경", isPresented: .init(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("폴더 이름", text: $renameText)
            Button("취소", role: .cancel) { renamingFolder = nil }
            Button("변경") { commitRename() }
        }
        .alert("악보 이름 변경", isPresented: .init(
            get: { renamingScore != nil },
            set: { if !$0 { renamingScore = nil } }
        )) {
            TextField("악보 이름", text: $scoreRenameText)
            Button("취소", role: .cancel) { renamingScore = nil }
            Button("변경") { commitScoreRename() }
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
                        Label("이름 변경", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("삭제", systemImage: "trash")
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
                    Label("정보 편집", systemImage: "info.circle")
                }
            }

            if let onRename {
                Button(action: onRename) {
                    Label("이름 변경", systemImage: "pencil")
                }
            }

            if !folders.isEmpty, let modelContext {
                Menu("폴더로 이동") {
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            score.folder = folder
                            score.updatedAt = .now
                            try? modelContext.save()
                        }
                    }
                    if score.folder != nil {
                        Divider()
                        Button("미분류로 이동") {
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
