import UIKit
import PDFKit

@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let thumbnailSize = CGSize(width: 300, height: 400)

    private var cacheDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("ScoreThumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func thumbnail(for score: Score) async -> UIImage? {
        let key = score.id.uuidString as NSString

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Disk cache
        let diskPath = cacheDirectory.appendingPathComponent("\(score.id.uuidString).jpg")
        if let diskData = try? Data(contentsOf: diskPath),
           let diskImage = UIImage(data: diskData) {
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }

        // 3. Generate from PDF
        guard let image = await generateThumbnail(from: score.pdfData) else {
            return nil
        }

        // Store in memory
        memoryCache.setObject(image, forKey: key)

        // Store on disk (background)
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            try? jpegData.write(to: diskPath, options: .atomic)
        }

        return image
    }

    func invalidate(for scoreId: UUID) {
        let key = scoreId.uuidString as NSString
        memoryCache.removeObject(forKey: key)
        let diskPath = cacheDirectory.appendingPathComponent("\(scoreId.uuidString).jpg")
        try? fileManager.removeItem(at: diskPath)
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
    }

    private func generateThumbnail(from pdfData: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [thumbnailSize] in
                guard let document = PDFDocument(data: pdfData),
                      let page = document.page(at: 0) else {
                    continuation.resume(returning: nil)
                    return
                }

                let pageRect = page.bounds(for: .mediaBox)
                let scale = min(
                    thumbnailSize.width / pageRect.width,
                    thumbnailSize.height / pageRect.height
                )
                let scaledSize = CGSize(
                    width: pageRect.width * scale,
                    height: pageRect.height * scale
                )

                let renderer = UIGraphicsImageRenderer(size: scaledSize)
                let image = renderer.image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: scaledSize))

                    context.cgContext.translateBy(x: 0, y: scaledSize.height)
                    context.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: context.cgContext)
                }

                continuation.resume(returning: image)
            }
        }
    }
}
