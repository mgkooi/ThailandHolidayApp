import ImageIO
import OSLog
import Vision

struct BookingOCRService {
    private static let logger = Logger(subsystem: "nl.martijnkooi.ThailandHolidayApp", category: "BookingOCR")

    func recognize(imageData: Data) async throws -> RecognizedBookingText {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BookingOCRError.invalidImage
        }
        let text: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap {
                    $0.topCandidates(1).first?.string
                } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "nl-NL"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
        Self.logger.info("OCR succeeded")
        return RecognizedBookingText(originalText: text)
    }
}

enum BookingOCRError: Error { case invalidImage }
