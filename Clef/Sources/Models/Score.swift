import Foundation
import SwiftData

@Model
final class Score {
    var id: UUID
    var title: String
    var composer: String?
    var instruments: [String]
    var tags: [String]
    @Attribute(.externalStorage) var pdfData: Data
    @Relationship(deleteRule: .cascade, inverse: \PageAnnotation.score)
    var pageAnnotations: [PageAnnotation] = []
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \ProgramItem.score)
    var programItems: [ProgramItem] = []
    var isTwoPageMode: Bool = false
    var hasCoverPage: Bool = true
    var isFavorite: Bool = false
    var practiceStatusRaw: Int = 0
    var lastPlayedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var practiceStatus: PracticeStatus {
        get { PracticeStatus(rawValue: practiceStatusRaw) ?? .notStarted }
        set { practiceStatusRaw = newValue.rawValue }
    }

    init(
        title: String,
        composer: String? = nil,
        instruments: [String] = [],
        tags: [String] = [],
        pdfData: Data
    ) {
        self.id = UUID()
        self.title = title
        self.composer = composer
        self.instruments = instruments
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
