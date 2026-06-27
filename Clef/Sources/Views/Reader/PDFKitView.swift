import SwiftUI
@preconcurrency import PDFKit
import PencilKit
import UIKit.UIGestureRecognizerSubclass

/// Recognizes the moment three fingers are down, and fails the moment the touch
/// is clearly not a three-finger gesture (movement begins with fewer than three
/// touches). Paging gestures `require(toFail:)` this, so a three-finger
/// undo/redo swipe never turns the page, while one- and two-finger swipes still
/// page with no perceptible delay (the gate fails as soon as they move).
final class ThreeFingerGate: UIGestureRecognizer {
    private func activeTouchCount(_ event: UIEvent) -> Int {
        (event.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }.count
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if activeTouchCount(event) >= 3 { state = .began }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible else { return }
        if activeTouchCount(event) >= 3 {
            state = .began
        } else if let touch = touches.first {
            // Movement with fewer than three touches means a one/two-finger
            // swipe — fail quickly so paging can begin. The small threshold
            // leaves room for a slightly staggered third finger to land.
            let current = touch.location(in: view)
            let previous = touch.previousLocation(in: view)
            if abs(current.x - previous.x) > 10 || abs(current.y - previous.y) > 10 {
                state = .failed
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if state == .began || state == .changed {
            state = .ended
        } else if activeTouchCount(event) == 0 {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }
}

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
    var onSwipePastStart: (() -> Void)? = nil

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

            if onSwipePastEnd != nil || onSwipePastStart != nil {
                let pan = UIPanGestureRecognizer(
                    target: context.coordinator,
                    action: #selector(Coordinator.handleBoundaryPan(_:))
                )
                pan.delegate = context.coordinator
                pdfView.addGestureRecognizer(pan)
            }
        }

        let overlayCoordinator = context.coordinator.overlayCoordinator
        pdfView.pageOverlayViewProvider = overlayCoordinator
        overlayCoordinator.attachToolHost(to: pdfView)
        pdfView.isInMarkupMode = isDrawingEnabled

        if let document = PDFDocument(data: pdfData) {
            pdfView.document = document
            DispatchQueue.main.async {
                totalPages = document.pageCount
                pdfView.hideScrollIndicators()
            }
        }

        context.coordinator.pdfView = pdfView
        context.coordinator.subscribeToPageChanges(pdfView)
        context.coordinator.installPagingBlocker(on: pdfView)

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
        context.coordinator.setPagingBlockerActive(isDrawingEnabled)

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
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        let overlayCoordinator: OverlayCoordinator
        private var pageObserver: NSObjectProtocol?
        private var hasFiredBoundary = false

        /// A three-finger gate that does nothing on its own. Paging gestures are
        /// made to require it to fail, so when three fingers are down (a system
        /// undo/redo swipe) the page stays put. With one or two fingers it fails
        /// as soon as they move and paging proceeds normally.
        private var pagingBlocker: ThreeFingerGate?

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

        // MARK: - Three-finger paging blocker

        func installPagingBlocker(on pdfView: PDFView) {
            guard pagingBlocker == nil else { return }
            let blocker = ThreeFingerGate(
                target: self,
                action: #selector(handlePagingBlocker(_:))
            )
            blocker.delegate = self
            // Don't swallow the touches — the system undo/redo gesture still
            // needs to see them.
            blocker.cancelsTouchesInView = false
            blocker.delaysTouchesBegan = false
            blocker.delaysTouchesEnded = false
            blocker.isEnabled = false
            pdfView.addGestureRecognizer(blocker)
            pagingBlocker = blocker
        }

        /// Enables/disables the blocker. Only active while drawing, since that's
        /// the only time the three-finger undo/redo gesture is in play.
        func setPagingBlockerActive(_ active: Bool) {
            pagingBlocker?.isEnabled = active
            if active {
                refreshPagingBlockerRequirements()
            }
        }

        /// Walks the PDF view hierarchy and makes every pan/swipe gesture defer
        /// to the blocker. Re-run after page changes because PDFKit rebuilds its
        /// internal paging gestures.
        func refreshPagingBlockerRequirements() {
            guard let pdfView, let blocker = pagingBlocker else { return }
            requirePagingFailure(in: pdfView, blocker: blocker)
        }

        private func requirePagingFailure(in view: UIView, blocker: UIGestureRecognizer) {
            // Skip annotation canvases entirely: their drawing/lasso gestures
            // must not wait on the blocker, or a slow pencil lasso (which stays
            // under the gate's movement threshold) gets stuck instead of
            // selecting. Paging gestures live outside the canvases.
            if view is PKCanvasView { return }
            for recognizer in view.gestureRecognizers ?? [] where recognizer !== blocker {
                if recognizer is UIPanGestureRecognizer || recognizer is UISwipeGestureRecognizer {
                    recognizer.require(toFail: blocker)
                }
            }
            for subview in view.subviews {
                requirePagingFailure(in: subview, blocker: blocker)
            }
        }

        @objc private func handlePagingBlocker(_ gesture: UIGestureRecognizer) {
            // Intentionally empty: it exists only to win recognition against the
            // paging gestures when three fingers are down.
        }

        // MARK: - Boundary swipe detection

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleBoundaryPan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else {
                if gesture.state == .began {
                    hasFiredBoundary = false
                }
                return
            }
            guard !hasFiredBoundary else { return }

            guard let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage else { return }

            let pageIndex = document.index(for: currentPage)
            let velocity = gesture.velocity(in: pdfView)
            let threshold: CGFloat = 300

            if pageIndex >= document.pageCount - 1 && velocity.x < -threshold {
                hasFiredBoundary = true
                parent.onSwipePastEnd?()
            } else if pageIndex == 0 && velocity.x > threshold {
                hasFiredBoundary = true
                parent.onSwipePastStart?()
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
            // PDFKit can rebuild its internal paging gestures across page
            // transitions, dropping the fail-requirement we install — reapply
            // while drawing so three-finger undo/redo keeps the page in place.
            if pdfView.isInMarkupMode {
                refreshPagingBlockerRequirements()
            }
            pdfView.hideScrollIndicators()
            overlayCoordinator.setCurrentPage(pageIndex)
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

    /// Invisible, page-independent canvas that owns the tool picker. It stays
    /// first responder for the whole drawing session so the palette never hides
    /// while paging. Per-page canvases mirror its selected tool via the observer
    /// relationship, and are also registered with the picker so the palette
    /// survives when the lasso tool makes one of them first responder.
    private let toolHost = PKCanvasView(frame: .zero)

    private var isDrawingEnabled: Bool
    private var hasAssertedHost = false
    private var currentPageIndex = 0
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
        // Observing keeps `toolHost.tool` in sync with the picker, so new page
        // canvases can copy the current tool at creation time.
        toolPicker.addObserver(toolHost)
    }

    /// Adds the tool-host anchor into the view hierarchy so it can become
    /// first responder. Must be called once the `PDFView` exists in a window.
    func attachToolHost(to hostView: UIView) {
        guard toolHost.superview == nil else { return }
        // Keep interaction enabled (UIKit refuses first responder otherwise),
        // but the zero frame means it never receives touches itself.
        hostView.addSubview(toolHost)
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let document = view.document else { return nil }
        let pageIndex = document.index(for: page)

        if let existing = canvasCache[pageIndex] {
            existing.isUserInteractionEnabled = isDrawingEnabled
            return existing
        }

        let canvasView = PKCanvasView(frame: .zero)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.delegate = self
        canvasView.isUserInteractionEnabled = isDrawingEnabled
        canvasView.showsVerticalScrollIndicator = false
        canvasView.showsHorizontalScrollIndicator = false
        // Mirror the picker's current tool immediately; the observer below keeps
        // it in sync for subsequent changes.
        canvasView.tool = toolHost.tool

        if let cached = drawingCache[pageIndex] {
            canvasView.drawing = cached
        } else {
            let drawing = drawingForPage(pageIndex)
            drawingCache[pageIndex] = drawing
            canvasView.drawing = drawing
        }

        toolPicker.addObserver(canvasView)
        // Register as a monitored responder so the palette stays visible when the
        // lasso tool makes this canvas first responder. The anchor owns the
        // palette the rest of the time.
        toolPicker.setVisible(true, forFirstResponder: canvasView)
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

        let pageIndex = document.index(for: page)
        let drawing = canvasView.drawing
        drawingCache[pageIndex] = drawing
        if !drawing.strokes.isEmpty {
            onDrawingChanged(pageIndex, drawing)
        }
    }

    func setDrawingEnabled(_ enabled: Bool) {
        let changed = isDrawingEnabled != enabled
        isDrawingEnabled = enabled

        if changed {
            for canvasView in canvasCache.values {
                canvasView.isUserInteractionEnabled = enabled
            }
        }

        // The palette follows the anchor's responder state, which is stable
        // across page turns — so it stays put instead of blinking. Assert it
        // once per enable (covers a freshly recreated view that starts enabled)
        // without re-asserting on every layout pass, so manual palette
        // dismissal is respected.
        if enabled {
            guard changed || !hasAssertedHost else { return }
            hasAssertedHost = true
            toolPicker.setVisible(true, forFirstResponder: toolHost)
            updateFirstResponder()
        } else if changed {
            hasAssertedHost = false
            toolPicker.setVisible(false, forFirstResponder: toolHost)
            // Resign the anchor and any canvas left first responder by a lasso
            // selection, so no monitored responder keeps the palette up.
            for canvasView in canvasCache.values {
                canvasView.resignFirstResponder()
            }
            toolHost.resignFirstResponder()
        }
    }

    /// Tracks the visible page so first responder can be re-routed after a turn.
    func setCurrentPage(_ pageIndex: Int) {
        currentPageIndex = pageIndex
        // Defer: touching first responder synchronously during a page transition
        // fights the transition. Running next turn lets the new page settle.
        Task { @MainActor [weak self] in self?.updateFirstResponder() }
    }

    private var isLassoSelected: Bool {
        toolHost.tool is PKLassoTool
    }

    /// Decides which view owns first responder. The lasso tool needs the visible
    /// page canvas (so selection and its edit menu work); every other tool keeps
    /// the page-independent anchor. Crucially, no *off-screen* page canvas may
    /// remain first responder — UIKit scrolls to keep a first responder visible,
    /// which would snap the PDF back a page. The anchor lives outside the scroll
    /// view, so holding it there is safe. Both are registered with the picker,
    /// so the palette never drops when first responder moves between them.
    private func updateFirstResponder() {
        guard isDrawingEnabled else { return }
        if isLassoSelected, let canvas = canvasCache[currentPageIndex] {
            for (index, other) in canvasCache where index != currentPageIndex && other.isFirstResponder {
                other.resignFirstResponder()
            }
            if !canvas.isFirstResponder {
                canvas.becomeFirstResponder()
            }
        } else {
            for canvasView in canvasCache.values where canvasView.isFirstResponder {
                canvasView.resignFirstResponder()
            }
            if !toolHost.isFirstResponder {
                toolHost.becomeFirstResponder()
            }
        }
    }

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        // Defer so the anchor (also an observer) has updated its `tool` first.
        Task { @MainActor [weak self] in self?.updateFirstResponder() }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        // After a non-lasso stroke, hand first responder back to the anchor so
        // this off-screen-able canvas can't drag the page back on the next turn.
        guard !isLassoSelected else { return }
        updateFirstResponder()
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
            toolPicker.setVisible(false, forFirstResponder: canvasView)
        }
        toolPicker.setVisible(false, forFirstResponder: toolHost)
        toolHost.resignFirstResponder()
        toolPicker.removeObserver(toolHost)
        toolHost.removeFromSuperview()
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

}

extension PDFView {
    func panWithTwoFingers() {
        for view in subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
            }
        }
    }

    /// Hides the stray scroll indicator (a small gray bar) shown by the internal
    /// paging/content scroll views. PDFKit rebuilds these across page changes, so
    /// this is reapplied on every page turn.
    func hideScrollIndicators() {
        hideScrollIndicators(in: self)
    }

    private func hideScrollIndicators(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
        }
        for subview in view.subviews {
            hideScrollIndicators(in: subview)
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
