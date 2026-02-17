import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Score.updatedAt, order: .reverse) private var scores: [Score]
    @State private var isImporting = false
    @State private var selectedTab: LibraryTab = .recent
    @State private var searchText = ""
    @State private var recentPath = NavigationPath()
    @State private var browsePath = NavigationPath()

    private var allTags: [String] {
        Array(Set(scores.flatMap(\.tags))).sorted()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Recent", systemImage: "clock", value: .recent) {
                NavigationStack(path: $recentPath) {
                    ScoreLibraryView(
                        tab: .recent,
                        searchText: $searchText,
                        onImport: { isImporting = true },
                        onScoreTapped: { score in
                            recentPath.append(ScoreNavigation.reader(score.id))
                        },
                        onProgramTapped: { program in
                            recentPath.append(ProgramNavigation.detail(program.id))
                        },
                        onFolderTapped: { folder in
                            recentPath.append(FolderNavigation.detail(folder.id))
                        }
                    )
                    .navigationDestination(for: ScoreNavigation.self) { nav in
                        switch nav {
                        case .reader(let scoreId):
                            if let score = scores.first(where: { $0.id == scoreId }) {
                                ScoreReaderView(score: score, allTags: allTags)
                            }
                        }
                    }
                    .navigationDestination(for: FolderNavigation.self) { nav in
                        switch nav {
                        case .detail(let folderId):
                            FolderDestinationView(
                                folderId: folderId,
                                onScoreTapped: { score in
                                    recentPath.append(ScoreNavigation.reader(score.id))
                                },
                                onProgramTapped: { program in
                                    recentPath.append(ProgramNavigation.detail(program.id))
                                },
                                onFolderTapped: { folder in
                                    recentPath.append(FolderNavigation.detail(folder.id))
                                }
                            )
                        }
                    }
                    .navigationDestination(for: ProgramNavigation.self) { nav in
                        switch nav {
                        case .detail(let programId):
                            ProgramDestinationView(
                                programId: programId,
                                allTags: allTags,
                                onScoreTapped: { score in
                                    recentPath.append(ScoreNavigation.reader(score.id))
                                },
                                onPlayProgram: { program in
                                    recentPath.append(ProgramNavigation.play(program.id))
                                }
                            )
                        case .play(let programId):
                            ProgramPlayerDestinationView(
                                programId: programId,
                                allTags: allTags
                            )
                        }
                    }
                }
            }
            Tab("Browse", systemImage: "folder", value: .browse) {
                NavigationStack(path: $browsePath) {
                    ScoreLibraryView(
                        tab: .browse,
                        searchText: $searchText,
                        onImport: { isImporting = true },
                        onScoreTapped: { score in
                            browsePath.append(ScoreNavigation.reader(score.id))
                        },
                        onProgramTapped: { program in
                            browsePath.append(ProgramNavigation.detail(program.id))
                        },
                        onFolderTapped: { folder in
                            browsePath.append(FolderNavigation.detail(folder.id))
                        }
                    )
                    .navigationDestination(for: ScoreNavigation.self) { nav in
                        switch nav {
                        case .reader(let scoreId):
                            if let score = scores.first(where: { $0.id == scoreId }) {
                                ScoreReaderView(score: score, allTags: allTags)
                            }
                        }
                    }
                    .navigationDestination(for: FolderNavigation.self) { nav in
                        switch nav {
                        case .detail(let folderId):
                            FolderDestinationView(
                                folderId: folderId,
                                onScoreTapped: { score in
                                    browsePath.append(ScoreNavigation.reader(score.id))
                                },
                                onProgramTapped: { program in
                                    browsePath.append(ProgramNavigation.detail(program.id))
                                },
                                onFolderTapped: { folder in
                                    browsePath.append(FolderNavigation.detail(folder.id))
                                }
                            )
                        }
                    }
                    .navigationDestination(for: ProgramNavigation.self) { nav in
                        switch nav {
                        case .detail(let programId):
                            ProgramDestinationView(
                                programId: programId,
                                allTags: allTags,
                                onScoreTapped: { score in
                                    browsePath.append(ScoreNavigation.reader(score.id))
                                },
                                onPlayProgram: { program in
                                    browsePath.append(ProgramNavigation.play(program.id))
                                }
                            )
                        case .play(let programId):
                            ProgramPlayerDestinationView(
                                programId: programId,
                                allTags: allTags
                            )
                        }
                    }
                }
            }
        }
        .scoreImporter(isPresented: $isImporting)
    }
}

// MARK: - Navigation Types

enum ScoreNavigation: Hashable {
    case reader(UUID)
}

enum FolderNavigation: Hashable {
    case detail(UUID)
}

enum ProgramNavigation: Hashable {
    case detail(UUID)
    case play(UUID)
}

// MARK: - Program Destination Wrappers

private struct ProgramDestinationView: View {
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    let programId: UUID
    let allTags: [String]
    let onScoreTapped: (Score) -> Void
    let onPlayProgram: (Program) -> Void

    var body: some View {
        if let program = programs.first(where: { $0.id == programId }) {
            ProgramDetailView(
                program: program,
                onScoreTapped: onScoreTapped,
                onPlayProgram: onPlayProgram
            )
        } else {
            ContentUnavailableView(
                "Program Not Found",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

private struct FolderDestinationView: View {
    @Query(sort: \Folder.name) private var folders: [Folder]
    let folderId: UUID
    let onScoreTapped: (Score) -> Void
    let onProgramTapped: (Program) -> Void
    let onFolderTapped: (Folder) -> Void
    @State private var isSelecting = false
    @State private var selectedScoreIds: Set<UUID> = []
    @State private var isImporting = false
    @State private var isCreatingFolder = false
    @State private var isCreatingProgram = false

    var body: some View {
        if let folder = folders.first(where: { $0.id == folderId }) {
            BrowseCatalogView(
                folder: folder,
                onScoreTapped: onScoreTapped,
                onProgramTapped: onProgramTapped,
                onFolderTapped: onFolderTapped,
                isSelecting: $isSelecting,
                selectedScoreIds: $selectedScoreIds,
                isImporting: $isImporting,
                isCreatingFolder: $isCreatingFolder,
                isCreatingProgram: $isCreatingProgram
            )
            .navigationTitle(folder.name)
        } else {
            ContentUnavailableView(
                "Folder Not Found",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

private struct ProgramPlayerDestinationView: View {
    @Query(sort: \Program.updatedAt, order: .reverse) private var programs: [Program]
    let programId: UUID
    let allTags: [String]

    var body: some View {
        if let program = programs.first(where: { $0.id == programId }) {
            ProgramPlayerView(program: program, allTags: allTags)
        } else {
            ContentUnavailableView(
                "Program Not Found",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}
