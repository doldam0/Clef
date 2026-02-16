import SwiftUI
import SwiftData

struct MetadataConfirmationView: View {
    let score: Score
    let extracted: ExtractedMetadata
    var currentIndex: Int = 0
    var totalCount: Int = 1
    var onComplete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var composer: String = ""
    @State private var instruments: [String] = []
    @State private var newInstrumentText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Title")) {
                    TextField(String(localized: "Title"), text: $title)
                    autoDetectedLabel(show: extracted.title)
                }

                Section(String(localized: "Composer")) {
                    TextField(String(localized: "Composer"), text: $composer)
                    autoDetectedLabel(show: extracted.composer)
                }

                Section(String(localized: "Instruments")) {
                    if !instruments.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(instruments, id: \.self) { name in
                                HStack(spacing: 4) {
                                    Text(name)
                                        .font(.subheadline)
                                    Button {
                                        instruments.removeAll { $0 == name }
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

                    HStack {
                        TextField(String(localized: "Add Instrument"), text: $newInstrumentText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onSubmit { addInstrument() }

                        if !newInstrumentText.isEmpty {
                            Button(action: addInstrument) {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    }

                    if !extracted.instruments.isEmpty {
                        autoDetectedLabel(show: extracted.instruments.joined(separator: ", "))
                    }
                }

            }
            .navigationTitle(totalCount > 1
                ? "\(String(localized: "Score Info")) (\(currentIndex + 1)/\(totalCount))"
                : String(localized: "Score Info")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip")) {
                        onComplete?()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply")) {
                        applyChanges()
                        onComplete?()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            prefill()
        }
    }

    @ViewBuilder
    private func autoDetectedLabel(show value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(String(localized: "Auto-detected"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func prefill() {
        title = extracted.title ?? score.title
        composer = extracted.composer ?? score.composer ?? ""
        instruments = extracted.instruments.isEmpty ? score.instruments : extracted.instruments
        newInstrumentText = ""
    }

    private func addInstrument() {
        let trimmed = newInstrumentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !instruments.contains(trimmed) else {
            newInstrumentText = ""
            return
        }
        instruments.append(trimmed)
        newInstrumentText = ""
    }

    private func applyChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        score.title = trimmedTitle.isEmpty ? score.title : trimmedTitle

        score.composer = normalizedOptional(composer)
        score.instruments = instruments
        score.updatedAt = .now

        try? modelContext.save()
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
