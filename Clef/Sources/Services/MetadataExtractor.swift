import Foundation
import CoreGraphics
import PDFKit
@preconcurrency import Vision
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ExtractedMetadata: Sendable {
    var title: String?
    var composer: String?
    var instruments: [String] = []
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct LLMScoreMetadata {
    @Guide(description: "The title of the sheet music piece. Extract the full title as written.")
    var title: String?
    @Guide(description: "The full name of the composer as written on the score.")
    var composer: String?
    @Guide(description: "Instrument names translated to standard English. Only from Medium or Large text. Empty array if none visible.")
    var instruments: [String]
}
#endif

actor MetadataExtractor {
    static let shared = MetadataExtractor()

    // MARK: - Main extraction

    func extract(from pdfData: Data) async -> ExtractedMetadata {
        // Step 1: Parse PDF once — attributes + first page render
        let (pdfTitle, pdfAuthor, pdfSubject, pdfCreator, cgImage) = await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: pdfData) else {
                return (nil as String?, nil as String?, nil as String?, nil as String?, nil as CGImage?)
            }

            let attrs = document.documentAttributes ?? [:]
            let title = attrs[PDFDocumentAttribute.titleAttribute] as? String
            let author = attrs[PDFDocumentAttribute.authorAttribute] as? String
            let subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String
            let creator = attrs[PDFDocumentAttribute.creatorAttribute] as? String

            guard let page = document.page(at: 0) else {
                return (title, author, subject, creator, nil as CGImage?)
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
                return (title, author, subject, creator, nil as CGImage?)
            }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            return (title, author, subject, creator, context.makeImage())
        }.value

        // Step 2: OCR on first page
        var ocrResults: [OCRResult]?
        if let cgImage {
            ocrResults = await performOCR(on: cgImage)
        }

        // Step 3: Try Foundation Models LLM (iPadOS 26+)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let ocrResults {
            if let result = await extractWithLLM(
                ocrResults: ocrResults,
                pdfTitle: pdfTitle,
                pdfAuthor: pdfAuthor,
                pdfSubject: pdfSubject,
                pdfCreator: pdfCreator
            ) {
                return result
            }
        }
        #endif

        // Step 4: Fallback — regex-based extraction
        return extractWithRegex(
            ocrResults: ocrResults,
            pdfTitle: pdfTitle,
            pdfAuthor: pdfAuthor
        )
    }

    // MARK: - OCR

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

    // MARK: - LLM-based extraction (iPadOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func extractWithLLM(
        ocrResults: [OCRResult],
        pdfTitle: String?,
        pdfAuthor: String?,
        pdfSubject: String?,
        pdfCreator: String?
    ) async -> ExtractedMetadata? {
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let ocrText = formatOCRForLLM(ocrResults)
        let pdfMetadata = formatPDFMetadata(
            title: pdfTitle,
            author: pdfAuthor,
            subject: pdfSubject,
            creator: pdfCreator
        )

        let prompt = """
        PDF File Metadata:
        \(pdfMetadata)

        OCR Text from first page:
        \(ocrText)
        """

        do {
            let session = LanguageModelSession {
                """
                You are a sheet music metadata extractor. Each OCR line has [position, size] tags.

                Extract:
                - title: The piece name (usually Large text near top center)
                - composer: The composer's full name (usually Medium or Large text near top right)
                - instruments: Only from Medium or Large text. Ignore Small text (cue labels). Translate any non-English names to standard English. Most parts have 1-4 instruments.

                Do NOT guess or infer. Only extract what is literally visible. When in doubt, leave empty.
                """
            }
            let response = try await session.respond(to: prompt, generating: LLMScoreMetadata.self)
            let content = response.content
            return ExtractedMetadata(
                title: normalized(content.title),
                composer: normalized(content.composer),
                instruments: content.instruments
            )
        } catch {
            return nil
        }
    }
    #endif

    private func formatOCRForLLM(_ results: [OCRResult]) -> String {
        let sorted = results.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let heights = sorted.map { $0.boundingBox.height }
        let medianHeight = heights.isEmpty ? 0 : heights.sorted()[heights.count / 2]

        return sorted
            .prefix(50)
            .map { result in
                let vPos = result.boundingBox.midY > 0.66 ? "Top"
                    : result.boundingBox.midY > 0.33 ? "Middle" : "Bottom"
                let hPos = result.boundingBox.midX < 0.33 ? "Left"
                    : result.boundingBox.midX < 0.66 ? "Center" : "Right"
                let size: String
                if medianHeight > 0 {
                    let ratio = result.boundingBox.height / medianHeight
                    size = ratio > 1.4 ? "Large" : ratio < 0.7 ? "Small" : "Medium"
                } else {
                    size = "Medium"
                }
                return "[\(vPos), \(hPos), \(size)] \"\(result.text)\""
            }
            .joined(separator: "\n")
    }

    private func formatPDFMetadata(
        title: String?,
        author: String?,
        subject: String?,
        creator: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Title: \(title ?? "not available")")
        lines.append("Author: \(author ?? "not available")")
        if let subject, !subject.isEmpty { lines.append("Subject: \(subject)") }
        if let creator, !creator.isEmpty { lines.append("Creator App: \(creator)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Regex-based extraction (fallback)

    private func extractWithRegex(
        ocrResults: [OCRResult]?,
        pdfTitle: String?,
        pdfAuthor: String?
    ) -> ExtractedMetadata {
        var metadata = ExtractedMetadata()
        metadata.title = normalized(pdfTitle)
        metadata.composer = normalized(pdfAuthor)

        if let ocrResults {
            if metadata.title == nil {
                metadata.title = findTitle(from: ocrResults)
            }
            if metadata.composer == nil {
                metadata.composer = findComposer(from: ocrResults)
            }
        }

        return metadata
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


