import SwiftUI
@preconcurrency import PDFKit
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
    var onSwipePastEnd: (() -> Void)? = nil

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = isTwoPageMode ? .twoUp : .singlePage
        pdfView.displayDirection = .horizontal
        if isTwoPageMode {
            pdfView.displaysAsBook = hasCoverPage
        }
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = .secondarySystemBackground

        if isTwoPageMode {
            pdfView.usePageViewController(false)

            let swipeLeft = UISwipeGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.nextPage)
            )
            swipeLeft.direction = .left
            pdfView.addGestureRecognizer(swipeLeft)

            let swipeRight = UISwipeGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.previousPage)
            )
            swipeRight.direction = .right
            pdfView.addGestureRecognizer(swipeRight)
        } else {
            pdfView.usePageViewController(true)

            if onSwipePastEnd != nil {
                let swipeLeft = UISwipeGestureRecognizer(
                    target: context.coordinator,
                    action: #selector(Coordinator.handleSwipePastEnd)
                )
                swipeLeft.direction = .left
                pdfView.addGestureRecognizer(swipeLeft)
            }
        }

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
                Task { @MainActor [weak self] in
                    self?.handlePageChange()
                }
            }
        }

        func unsubscribe() {
            if let observer = pageObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            overlayCoordinator.cleanup()
        }

        @objc func handleSwipePastEnd() {
            guard let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage else { return }
            let pageIndex = document.index(for: currentPage)
            if pageIndex >= document.pageCount - 1 {
                parent.onSwipePastEnd?()
            }
        }

        @objc func nextPage() {
            guard let pdfView, pdfView.canGoToNextPage else { return }
            let transition = CATransition()
            transition.type = .push
            transition.subtype = .fromRight
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pdfView.layer.add(transition, forKey: "pageTransition")
            pdfView.goToNextPage(nil)
        }

        @objc func previousPage() {
            guard let pdfView, pdfView.canGoToPreviousPage else { return }
            let transition = CATransition()
            transition.type = .push
            transition.subtype = .fromLeft
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pdfView.layer.add(transition, forKey: "pageTransition")
            pdfView.goToPreviousPage(nil)
        }

        private func handlePageChange() {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document
            else { return }

            let pageIndex = document.index(for: currentPage)
            parent.currentPageIndex = pageIndex
            let isTwoPage = parent.isTwoPageMode
            overlayCoordinator.preloadDrawings(around: pageIndex, pageCount: document.pageCount, isTwoPageMode: isTwoPage)
            overlayCoordinator.preRenderPages(around: pageIndex, document: document, isTwoPageMode: isTwoPage)
        }
    }
}

@MainActor
final class OverlayCoordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate, PKToolPickerObserver {
    private var canvasCache: [Int: PKCanvasView] = [:]
    private var canvasToPageIndex: [ObjectIdentifier: Int] = [:]
    private var drawingCache: [Int: PKDrawing] = [:]
    private var preRenderedPages: Set<Int> = []
    private var toolPicker: PKToolPicker!

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
        configureToolPicker()
    }

    private func configureToolPicker() {
        toolPicker = PKToolPicker()
        toolPicker.addObserver(self)
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let document = view.document else { return nil }
        let pageIndex = document.index(for: page)

        if let existing = canvasCache[pageIndex] {
            existing.isUserInteractionEnabled = isDrawingEnabled
            updateToolPicker(for: existing)
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
        canvasCache[pageIndex] = canvasView
        canvasToPageIndex[ObjectIdentifier(canvasView)] = pageIndex
        updateToolPicker(for: canvasView)
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

        for canvasView in canvasCache.values {
            canvasView.isUserInteractionEnabled = enabled
            updateToolPicker(for: canvasView)
        }
    }

    func preloadDrawings(around pageIndex: Int, pageCount: Int, isTwoPageMode: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let offsets = isTwoPageMode
                ? [1, -1, 2, -2, 3, -3, 4, -4]
                : [1, -1, 2, -2]
            for offset in offsets {
                let target = pageIndex + offset
                guard target >= 0, target < pageCount, self.drawingCache[target] == nil else { continue }
                self.drawingCache[target] = self.drawingForPage(target)
            }
        }
    }

    func preRenderPages(around pageIndex: Int, document: PDFDocument, isTwoPageMode: Bool) {
        var pagesToRender: [(PDFPage, CGSize)] = []
        let offsets = isTwoPageMode
            ? [1, -1, 2, -2, 3, -3, 4, -4]
            : [1, -1, 2, -2]
        for offset in offsets {
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
                _ = page.thumbnail(of: size, for: .cropBox)
            }
        }
    }

    func cleanup() {
        for canvasView in canvasCache.values {
            toolPicker.removeObserver(canvasView)
        }
        toolPicker.removeObserver(self)
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

    private func updateToolPicker(for canvasView: PKCanvasView) {
        if isDrawingEnabled {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        } else {
            toolPicker.setVisible(false, forFirstResponder: canvasView)
            canvasView.resignFirstResponder()
        }
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

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let hexNumber = UInt64(hexSanitized, radix: 16) else { return nil }

        self.init(
            red: CGFloat((hexNumber & 0xFF0000) >> 16) / 255,
            green: CGFloat((hexNumber & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hexNumber & 0x0000FF) / 255,
            alpha: 1.0
        )
    }
}
