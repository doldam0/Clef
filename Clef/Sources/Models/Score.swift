import Foundation
import SwiftData

@Model
final class Score {
    var id: UUID
    var title: String
    var composer: String?
    var instrument: String?
    var tags: [String]
    @Attribute(.externalStorage) var pdfData: Data
    @Relationship(deleteRule: .cascade, inverse: \PageAnnotation.score)
    var pageAnnotations: [PageAnnotation] = []
    var folder: Folder?
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String,
        composer: String? = nil,
        instrument: String? = nil,
        tags: [String] = [],
        pdfData: Data
    ) {
        self.id = UUID()
        self.title = title
        self.composer = composer
        self.instrument = instrument
        self.tags = tags
        self.pdfData = pdfData
        self.createdAt = .now
        self.updatedAt = .now
    }

    func annotation(for pageIndex: Int) -> PageAnnotation? {
        pageAnnotations.first { $0.pageIndex == pageIndex }
    }

    func getOrCreateAnnotation(for pageIndex: Int, in context: ModelContext) -> PageAnnotation {
        if let existing = annotation(for: pageIndex) {
            return existing
        }
        let annotation = PageAnnotation(pageIndex: pageIndex)
        pageAnnotations.append(annotation)
        return annotation
    }
}
