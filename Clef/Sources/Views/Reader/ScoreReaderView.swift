import SwiftUI
import SwiftData
import PDFKit
import PencilKit

struct ScoreReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var score: Score
    @Binding var currentPageIndex: Int
    @Binding var showThumbnails: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var totalPages = 0
    @State private var isDrawingEnabled = false
    @State private var isPerformanceMode = false
    @State private var showControls = true
    @State private var saveTask: Task<Void, Never>?
    @State private var controlsTimer: Task<Void, Never>?
    @State private var pdfDocument: PDFDocument?
    @State private var pdfViewID = UUID()

    var body: some View {
        HStack(spacing: 0) {
            if showThumbnails, let document = pdfDocument {
                ThumbnailSidebarView(
                    document: document,
                    currentPageIndex: $currentPageIndex
                )
                .frame(width: 220)

                Divider()
            }

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
                }
            )
            .id(pdfViewID)
        }
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
        .navigationTitle(isPerformanceMode ? "" : score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isPerformanceMode && !showControls ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !isPerformanceMode {
                ToolbarItem(placement: .principal) {
                    pageIndicator
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    thumbnailToggle
                    drawingToggle
                    moreMenu
                }
            }
        }
        .statusBarHidden(isPerformanceMode)
        .ignoresSafeArea(isPerformanceMode ? .all : .container, edges: .bottom)
        .onAppear {
            pdfDocument = PDFDocument(data: score.pdfData)
        }
        .onDisappear {
            flushPendingSave()
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
                    showThumbnails = false
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

    private var thumbnailToggle: some View {
        Button {
            showThumbnails.toggle()
        } label: {
            Image(systemName: showThumbnails ? "sidebar.squares.left" : "sidebar.squares.leading")
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
                Label("두 쪽 보기", systemImage: "book.pages")
            }

            Toggle(isOn: $score.hasCoverPage) {
                Label("표지", systemImage: "text.book.closed")
            }
            .disabled(!score.isTwoPageMode)

            Divider()

            Button {
                withAnimation { isPerformanceMode = true }
            } label: {
                Label("공연 모드", systemImage: "play.rectangle.on.rectangle")
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
