import SwiftUI
import SwiftData

struct MetadataConfirmationView: View {
    let score: Score
    let extracted: ExtractedMetadata

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var composer: String = ""
    @State private var instrument: String = ""
    @State private var key: String = ""
    @State private var timeSignature: String = ""
    @State private var didPrefill = false

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

                Section(String(localized: "Instrument")) {
                    TextField(String(localized: "Instrument"), text: $instrument)
                    autoDetectedLabel(show: extracted.instrument)
                }

                Section(String(localized: "Key")) {
                    TextField(String(localized: "Key"), text: $key)
                    autoDetectedLabel(show: extracted.key)
                }

                Section(String(localized: "Time Signature")) {
                    TextField(String(localized: "Time Signature"), text: $timeSignature)
                    autoDetectedLabel(show: extracted.timeSignature)
                }
            }
            .navigationTitle(String(localized: "Detected Metadata"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply")) {
                        applyChanges()
                    }
                }
            }
        }
        .onAppear {
            prefillIfNeeded()
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

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true

        title = extracted.title ?? score.title
        composer = extracted.composer ?? score.composer ?? ""
        instrument = extracted.instrument ?? score.instrument ?? ""
        key = extracted.key ?? score.key ?? ""
        timeSignature = extracted.timeSignature ?? score.timeSignature ?? ""
    }

    private func applyChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        score.title = trimmedTitle.isEmpty ? score.title : trimmedTitle

        score.composer = normalizedOptional(composer)
        score.instrument = normalizedOptional(instrument)
        score.key = normalizedOptional(key)
        score.timeSignature = normalizedOptional(timeSignature)
        score.updatedAt = .now

        try? modelContext.save()
        dismiss()
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
