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

/// A sheet that lets the user choose which folder received files should go into
/// (or the top-level library).
private struct ImportDestinationPicker: View {
    @Query(sort: \Folder.name) private var folders: [Folder]
    let fileCount: Int
    let onSelect: (Folder?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        Label("Library", systemImage: "house")
                    }
                }

                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(foldersByPath, id: \.id) { folder in
                            Button {
                                onSelect(folder)
                            } label: {
                                Label(path(for: folder), systemImage: "folder")
                            }
                        }
                    }
                }
            }
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

    private var foldersByPath: [Folder] {
        folders.sorted { path(for: $0).localizedStandardCompare(path(for: $1)) == .orderedAscending }
    }

    private func path(for folder: Folder) -> String {
        var parts: [String] = []
        var current: Folder? = folder
        while let node = current {
            parts.insert(node.name, at: 0)
            current = node.parent
        }
        return parts.joined(separator: " / ")
    }
}
