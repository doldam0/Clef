import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \Score.folder)
    var scores: [Score] = []
    var createdAt: Date
    var updatedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
}
