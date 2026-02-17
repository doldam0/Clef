import SwiftUI

struct LibraryToolbar: ToolbarContent {
    @Binding var isSelecting: Bool
    @Binding var selectedScoreIds: Set<UUID>
    @Binding var showDeleteSelectedAlert: Bool
    let selectableScores: [Score]
    let folders: [Folder]
    let programs: [Program]
    var currentFolder: Folder? = nil
    let onImport: () -> Void
    let onCreateFolder: () -> Void
    let onCreateProgram: () -> Void
    let onMoveToFolder: (Folder?) -> Void
    let onAddToProgram: (Program) -> Void

    private var allSelected: Bool {
        !selectableScores.isEmpty && selectedScoreIds.count == selectableScores.count
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button(allSelected ? "Deselect All" : "Select All") {
                    withAnimation {
                        if allSelected {
                            selectedScoreIds.removeAll()
                        } else {
                            selectedScoreIds = Set(selectableScores.map(\.id))
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
                            if folder.id != currentFolder?.id {
                                Button(folder.name) {
                                    onMoveToFolder(folder)
                                }
                            }
                        }
                        Divider()
                        Button("Remove from Folder") {
                            onMoveToFolder(nil)
                        }
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .disabled(selectedScoreIds.isEmpty)
                }

                if !programs.isEmpty {
                    Menu {
                        ForEach(programs) { program in
                            Button(program.name) {
                                onAddToProgram(program)
                            }
                        }
                    } label: {
                        Label("Add to Program", systemImage: "music.note.list")
                    }
                    .disabled(selectedScoreIds.isEmpty)
                }

                Button(role: .destructive) {
                    showDeleteSelectedAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
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
                Button {
                    withAnimation { isSelecting = true }
                } label: {
                    Text("Select")
                }
                .disabled(selectableScores.isEmpty)
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: onImport) {
                        Label("Import Score", systemImage: "doc.badge.plus")
                    }
                    Button(action: onCreateFolder) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button(action: onCreateProgram) {
                        Label("New Program", systemImage: "music.note.list")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}
