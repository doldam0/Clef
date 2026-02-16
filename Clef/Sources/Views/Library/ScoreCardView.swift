import SwiftUI
import UIKit

struct ScoreCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let score: Score
    var isSelecting: Bool = false
    var isSelected: Bool = false
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnailArea
            metadataArea
        }
        .task(id: score.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: score)
        }
    }

    private var thumbnailArea: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(
                    color: colorScheme == .dark
                        ? .white.opacity(0.06)
                        : .black.opacity(0.15),
                    radius: 4, y: 2
                )

            if score.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.red, in: Circle())
                    .padding(6)
            }

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
            }
        }
    }

    private var metadataArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(score.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let composer = score.composer, !composer.isEmpty {
                Text(composer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !score.instruments.isEmpty {
                Text(score.instruments.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 52, alignment: .top)
    }
}
