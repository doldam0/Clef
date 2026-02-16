import SwiftUI

// MARK: - PreferenceKey for collecting item frames

struct DragSelectFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Per-item frame reporter

extension View {
    func dragSelectFrame(id: UUID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: DragSelectFrameKey.self,
                    value: [id: geo.frame(in: .named("dragSelect"))]
                )
            }
        )
    }
}

// MARK: - Drag-to-select grid modifier

struct DragSelectModifier: ViewModifier {
    @Binding var selectedIds: Set<UUID>
    let isSelecting: Bool
    let orderedIds: [UUID]

    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragStartIndex: Int?
    @State private var preDragSelection: Set<UUID> = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "dragSelect")
            .onPreferenceChange(DragSelectFrameKey.self) { frames = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named("dragSelect"))
                    .onChanged { value in
                        guard isSelecting else { return }

                        if dragStartIndex == nil {
                            dragStartIndex = indexOfItem(at: value.startLocation)
                            preDragSelection = selectedIds
                        }

                        guard let startIdx = dragStartIndex,
                              let currentIdx = indexOfItem(at: value.location)
                        else { return }

                        let lo = min(startIdx, currentIdx)
                        let hi = max(startIdx, currentIdx)
                        var newSelection = preDragSelection
                        for i in lo...hi {
                            newSelection.insert(orderedIds[i])
                        }
                        selectedIds = newSelection
                    }
                    .onEnded { _ in
                        dragStartIndex = nil
                        preDragSelection = []
                    }
            )
    }

    private func indexOfItem(at point: CGPoint) -> Int? {
        for (id, frame) in frames {
            if frame.contains(point), let idx = orderedIds.firstIndex(of: id) {
                return idx
            }
        }
        return nil
    }
}

extension View {
    func dragToSelect(
        selectedIds: Binding<Set<UUID>>,
        isSelecting: Bool,
        orderedIds: [UUID]
    ) -> some View {
        modifier(DragSelectModifier(
            selectedIds: selectedIds,
            isSelecting: isSelecting,
            orderedIds: orderedIds
        ))
    }
}
