import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var program: Program
    var onScoreTapped: (Score) -> Void
    var onPlayProgram: (Program) -> Void

    @State private var showScorePicker = false
    @State private var isSelecting = false
    @State private var selectedItemIds: Set<UUID> = []
    @State private var showDeleteSelectedAlert = false
    @State private var showRemoveSelectedAlert = false

    var body: some View {
        Group {
            if program.orderedItems.isEmpty {
                emptyView
            } else {
                scoreList
            }
        }
        .navigationTitle(program.name)
        .toolbar(content: programToolbar)
        .alert("Remove from Program", isPresented: $showRemoveSelectedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { removeSelectedItems() }
        } message: {
            Text("Remove \(selectedItemIds.count) scores from this program?")
        }
        .alert("Delete Selected", isPresented: $showDeleteSelectedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteSelectedItems() }
        } message: {
            Text("Delete \(selectedItemIds.count) scores permanently? This cannot be undone.")
        }
        .sheet(isPresented: $showScorePicker) {
            ScorePickerView(program: program)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Scores", systemImage: "music.note.list")
        } description: {
            Text("Add scores to this program")
        } actions: {
            Button("Add Scores") {
                showScorePicker = true
            }
        }
    }

    private var scoreList: some View {
        List {
            if isSelecting {
                ForEach(program.orderedItems) { item in
                    programRow(for: item)
                }
            } else {
                ForEach(program.orderedItems) { item in
                    programRow(for: item)
                }
                .onMove(perform: moveItems)
                .onDelete(perform: deleteItems)
            }
        }
    }

    @ViewBuilder
    private func programRow(for item: ProgramItem) -> some View {
        if let score = item.score {
            Button {
                if isSelecting {
                    toggleSelection(item)
                } else {
                    onScoreTapped(score)
                }
            } label: {
                HStack(spacing: 12) {
                    if isSelecting {
                        selectionIndicator(for: item)
                    }
                    ProgramScoreRow(item: item)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func selectionIndicator(for item: ProgramItem) -> some View {
        let selected = selectedItemIds.contains(item.id)
        return Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private var allItemsSelected: Bool {
        let items = program.orderedItems
        return !items.isEmpty && selectedItemIds.count == items.count
    }

    @ToolbarContentBuilder
    private func programToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button(allItemsSelected ? "Deselect All" : "Select All") {
                    withAnimation {
                        if allItemsSelected {
                            selectedItemIds.removeAll()
                        } else {
                            selectedItemIds = Set(program.orderedItems.map(\.id))
                        }
                    }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button {
                    showRemoveSelectedAlert = true
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .disabled(selectedItemIds.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button(role: .destructive) {
                    showDeleteSelectedAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedItemIds.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button {
                    withAnimation {
                        isSelecting = false
                        selectedItemIds.removeAll()
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                }
            } else if !program.items.isEmpty {
                Button {
                    withAnimation { isSelecting = true }
                } label: {
                    Text("Select")
                }
            }
        }
        if !isSelecting {
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !isSelecting {
                Button {
                    showScorePicker = true
                } label: {
                    Label("Add Scores", systemImage: "plus")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !isSelecting {
                Button {
                    onPlayProgram(program)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
    }

    private func toggleSelection(_ item: ProgramItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
    }

    private func removeSelectedItems() {
        for item in program.orderedItems where selectedItemIds.contains(item.id) {
            if let score = item.score {
                program.removeScore(score)
            }
        }
        try? modelContext.save()
        selectedItemIds.removeAll()
    }

    private func deleteSelectedItems() {
        for item in program.orderedItems where selectedItemIds.contains(item.id) {
            if let score = item.score {
                program.removeScore(score)
                modelContext.delete(score)
            }
        }
        try? modelContext.save()
        selectedItemIds.removeAll()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        program.moveItems(from: source, to: destination)
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { program.orderedItems[$0] }
        for item in itemsToDelete {
            if let score = item.score {
                program.removeScore(score)
            }
        }
        try? modelContext.save()
    }
}

private struct ProgramScoreRow: View {
    let item: ProgramItem

    var body: some View {
        HStack(spacing: 12) {
            Text("\(item.position + 1).")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            if let score = item.score {
                ScoreThumbnailView(score: score)

                VStack(alignment: .leading, spacing: 4) {
                    Text(score.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(score.composer ?? String(localized: "Unknown Composer"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !score.instruments.isEmpty {
                        Text(score.instruments.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.2))
                    .frame(width: 44, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Missing Score")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("This score is unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct ScoreThumbnailView: View {
    let score: Score

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 44, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: score.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: score)
        }
    }
}


