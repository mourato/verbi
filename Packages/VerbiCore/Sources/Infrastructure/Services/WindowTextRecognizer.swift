import CoreGraphics
import Foundation
import VerbiCoreCommon
import Vision

@MainActor
final class WindowTextRecognizer {
    static let shared = WindowTextRecognizer()

    private let recognizeText: @Sendable (CGImage) -> String?
    private var isRecognizing = false

    init(recognizeText: @escaping @Sendable (CGImage) -> String? = WindowTextRecognizer.recognizedText) {
        self.recognizeText = recognizeText
    }

    func recognize(_ image: CGImage) async -> String? {
        guard !Task.isCancelled, !isRecognizing else { return nil }
        isRecognizing = true
        defer { isRecognizing = false }

        let recognizeText = recognizeText
        let text = await Task.detached(priority: .utility) {
            recognizeText(image)
        }.value
        return Task.isCancelled ? nil : text
    }

    private nonisolated static func recognizedText(from image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            AppLogger.warning(
                "OCR recognition request failed",
                category: .recordingManager,
                extra: [
                    "reasonCode": "ocr.vision_request_failed",
                    "error": error.localizedDescription
                ]
            )
            return nil
        }

        let observations = request.results ?? []
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        if text.count <= 4000 {
            return text
        }

        let maxEndIndex = text.index(text.startIndex, offsetBy: 4000)
        return String(text[..<maxEndIndex])
    }
}
