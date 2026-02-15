import SwiftUI
import PDFKit
import PencilKit

struct PDFKitView: UIViewRepresentable {
    let pdfData: Data
    @Binding var currentPageIndex: Int
    @Binding var totalPages: Int
    let isDrawingEnabled: Bool
    let isTwoPageMode: Bool
    let hasCoverPage: Bool
    let onDrawingChanged: (Int, PKDrawing) -> Void
    let drawingForPage: (Int) -> PKDrawing

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = isTwoPageMode ? .twoUp : .singlePage
        pdfView.displaysAsBook = hasCoverPage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true)
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = .secondarySystemBackground

        let overlayCoordinator = context.coordinator.overlayCoordinator
        pdfView.pageOverlayViewProvider = overlayCoordinator
        pdfView.isInMarkupMode = isDrawingEnabled

        if let document = PDFDocument(data: pdfData) {
            pdfView.document = document
            DispatchQueue.main.async {
                totalPages = document.pageCount
            }
        }

        context.coordinator.pdfView = pdfView
        context.coordinator.subscribeToPageChanges(pdfView)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        let targetMode: PDFDisplayMode = isTwoPageMode ? .twoUp : .singlePage
        if pdfView.displayMode != targetMode {
            pdfView.displayMode = targetMode
        }
        if pdfView.displaysAsBook != hasCoverPage {
            pdfView.displaysAsBook = hasCoverPage
        }

        if let document = pdfView.document,
           currentPageIndex < document.pageCount,
           let targetPage = document.page(at: currentPageIndex),
           pdfView.currentPage != targetPage {
            pdfView.go(to: targetPage)
        }

        let wasEnabled = pdfView.isInMarkupMode
        pdfView.isInMarkupMode = isDrawingEnabled
        context.coordinator.overlayCoordinator.setDrawingEnabled(isDrawingEnabled)

        if isDrawingEnabled && !wasEnabled {
            pdfView.panWithTwoFingers()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.unsubscribe()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        let overlayCoordinator: OverlayCoordinator
        private var pageObserver: NSObjectProtocol?

        init(parent: PDFKitView) {
            self.parent = parent
            self.overlayCoordinator = OverlayCoordinator(
                isDrawingEnabled: parent.isDrawingEnabled,
                onDrawingChanged: parent.onDrawingChanged,
                drawingForPage: parent.drawingForPage
            )
            super.init()
        }

        func subscribeToPageChanges(_ pdfView: PDFView) {
            pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.handlePageChange()
            }
        }

        func unsubscribe() {
            if let observer = pageObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            overlayCoordinator.cleanup()
        }

        private func handlePageChange() {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document
            else { return }

            let pageIndex = document.index(for: currentPage)
            parent.currentPageIndex = pageIndex
            overlayCoordinator.preloadDrawings(around: pageIndex, pageCount: document.pageCount)
            overlayCoordinator.preRenderPages(around: pageIndex, document: document)
        }
    }
}

@MainActor
final class OverlayCoordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate {
    private var canvasCache: [Int: PKCanvasView] = [:]
    private var canvasToPageIndex: [ObjectIdentifier: Int] = [:]
    private var drawingCache: [Int: PKDrawing] = [:]
    private var preRenderedPages: Set<Int> = []
    private var toolPicker = PKToolPicker()
    private var isDrawingEnabled: Bool
    private var onDrawingChanged: (Int, PKDrawing) -> Void
    private var drawingForPage: (Int) -> PKDrawing

    init(
        isDrawingEnabled: Bool,
        onDrawingChanged: @escaping (Int, PKDrawing) -> Void,
        drawingForPage: @escaping (Int) -> PKDrawing
    ) {
        self.isDrawingEnabled = isDrawingEnabled
        self.onDrawingChanged = onDrawingChanged
        self.drawingForPage = drawingForPage
        super.init()
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let document = view.document else { return nil }
        let pageIndex = document.index(for: page)

        if let existing = canvasCache[pageIndex] {
            existing.isUserInteractionEnabled = isDrawingEnabled
            if isDrawingEnabled {
                toolPicker.setVisible(true, forFirstResponder: existing)
                existing.becomeFirstResponder()
            }
            return existing
        }

        let canvasView = PKCanvasView(frame: .zero)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.delegate = self
        canvasView.isUserInteractionEnabled = isDrawingEnabled

        if let cached = drawingCache[pageIndex] {
            canvasView.drawing = cached
        } else {
            let drawing = drawingForPage(pageIndex)
            drawingCache[pageIndex] = drawing
            canvasView.drawing = drawing
        }

        toolPicker.addObserver(canvasView)
        if isDrawingEnabled {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        canvasCache[pageIndex] = canvasView
        canvasToPageIndex[ObjectIdentifier(canvasView)] = pageIndex
        return canvasView
    }

    func pdfView(
        _ pdfView: PDFView,
        willEndDisplayingOverlayView overlayView: UIView,
        for page: PDFPage
    ) {
        guard let canvasView = overlayView as? PKCanvasView,
              let document = pdfView.document
        else { return }

        // Save drawing but do NOT destroy canvas or remove toolPicker observer
        let pageIndex = document.index(for: page)
        let drawing = canvasView.drawing
        drawingCache[pageIndex] = drawing
        if !drawing.strokes.isEmpty {
            onDrawingChanged(pageIndex, drawing)
        }
    }

    func setDrawingEnabled(_ enabled: Bool) {
        guard isDrawingEnabled != enabled else { return }
        isDrawingEnabled = enabled

        for (_, canvasView) in canvasCache {
            canvasView.isUserInteractionEnabled = enabled
            if enabled {
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                canvasView.resignFirstResponder()
            }
        }
    }

    func preloadDrawings(around pageIndex: Int, pageCount: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for offset in [1, -1, 2, -2] {
                let target = pageIndex + offset
                guard target >= 0, target < pageCount, self.drawingCache[target] == nil else { continue }
                self.drawingCache[target] = self.drawingForPage(target)
            }
        }
    }

    func preRenderPages(around pageIndex: Int, document: PDFDocument) {
        var pagesToRender: [(PDFPage, CGSize)] = []
        for offset in [1, -1, 2, -2] {
            let target = pageIndex + offset
            guard target >= 0, target < document.pageCount,
                  !preRenderedPages.contains(target),
                  let page = document.page(at: target)
            else { continue }

            preRenderedPages.insert(target)
            let bounds = page.bounds(for: .cropBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            pagesToRender.append((page, size))
        }

        guard !pagesToRender.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [pagesToRender] in
            for (page, size) in pagesToRender {
                let _ = page.thumbnail(of: size, for: .cropBox)
            }
        }
    }

    func cleanup() {
        for (_, canvasView) in canvasCache {
            toolPicker.removeObserver(canvasView)
        }
        canvasCache.removeAll()
        canvasToPageIndex.removeAll()
        drawingCache.removeAll()
        preRenderedPages.removeAll()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let pageIndex = canvasToPageIndex[ObjectIdentifier(canvasView)] else { return }

        let drawing = canvasView.drawing
        drawingCache[pageIndex] = drawing
        onDrawingChanged(pageIndex, drawing)
    }
}

extension PDFView {
    func panWithTwoFingers() {
        for view in subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
            }
        }
    }
}
