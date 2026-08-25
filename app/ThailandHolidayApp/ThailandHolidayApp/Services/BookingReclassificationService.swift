import Foundation

struct BookingReclassificationService {
    let extractor: DeterministicBookingExtractor

    init(extractor: DeterministicBookingExtractor = DeterministicBookingExtractor()) {
        self.extractor = extractor
    }

    func reparse(_ current: BookingExtractionResult, as type: BookingDetectedType, trip: Trip) -> BookingExtractionResult {
        extractor.extract(
            text: RecognizedBookingText(originalText: current.originalRecognizedText),
            trip: trip,
            forcedType: type
        )
    }
}

