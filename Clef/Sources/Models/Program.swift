import Foundation
import SwiftData

@Model
final class Program {
    var id: UUID
    var name: String
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \ProgramItem.program)
    var items: [ProgramItem] = []
    var createdAt: Date
    var updatedAt: Date

    init(name: String, folder: Folder? = nil) {
        self.id = UUID()
        self.name = name
        self.folder = folder
        self.createdAt = .now
        self.updatedAt = .now
    }

    var orderedItems: [ProgramItem] {
        items.sorted { $0.position < $1.position }
    }

    var orderedScores: [Score] {
        orderedItems.compactMap(\.score)
    }

    func nextScore(after score: Score) -> Score? {
        let ordered = orderedScores
        guard let index = ordered.firstIndex(where: { $0.id == score.id }),
              index + 1 < ordered.count else {
            return nil
        }
        return ordered[index + 1]
    }

    func appendScore(_ score: Score) {
        let maxPosition = items.map(\.position).max() ?? -1
        let item = ProgramItem(position: maxPosition + 1, score: score)
        items.append(item)
        updatedAt = .now
    }

    func removeScore(_ score: Score) {
        items.removeAll { $0.score?.id == score.id }
        reindex()
        updatedAt = .now
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        var ordered = orderedItems
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() {
            item.position = index
        }
        updatedAt = .now
    }

    private func reindex() {
        for (index, item) in orderedItems.enumerated() {
            item.position = index
        }
    }
}
