import Foundation
import SwiftData

@Model
final class ProgramItem {
    var id: UUID
    var position: Int
    var program: Program?
    var score: Score?
    var addedAt: Date
    var updatedAt: Date

    init(position: Int, score: Score? = nil) {
        self.id = UUID()
        self.position = position
        self.score = score
        self.addedAt = .now
        self.updatedAt = .now
    }
}
