import SwiftUI
import SwiftData

struct ScoreLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    let scores: [Score]
    let folders: [Folder]
    let selectedScore: Score?
    var onImport: () -> Void
    var onDelete: (IndexSet) -> Void
    var onScoreTapped: (Score) -> Void

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renamingFolder: Folder?
    @State private var renameText = ""

    var body: some View {
        List {
            if !folders.isEmpty {
                Section("폴더") {
                    ForEach(folders) { folder in
                        FolderRow(
                            folder: folder,
                            selectedScore: selectedScore,
                            onScoreTapped: onScoreTapped,
                            onRename: { beginRename(folder) },
                            onDelete: { deleteFolder(folder) }
                        )
                    }
                }
            }

            Section(folders.isEmpty ? "악보" : "미분류") {
                ForEach(unfolderedScores) { score in
                    Button { onScoreTapped(score) } label: {
                        ScoreRow(score: score, folders: folders, modelContext: modelContext)
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
    }

    private var unfolderedScores: [Score] {
        scores.filter { $0.folder == nil }
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
    var onScoreTapped: (Score) -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(folder.scores.sorted(by: { $0.updatedAt > $1.updatedAt })) { score in
                Button { onScoreTapped(score) } label: {
                    ScoreRow(score: score, folders: [], modelContext: nil)
                }
                .listRowBackground(
                    score == selectedScore ? Color.accentColor.opacity(0.15) : nil
                )
            }
        } label: {
            Label(folder.name, systemImage: "folder")
                .badge(folder.scores.count)
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
        }
        .padding(.vertical, 4)
        .contextMenu {
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
