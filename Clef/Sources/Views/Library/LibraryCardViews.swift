import SwiftUI
import SwiftData

// MARK: - Folder Card

struct FolderCardView: View {
    let folder: Folder
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.opacity(0.1))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.tint)
                            Text("\(folder.totalScoreCount)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(folder.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Card

struct ProgramCardView: View {
    let program: Program
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.orange.opacity(0.1))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note.list")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)
                            Text("\(program.items.count)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(program.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Item Card (dashed placeholder)

struct NewItemCardView: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(.tertiary)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(" ")
                    .font(.headline)
            }
        }
        .buttonStyle(.plain)
    }
}
