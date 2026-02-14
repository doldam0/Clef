import SwiftUI
import PDFKit

struct ThumbnailSidebarView: View {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    var onPageSelected: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        ThumbnailCell(
                            document: document,
                            pageIndex: index,
                            isSelected: index == currentPageIndex
                        )
                        .id(index)
                        .onTapGesture {
                            currentPageIndex = index
                            onPageSelected?()
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
            .onChange(of: currentPageIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct ThumbnailCell: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.tint, lineWidth: 3)
                }
            }

            Text("\(pageIndex + 1)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .task(id: pageIndex) {
            await generateThumbnail()
        }
    }

    private var aspectRatio: CGFloat {
        guard let page = document.page(at: pageIndex) else { return 0.75 }
        let size = page.bounds(for: .mediaBox).size
        return size.width / (size.height + 20)
    }

    private func generateThumbnail() async {
        guard thumbnail == nil,
              let page = document.page(at: pageIndex)
        else { return }

        let size = page.bounds(for: .mediaBox).size
        let ratio = size.width / size.height
        let thumbWidth: CGFloat = 160
        let thumbHeight = thumbWidth / ratio

        let image = page.thumbnail(
            of: CGSize(width: thumbWidth, height: thumbHeight),
            for: .mediaBox
        )

        if !Task.isCancelled {
            thumbnail = image
        }
    }
}
