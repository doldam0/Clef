import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScoreImportModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    var program: Program?
    var folder: Folder?
    /// Files supplied from outside the file picker (e.g. "Open in Clef"). Setting
    /// this imports them into `folder`, then clears itself.
    @Binding var externalFiles: [ImportFile]

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .onChange(of: externalFiles.map(\.id)) {
                let files = externalFiles
                guard !files.isEmpty else { return }
                externalFiles = []
                importFiles(files)
            }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        var files: [ImportFile] = []
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let pdfData = try? Data(contentsOf: url) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            files.append(ImportFile(title: title, data: pdfData))
        }

        importFiles(files)
    }

    /// Imports each PDF using its file name as the title and leaving the rest of
    /// the metadata blank for the user to fill in later.
    private func importFiles(_ files: [ImportFile]) {
        guard !files.isEmpty else { return }

        for file in files {
            let score = Score(title: file.title, pdfData: file.data)
            modelContext.insert(score)

            if let folder {
                score.folder = folder
            }
            if let program {
                program.appendScore(score)
            }
        }

        try? modelContext.save()
    }
}

extension View {
    func scoreImporter(
        isPresented: Binding<Bool>,
        program: Program? = nil,
        folder: Folder? = nil,
        externalFiles: Binding<[ImportFile]> = .constant([])
    ) -> some View {
        modifier(ScoreImportModifier(
            isPresented: isPresented,
            program: program,
            folder: folder,
            externalFiles: externalFiles
        ))
    }
}
