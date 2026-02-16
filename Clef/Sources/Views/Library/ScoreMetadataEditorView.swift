import SwiftUI
import SwiftData

struct ScoreMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var score: Score
    let existingTags: [String]

    @State private var newTagText = ""
    @FocusState private var isTagFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("제목", text: $score.title)
                    TextField("작곡가", text: optionalBinding($score.composer))
                    TextField("악기", text: optionalBinding($score.instrument))
                }

                Section("음악 정보") {
                    TextField("조성 (예: C Major)", text: optionalBinding($score.key))
                    TextField("박자 (예: 4/4)", text: optionalBinding($score.timeSignature))
                }

                Section("태그") {
                    tagChipsView

                    HStack {
                        TextField("태그 추가", text: $newTagText)
                            .focused($isTagFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { addTag() }

                        if !newTagText.isEmpty {
                            Button(action: addTag) {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    }

                    if !tagSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tagSuggestions, id: \.self) { tag in
                                    Button {
                                        appendTag(tag)
                                    } label: {
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.fill.tertiary, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("악보 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        score.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagChipsView: some View {
        if !score.tags.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(score.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.subheadline)
                        Button {
                            score.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private var tagSuggestions: [String] {
        guard !newTagText.isEmpty else { return [] }
        let query = newTagText.lowercased()
        return existingTags
            .filter { $0.lowercased().contains(query) && !score.tags.contains($0) }
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !score.tags.contains(trimmed) else {
            newTagText = ""
            return
        }
        appendTag(trimmed)
    }

    private func appendTag(_ tag: String) {
        score.tags.append(tag)
        newTagText = ""
        isTagFieldFocused = true
    }

    private func optionalBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding<String>(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
