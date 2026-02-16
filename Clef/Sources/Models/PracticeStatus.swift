import Foundation

enum PracticeStatus: Int, Codable, CaseIterable, Identifiable {
    case notStarted = 0
    case inProgress = 1
    case mastered = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .notStarted: String(localized: "Not Started")
        case .inProgress: String(localized: "In Progress")
        case .mastered: String(localized: "Mastered")
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .mastered: "checkmark.circle.fill"
        }
    }
}
