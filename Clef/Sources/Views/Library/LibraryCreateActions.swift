import SwiftUI
import SwiftData

/// Hosts the "add" responders shared by the library screens — the score
/// importer and the New Folder / New Program alerts — all targeting `folder`
/// (nil for the top level). Triggered by the bound flags that `LibraryToolbar`
/// and the "new item" cards set.
struct LibraryCreateActionsModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    var folder: Folder?
    @Binding var isImporting: Bool
    @Binding var isCreatingFolder: Bool
    @Binding var isCreatingProgram: Bool

    @State private var newFolderName = ""
    @State private var newProgramName = ""

    func body(content: Content) -> some View {
        content
            .scoreImporter(isPresented: $isImporting, folder: folder)
            .alert("New Folder", isPresented: $isCreatingFolder) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") { createFolder() }
            }
            .alert("New Program", isPresented: $isCreatingProgram) {
                TextField("Program Name", text: $newProgramName)
                Button("Cancel", role: .cancel) { newProgramName = "" }
                Button("Create") { createProgram() }
            }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            newFolderName = ""
            return
        }
        let newFolder = Folder(name: trimmed)
        newFolder.parent = folder
        modelContext.insert(newFolder)
        try? modelContext.save()
        newFolderName = ""
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
}

extension View {
    /// Attaches the library "add" responders. Pass `enabled: false` where a
    /// child view (e.g. an embedded `BrowseCatalogView`) already hosts them, to
    /// avoid presenting two of each.
    @ViewBuilder
    func libraryCreateActions(
        enabled: Bool = true,
        folder: Folder?,
        isImporting: Binding<Bool>,
        isCreatingFolder: Binding<Bool>,
        isCreatingProgram: Binding<Bool>
    ) -> some View {
        if enabled {
            modifier(LibraryCreateActionsModifier(
                folder: folder,
                isImporting: isImporting,
                isCreatingFolder: isCreatingFolder,
                isCreatingProgram: isCreatingProgram
            ))
        } else {
            self
        }
    }
}
