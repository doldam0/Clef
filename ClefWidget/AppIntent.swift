import WidgetKit
import AppIntents

/// Configuration for the Folder widget: pick which folder to display. The folder
/// list comes from the snapshot the app writes into the App Group.
struct SelectFolderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Folder" }
    static var description: IntentDescription { "Choose a folder to display." }

    @Parameter(title: "Folder")
    var folder: FolderEntity?
}

struct FolderEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Folder" }
    static var defaultQuery = FolderEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct FolderEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [FolderEntity] {
        allFolders().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FolderEntity] {
        allFolders()
    }

    private func allFolders() -> [FolderEntity] {
        (WidgetShared.loadSnapshot()?.folders ?? []).map {
            FolderEntity(id: $0.id, name: $0.name)
        }
    }
}
