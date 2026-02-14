import Foundation
import SwiftData
import PencilKit

@Model
final class PageAnnotation {
    var id: UUID
    var pageIndex: Int
    @Attribute(.externalStorage) var drawingData: Data
    var updatedAt: Date

    var score: Score?

    init(pageIndex: Int, drawing: PKDrawing = PKDrawing()) {
        self.id = UUID()
        self.pageIndex = pageIndex
        self.drawingData = drawing.dataRepresentation()
        self.updatedAt = .now
    }

    var drawing: PKDrawing {
        get {
            (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        }
        set {
            drawingData = newValue.dataRepresentation()
            updatedAt = .now
        }
    }
}
