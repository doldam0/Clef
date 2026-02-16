import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var parent: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder] = []
    @Relationship(deleteRule: .nullify, inverse: \Score.folder)
    var scores: [Score] = []
    @Relationship(deleteRule: .cascade, inverse: \Program.folder)
    var programs: [Program] = []
    var createdAt: Date
    var updatedAt: Date

    init(name: String, parent: Folder? = nil) {
        self.id = UUID()
        self.name = name
        self.parent = parent
        self.createdAt = .now
        self.updatedAt = .now
    }

    var totalScoreCount: Int {
        var count = scores.count
        for program in programs {
            count += program.items.count
        }
        for child in children {
            count += child.totalScoreCount
        }
        return count
    }
}
