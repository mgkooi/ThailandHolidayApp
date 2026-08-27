import Foundation

enum TripMediaType: String, Codable, Equatable, Sendable {
    case image
}

enum TripMediaPresentationStyle: String, Codable, Equatable, Sendable, CaseIterable {
    case photo
    case logo
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
    var presentationStyle: TripMediaPresentationStyle?

    init(id: UUID = UUID(), filename: String? = nil, remoteURL: URL? = nil,
         sourceURL: URL? = nil, sourceName: String? = nil, attribution: String? = nil,
         caption: String? = nil, isCover: Bool = false, mediaType: TripMediaType = .image,
         googlePlaceID: String? = nil, presentationStyle: TripMediaPresentationStyle? = nil) {
        self.id = id; self.filename = filename; self.remoteURL = remoteURL
        self.sourceURL = sourceURL; self.sourceName = sourceName; self.attribution = attribution
        self.caption = caption; self.isCover = isCover; self.mediaType = mediaType
        self.googlePlaceID = googlePlaceID
        self.presentationStyle = presentationStyle
    }
}

protocol TripMediaContaining {
    var media: [TripMedia]? { get set }
    var presentationMedia: TripMedia? { get set }
}

extension Flight: TripMediaContaining {}
extension Accommodation: TripMediaContaining {}
extension Activity: TripMediaContaining {}
extension Transfer: TripMediaContaining {}
extension Ferry: TripMediaContaining {}
extension TrainTrip: TripMediaContaining {}
extension RestaurantReservation: TripMediaContaining {}
extension RentalVehicleBooking: TripMediaContaining {}
extension TripEvent: TripMediaContaining {}

extension TripMediaContaining {
    var mediaItems: [TripMedia] { media ?? [] }
    var coverMedia: TripMedia? { presentationMedia }
}

extension Trip {
    var allMedia: [TripMedia] {
        var result = flights.flatMap(\.mediaItems)
        result += accommodations.flatMap(\.mediaItems)
        result += activities.flatMap(\.mediaItems)
        result += transfers.flatMap(\.mediaItems)
        result += ferries.flatMap(\.mediaItems)
        result += trains.flatMap(\.mediaItems)
        result += restaurants.flatMap(\.mediaItems)
        result += rentalVehicles.flatMap(\.mediaItems)
        result += otherItems.flatMap(\.mediaItems)
        result += flights.compactMap(\.presentationMedia)
        result += accommodations.compactMap(\.presentationMedia)
        result += activities.compactMap(\.presentationMedia)
        result += transfers.compactMap(\.presentationMedia)
        result += ferries.compactMap(\.presentationMedia)
        result += trains.compactMap(\.presentationMedia)
        result += restaurants.compactMap(\.presentationMedia)
        result += rentalVehicles.compactMap(\.presentationMedia)
        result += otherItems.compactMap(\.presentationMedia)
        return result
    }
}
