import Foundation

enum TripMediaType: String, Codable, Equatable, Sendable {
    case image
}

struct TripMedia: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var filename: String?
    var remoteURL: URL?
    var sourceURL: URL?
    var sourceName: String?
    var attribution: String?
    var caption: String?
    var isCover: Bool
    var mediaType: TripMediaType
    var googlePlaceID: String?

    init(id: UUID = UUID(), filename: String? = nil, remoteURL: URL? = nil,
         sourceURL: URL? = nil, sourceName: String? = nil, attribution: String? = nil,
         caption: String? = nil, isCover: Bool = false, mediaType: TripMediaType = .image,
         googlePlaceID: String? = nil) {
        self.id = id; self.filename = filename; self.remoteURL = remoteURL
        self.sourceURL = sourceURL; self.sourceName = sourceName; self.attribution = attribution
        self.caption = caption; self.isCover = isCover; self.mediaType = mediaType
        self.googlePlaceID = googlePlaceID
    }
}

protocol TripMediaContaining {
    var media: [TripMedia]? { get set }
    var presentationMedia: TripMedia? { get set }
}

extension Flight: TripMediaContaining {}
extension Accommodation: TripMediaContaining {}
extension Activity: TripMediaContaining {}

extension TripMediaContaining {
    var mediaItems: [TripMedia] { media ?? [] }
    var coverMedia: TripMedia? { presentationMedia }
}

extension Trip {
    var allMedia: [TripMedia] {
        flights.flatMap(\.mediaItems) + accommodations.flatMap(\.mediaItems) + activities.flatMap(\.mediaItems)
            + flights.compactMap(\.presentationMedia)
            + accommodations.compactMap(\.presentationMedia)
            + activities.compactMap(\.presentationMedia)
    }
}
