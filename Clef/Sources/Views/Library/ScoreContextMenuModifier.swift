import SwiftUI
import SwiftData

struct ScoreContextMenuModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var allFolders: [Folder]
    @Query(sort: \Program.updatedAt, order: .reverse) private var allPrograms: [Program]

    let score: Score
    let isSelecting: Bool
    var onEdit: ((Score) -> Void)?
    var onDelete: ((Score) -> Void)?

    func body(content: Content) -> some View {
        content
            .contextMenu(isSelecting ? nil : ContextMenu {
                Button {
                    onEdit?(score)
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
                        ForEach(allFolders) { folder in
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
                    onDelete?(score)
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            })
    }
}

extension View {
    func scoreContextMenu(
        score: Score,
        isSelecting: Bool,
        onEdit: ((Score) -> Void)? = nil,
        onDelete: ((Score) -> Void)? = nil
    ) -> some View {
        modifier(ScoreContextMenuModifier(
            score: score,
            isSelecting: isSelecting,
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }
}
