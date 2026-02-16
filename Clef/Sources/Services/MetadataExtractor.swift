import Foundation
import CoreGraphics
import PDFKit
@preconcurrency import Vision
import NaturalLanguage

struct ExtractedMetadata: Sendable {
    var title: String?
    var composer: String?
    var instrument: String?
    var key: String?
    var timeSignature: String?
}

actor MetadataExtractor {
    static let shared = MetadataExtractor()

    func extract(from pdfData: Data) async -> ExtractedMetadata {
        var metadata = ExtractedMetadata()

        let (pdfTitle, pdfAuthor, cgImage) = await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: pdfData) else {
                return (nil as String?, nil as String?, nil as CGImage?)
            }

            let attrs = document.documentAttributes ?? [:]
            let title = attrs[PDFDocumentAttribute.titleAttribute] as? String
            let author = attrs[PDFDocumentAttribute.authorAttribute] as? String

            guard let page = document.page(at: 0) else {
                return (title, author, nil as CGImage?)
            }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = (pageRect.width * pageRect.height) > 1_000_000 ? 1.5 : 2.0
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)

            guard width > 0, height > 0,
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return (title, author, nil as CGImage?)
            }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            return (title, author, context.makeImage())
        }.value

        metadata.title = normalized(pdfTitle)
        metadata.composer = normalized(pdfAuthor)

        if let cgImage, let ocrResults = await performOCR(on: cgImage) {
            if metadata.title == nil {
                metadata.title = findTitle(from: ocrResults)
            }
            if metadata.composer == nil {
                metadata.composer = findComposer(from: ocrResults)
            }
            if metadata.key == nil {
                metadata.key = findKey(from: ocrResults)
            }
            if metadata.timeSignature == nil {
                metadata.timeSignature = findTimeSignature(from: ocrResults)
            }
        }

        return metadata
    }

    private func performOCR(on cgImage: CGImage) async -> [OCRResult]? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let results: [OCRResult] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return OCRResult(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                }

                continuation.resume(returning: results)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func findTitle(from results: [OCRResult]) -> String? {
        let candidates = results.filter {
            $0.boundingBox.midY > 0.66
            && (0.2 ... 0.8).contains($0.boundingBox.midX)
            && $0.confidence > 0.25
        }

        let best = candidates
            .filter { !$0.text.contains("/") }
            .max { lhs, rhs in
                titleScore(lhs) < titleScore(rhs)
            }

        return normalized(best?.text)
    }

    private func findComposer(from results: [OCRResult]) -> String? {
        let topRightCandidates = results.filter {
            $0.boundingBox.midX > 0.5
            && $0.boundingBox.midY > 0.5
            && $0.confidence > 0.2
        }

        if let bestName = topRightCandidates
            .filter({ isLikelyPersonalName($0.text) })
            .max(by: { composerScore($0) < composerScore($1) }) {
            return normalized(extractName(from: bestName.text) ?? bestName.text)
        }

        let composerKeywordPatterns = [
            "(?i)(composer|composed\\s*by|작곡|편곡)\\s*[:：-]?\\s*([\\p{L} .'-]{2,})"
        ]

        for result in topRightCandidates.sorted(by: { composerScore($0) > composerScore($1) }) {
            if let match = firstRegexMatch(in: result.text, patterns: composerKeywordPatterns) {
                return normalized(extractName(from: match) ?? match)
            }
        }

        return nil
    }

    private func findKey(from results: [OCRResult]) -> String? {
        let patterns = [
            "\\b([A-G](?:#|b|♯|♭)?)\\s*(Major|major|Minor|minor)\\b",
            "\\b([A-G](?:#|b|♯|♭)?)\\s*(장조|단조)\\b"
        ]

        for result in results.sorted(by: { $0.confidence > $1.confidence }) {
            if let match = firstRegexMatch(in: result.text, patterns: patterns) {
                return normalized(match)
            }
        }

        return nil
    }

    private func findTimeSignature(from results: [OCRResult]) -> String? {
        let patterns = [
            "\\b(2|3|4|5|6|7|9|12)\\s*/\\s*(2|4|8|16)\\b"
        ]

        for result in results.sorted(by: { $0.confidence > $1.confidence }) {
            if let match = firstRegexMatch(in: result.text, patterns: patterns) {
                let normalizedMatch = match.replacingOccurrences(of: " ", with: "")
                return normalized(normalizedMatch)
            }
        }

        return nil
    }

    private func titleScore(_ result: OCRResult) -> CGFloat {
        let area = result.boundingBox.width * result.boundingBox.height
        return area + (result.boundingBox.height * 0.5) + (CGFloat(result.confidence) * 0.2)
    }

    private func composerScore(_ result: OCRResult) -> CGFloat {
        (result.boundingBox.midX * 0.6) + (result.boundingBox.midY * 0.3) + (CGFloat(result.confidence) * 0.1)
    }

    private func isLikelyPersonalName(_ text: String) -> Bool {
        let candidate = normalized(extractName(from: text) ?? text) ?? text
        guard !candidate.isEmpty else { return false }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = candidate

        var foundPersonalName = false
        tagger.enumerateTags(
            in: candidate.startIndex ..< candidate.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, _ in
            if tag == .personalName {
                foundPersonalName = true
                return false
            }
            return true
        }

        if foundPersonalName {
            return true
        }

        let koreanNamePattern = "^[가-힣]{2,4}$"
        return candidate.range(of: koreanNamePattern, options: .regularExpression) != nil
    }

    private func extractName(from text: String) -> String? {
        let separators = [":", "：", "-"]
        let normalizedText = text.replacingOccurrences(of: "작곡", with: "")
            .replacingOccurrences(of: "편곡", with: "")
            .replacingOccurrences(of: "composer", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "composed by", with: "", options: .caseInsensitive)

        for separator in separators {
            if let range = normalizedText.range(of: separator) {
                return String(normalizedText[range.upperBound...])
            }
        }

        return normalizedText
    }

    private func firstRegexMatch(in text: String, patterns: [String]) -> String? {
        let fullRange = NSRange(text.startIndex..., in: text)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else { continue }
            guard let range = Range(match.range, in: text) else { continue }
            return String(text[range])
        }

        return nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct OCRResult {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}


