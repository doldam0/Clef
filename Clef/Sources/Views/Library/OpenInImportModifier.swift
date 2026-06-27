import SwiftUI
import SwiftData

/// Handles files delivered via "Open in Clef": when the inbox has pending files
/// it asks where to put them, then feeds them into the regular import pipeline
/// (metadata analysis + confirmation) targeting the chosen folder.
struct OpenInImportModifier: ViewModifier {
    @ObservedObject private var inbox = ImportInbox.shared

    @State private var showDestinationPicker = false
    @State private var chosenFolder: Folder?
    @State private var filesToImport: [ImportFile] = []

    func body(content: Content) -> some View {
        content
            .onAppear { presentPickerIfNeeded() }
            .onChange(of: inbox.pending.count) { presentPickerIfNeeded() }
            .sheet(isPresented: $showDestinationPicker) {
                ImportDestinationPicker(
                    fileCount: inbox.pending.count,
                    onSelect: { folder in
                        showDestinationPicker = false
                        chosenFolder = folder
                        filesToImport = inbox.take()
                    },
                    onCancel: {
                        showDestinationPicker = false
                        inbox.clear()
                    }
                )
            }
            .scoreImporter(
                isPresented: .constant(false),
                folder: chosenFolder,
                externalFiles: $filesToImport
            )
    }

    private func presentPickerIfNeeded() {
        guard !inbox.pending.isEmpty, !showDestinationPicker else { return }
        showDestinationPicker = true
    }
}

extension View {
    func openInImporter() -> some View {
        modifier(OpenInImportModifier())
    }
}

/// A sheet that lets the user drill down through the folder tree and pick where
/// received files should go (or the top-level library).
private struct ImportDestinationPicker: View {
    let fileCount: Int
    let onSelect: (Folder?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            FolderLevelView(folder: nil, onSelect: onSelect)
                .navigationTitle(titleKey)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                }
        }
    }

    private var titleKey: LocalizedStringKey {
        fileCount == 1 ? "Import 1 file to…" : "Import \(fileCount) files to…"
    }
}

/// One level of the destination tree: an "import here" action for the current
/// folder, plus its subfolders that drill deeper when tapped.
private struct FolderLevelView: View {
    @Query private var allFolders: [Folder]
    let folder: Folder?
    let onSelect: (Folder?) -> Void

    private var subfolders: [Folder] {
        let children = folder?.children ?? allFolders.filter { $0.parent == nil }
        return children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Button {
                    onSelect(folder)
                } label: {
                    Label(importHereLabel, systemImage: "tray.and.arrow.down")
                }
            }

            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { child in
                        NavigationLink {
                            FolderLevelView(folder: child, onSelect: onSelect)
                                .navigationTitle(child.name)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label(child.name, systemImage: "folder")
                        }
                    }
                }
            }
        }
    }

    private var importHereLabel: LocalizedStringKey {
        if let folder {
            return "Import to “\(folder.name)”"
        }
        return "Import to Library"
    }
}
