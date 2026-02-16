import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScoreImportModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    var program: Program?

    @State private var isAnalyzing = false
    @State private var analysisProgress = (current: 0, total: 0)
    @State private var metadataQueue: [(score: Score, metadata: ExtractedMetadata)] = []
    @State private var metadataTotal = 0
    @State private var showConfirmation = false

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .overlay {
                if isAnalyzing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Analyzing Metadata...")
                                .font(.headline)
                            if analysisProgress.total > 1 {
                                Text("\(analysisProgress.current) / \(analysisProgress.total)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(32)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .sheet(isPresented: $showConfirmation) {
                if let first = metadataQueue.first {
                    MetadataConfirmationView(
                        score: first.score,
                        extracted: first.metadata,
                        currentIndex: metadataTotal - metadataQueue.count,
                        totalCount: metadataTotal
                    ) {
                        metadataQueue.removeFirst()
                        if !metadataQueue.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showConfirmation = true
                            }
                        }
                    }
                    .id(first.score.id)
                }
            }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        var importedScores: [Score] = []

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let pdfData = try? Data(contentsOf: url) else { continue }

            let title = url.deletingPathExtension().lastPathComponent
            let score = Score(title: title, pdfData: pdfData)
            modelContext.insert(score)

            if let program {
                program.appendScore(score)
            }

            importedScores.append(score)
        }

        try? modelContext.save()

        guard !importedScores.isEmpty else { return }

        isAnalyzing = true
        analysisProgress = (current: 0, total: importedScores.count)

        Task {
            let pdfDataList: [(index: Int, pdfData: Data)] = importedScores.enumerated().map { ($0.offset, $0.element.pdfData) }

            let metadataResults = await withTaskGroup(
                of: (Int, ExtractedMetadata).self,
                returning: [ExtractedMetadata].self
            ) { group in
                for item in pdfDataList {
                    let pdfData = item.pdfData
                    let index = item.index
                    group.addTask {
                        let metadata = await MetadataExtractor.shared.extract(from: pdfData)
                        return (index, metadata)
                    }
                }

                var results: [(Int, ExtractedMetadata)] = []
                for await result in group {
                    results.append(result)
                    await MainActor.run {
                        analysisProgress.current = results.count
                    }
                }

                return results.sorted { $0.0 < $1.0 }.map { $0.1 }
            }

            var queue: [(score: Score, metadata: ExtractedMetadata)] = []
            for (index, score) in importedScores.enumerated() {
                queue.append((score: score, metadata: metadataResults[index]))
            }

            isAnalyzing = false
            metadataQueue = queue
            metadataTotal = queue.count
            showConfirmation = true
        }
    }
}

extension View {
    func scoreImporter(isPresented: Binding<Bool>, program: Program? = nil) -> some View {
        modifier(ScoreImportModifier(isPresented: isPresented, program: program))
    }
}
