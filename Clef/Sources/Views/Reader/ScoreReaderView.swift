import SwiftUI
import SwiftData
import PDFKit
import PencilKit

struct ScoreReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var score: Score
    let allTags: [String]
    var onSwipePastEnd: (() -> Void)? = nil
    var onSwipePastStart: (() -> Void)? = nil
    var onNextScore: (() -> Void)? = nil
    var onPreviousScore: (() -> Void)? = nil
    var programScores: [Score]? = nil
    var onSelectProgramScore: ((Score) -> Void)? = nil
    @State private var currentPageIndex = 0
    @State private var totalPages = 0
    @State private var isDrawingEnabled = false
    @State private var isPerformanceMode = false
    @State private var showControls = true
    @State private var saveTask: Task<Void, Never>?
    @State private var controlsTimer: Task<Void, Never>?
    @State private var pdfDocument: PDFDocument?
    @State private var pdfViewID = UUID()
    @State private var showMetadataEditor = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if let document = pdfDocument {
                ThumbnailSidebarView(
                    document: document,
                    currentPageIndex: $currentPageIndex
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            }
        } detail: {
            PDFKitView(
                pdfData: score.pdfData,
                currentPageIndex: $currentPageIndex,
                totalPages: $totalPages,
                isDrawingEnabled: isDrawingEnabled,
                isTwoPageMode: score.isTwoPageMode,
                hasCoverPage: score.hasCoverPage,
                onDrawingChanged: { pageIndex, drawing in
                    debounceSave(drawing, for: pageIndex)
                },
                drawingForPage: { pageIndex in
                    loadDrawing(for: pageIndex)
                },
                onSwipePastEnd: onSwipePastEnd,
                onSwipePastStart: onSwipePastStart
            )
            .id(pdfViewID)
            .toolbarRole(.editor)
            .navigationTitle(score.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                if let programScores, let onSelectProgramScore {
                    ForEach(programScores, id: \.id) { programScore in
                        Button {
                            onSelectProgramScore(programScore)
                        } label: {
                            HStack {
                                Text(programScore.title)
                                if programScore.id == score.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(programScore.id == score.id)
                    }

                    Divider()
                }

                Button {
                    showMetadataEditor = true
                } label: {
                    Label("Score Info", systemImage: "info.circle")
                }
            }
            .toolbar(isPerformanceMode && !showControls ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !isPerformanceMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        drawingToggle
                    }
                    if let onPreviousScore {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                onPreviousScore()
                            } label: {
                                Label("Previous Score", systemImage: "backward.end")
                            }
                        }
                    }
                    if let onNextScore {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                onNextScore()
                            } label: {
                                Label("Next Score", systemImage: "forward.end")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        moreMenu
                    }
                }
            }
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .secondaryAction) {
                        if !isPerformanceMode {
                            pageIndicator
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .secondaryAction) {
                        if !isPerformanceMode {
                            pageIndicator
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .overlay {
            if isPerformanceMode && showControls {
                performanceOverlay
            }
        }
        .simultaneousGesture(
            isPerformanceMode
                ? TapGesture().onEnded { toggleControls() }
                : nil
        )
        .statusBarHidden(isPerformanceMode)
        .ignoresSafeArea(isPerformanceMode ? .all : .container, edges: .bottom)
        .onAppear {
            pdfDocument = PDFDocument(data: score.pdfData)
            score.lastPlayedAt = .now
            try? modelContext.save()
        }
        .onDisappear {
            flushPendingSave()
        }
        .sheet(isPresented: $showMetadataEditor) {
            ScoreMetadataEditorView(score: score, existingTags: allTags)
        }
        .onChange(of: score.isTwoPageMode) {
            pdfViewID = UUID()
        }
        .onChange(of: score.hasCoverPage) {
            if score.isTwoPageMode {
                pdfViewID = UUID()
            }
        }
        .onChange(of: isPerformanceMode) { _, entering in
            if entering {
                isDrawingEnabled = false
                withAnimation {
                    columnVisibility = .detailOnly
                }
                showControls = false
            } else {
                showControls = true
            }
        }
    }

    private var performanceOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation { isPerformanceMode = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .padding()
            }

            Spacer()

            if totalPages > 0 {
                Text("\(currentPageIndex + 1) / \(totalPages)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .transition(.opacity)
    }

    private var pageIndicator: some View {
        Group {
            if totalPages > 0 {
                Text("\(currentPageIndex + 1) / \(totalPages)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var drawingToggle: some View {
        Button {
            isDrawingEnabled.toggle()
        } label: {
            Image(systemName: isDrawingEnabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
        }
    }

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $score.isTwoPageMode) {
                Label("Two-Page View", systemImage: "book.pages")
            }

            Toggle(isOn: $score.hasCoverPage) {
                Label("Cover Page", systemImage: "text.book.closed")
            }
            .disabled(!score.isTwoPageMode)

            Divider()

            Button {
                withAnimation { isPerformanceMode = true }
            } label: {
                Label("Performance Mode", systemImage: "play.rectangle.on.rectangle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func toggleControls() {
        controlsTimer?.cancel()
        showControls.toggle()
        if showControls {
            controlsTimer = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, isPerformanceMode else { return }
                showControls = false
            }
        }
    }

    private func debounceSave(_ drawing: PKDrawing, for pageIndex: Int) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            persistDrawing(drawing, for: pageIndex)
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        try? modelContext.save()
    }

    private func persistDrawing(_ drawing: PKDrawing, for pageIndex: Int) {
        let annotation = score.getOrCreateAnnotation(for: pageIndex, in: modelContext)
        annotation.drawing = drawing
        try? modelContext.save()
    }

    private func loadDrawing(for pageIndex: Int) -> PKDrawing {
        score.annotation(for: pageIndex)?.drawing ?? PKDrawing()
    }
}
