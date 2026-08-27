import CoreLocation
import Foundation
import OSLog

struct GooglePlacesDiscoveryQuery: Encodable, Equatable {
    let textQuery: String
    let maxResultCount: Int
    let locationBias: LocationBias
    var includedType: String?

    struct LocationBias: Encodable, Equatable {
        let circle: Circle
        struct Circle: Encodable, Equatable {
            let center: Center
            let radius: Double
            struct Center: Encodable, Equatable { let latitude: Double; let longitude: Double }
        }
    }
}

struct DiscoveryQueryBuilder {
    func googleQuery(category: DiscoveryCategory, location: SearchLocation,
                     radiusMeters: Double) -> GooglePlacesDiscoveryQuery {
        GooglePlacesDiscoveryQuery(
            textQuery: "\(category.query) near \(location.name)",
            maxResultCount: 20,
            locationBias: .init(circle: .init(center: .init(latitude: location.latitude,
                                                              longitude: location.longitude),
                                                radius: min(max(radiusMeters, 500), 50_000))),
            includedType: category.googleIncludedType
        )
    }
}

@MainActor
final class GooglePlacesDiscoveryProvider: LocalDiscoverySearching, RadiusLocalDiscoverySearching {
    private struct Entry { let createdAt: Date; let results: [DiscoveryResult] }
    private let apiKey: String?
    private let session: URLSession
    private let lifetime: TimeInterval
    private var cache: [DiscoveryCacheKey: Entry] = [:]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
                                       category: "DiscoveryProvider")

    init(configuration: MediaSearchConfiguration, session: URLSession = .shared,
         lifetime: TimeInterval = 15 * 60) {
        apiKey = configuration.googlePlacesAPIKey
        self.session = session
        self.lifetime = lifetime
    }

    convenience init(session: URLSession = .shared, lifetime: TimeInterval = 15 * 60) {
        self.init(configuration: .app, session: session, lifetime: lifetime)
    }

    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult] {
        try await search(around: location, category: category, radiusMeters: 25_000)
    }

    func search(around location: SearchLocation, category: DiscoveryCategory,
                radiusMeters: Double) async throws -> [DiscoveryResult] {
        guard let apiKey else { throw MediaSearchError.notConfigured }
        let key = DiscoveryCacheKey(latitudeBucket: Int((location.latitude * 500).rounded()),
            longitudeBucket: Int((location.longitude * 500).rounded()), category: category,
            radiusBucket: Int((radiusMeters / 250).rounded()))
        if let entry = cache[key], Date().timeIntervalSince(entry.createdAt) < lifetime {
            Self.logger.debug("provider=google query=\(category.rawValue, privacy: .public) cache=hit results=\(entry.results.count, privacy: .public)")
            return entry.results
        }

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(DiscoveryQueryBuilder().googleQuery(
            category: category, location: location, radiusMeters: radiusMeters))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MediaSearchError.invalidResponse }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let origin = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let results = (decoded.places ?? []).compactMap { place -> DiscoveryResult? in
            guard let id = place.id, let coordinate = place.location,
                  let latitude = coordinate.latitude, let longitude = coordinate.longitude else { return nil }
            let distance = origin.distance(from: CLLocation(latitude: latitude, longitude: longitude))
            guard distance <= radiusMeters else { return nil }
            return DiscoveryResult(id: id, name: place.displayName?.text ?? place.formattedAddress ?? category.title,
                category: category, address: place.formattedAddress, latitude: latitude, longitude: longitude,
                distanceMeters: distance, phone: nil, websiteURL: place.websiteUri,
                rating: place.rating, reviewCount: place.userRatingCount,
                priceLevel: place.priceLevel.flatMap(DiscoveryPriceLevel.init(googleValue:)),
                googlePlaceID: id, primaryType: place.primaryType, isOpenNow: place.currentOpeningHours?.openNow,
                previewPhoto: place.preferredPhoto?.discoveryMetadata,
                sourceProviders: ["Google Places"])
        }
        cache[key] = Entry(createdAt: Date(), results: results)
        Self.logger.debug("provider=google query=\(category.rawValue, privacy: .public) cache=miss results=\(results.count, privacy: .public)")
        return results
    }

    static let fieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types,places.rating,places.userRatingCount,places.priceLevel,places.currentOpeningHours.openNow,places.websiteUri,places.photos.name,places.photos.widthPx,places.photos.heightPx,places.photos.authorAttributions.displayName,places.photos.authorAttributions.uri,places.photos.authorAttributions.photoUri,places.photos.googleMapsUri"

    private struct Response: Decodable { let places: [Place]? }
    private struct Place: Decodable {
        let id: String?
        let displayName: DisplayName?
        let formattedAddress: String?
        let location: Location?
        let primaryType: String?
        let types: [String]?
        let rating: Double?
        let userRatingCount: Int?
        let priceLevel: String?
        let currentOpeningHours: OpeningHours?
        let websiteUri: URL?
        let photos: [Photo]?
        struct DisplayName: Decodable { let text: String? }
        struct Location: Decodable { let latitude: Double?; let longitude: Double? }
        struct OpeningHours: Decodable { let openNow: Bool? }
        struct Photo: Decodable {
            let name: String?
            let widthPx: Int?
            let heightPx: Int?
            let authorAttributions: [AuthorAttribution]?
            let googleMapsUri: URL?
            struct AuthorAttribution: Decodable {
                let displayName: String?
                let uri: URL?
                let photoUri: URL?
            }

            var discoveryMetadata: DiscoveryPhotoMetadata? {
                guard let name, !name.isEmpty else { return nil }
                let authors = (authorAttributions ?? []).compactMap { author -> DiscoveryPhotoMetadata.AuthorAttribution? in
                    guard let displayName = author.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !displayName.isEmpty else { return nil }
                    return .init(displayName: displayName, profileURL: author.uri,
                                 profilePhotoURL: author.photoUri)
                }
                return DiscoveryPhotoMetadata(resourceName: name, width: widthPx, height: heightPx,
                                              authors: authors, googleMapsURL: googleMapsUri)
            }
        }

        var preferredPhoto: Photo? {
            photos?.filter { $0.name?.isEmpty == false }.max { lhs, rhs in
                suitability(of: lhs) < suitability(of: rhs)
            }
        }

        private func suitability(of photo: Photo) -> Double {
            guard let width = photo.widthPx, let height = photo.heightPx, height > 0 else { return 0 }
            let ratio = Double(width) / Double(height)
            let landscapeFit = max(0, 1 - abs(ratio - (16.0 / 9.0)))
            return landscapeFit * 10_000 + Double(min(width * height, 20_000_000)) / 20_000_000
        }
    }
}

@MainActor
final class PreferredDiscoveryService: LocalDiscoverySearching, RadiusLocalDiscoverySearching {
    private let primary: GooglePlacesDiscoveryProvider
    private let fallback: MapKitLocalDiscoveryService
    init(configuration: MediaSearchConfiguration, session: URLSession = .shared) {
        primary = GooglePlacesDiscoveryProvider(configuration: configuration, session: session)
        fallback = MapKitLocalDiscoveryService()
    }
    convenience init(session: URLSession = .shared) { self.init(configuration: .app, session: session) }
    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult] {
        try await search(around: location, category: category, radiusMeters: 25_000)
    }
    func search(around location: SearchLocation, category: DiscoveryCategory,
                radiusMeters: Double) async throws -> [DiscoveryResult] {
        do { return try await primary.search(around: location, category: category, radiusMeters: radiusMeters) }
        catch { return try await fallback.search(around: location, category: category, radiusMeters: radiusMeters) }
    }
}

private extension DiscoveryPriceLevel {
    init?(googleValue: String) {
        switch googleValue {
        case "PRICE_LEVEL_FREE": self = .free
        case "PRICE_LEVEL_INEXPENSIVE": self = .inexpensive
        case "PRICE_LEVEL_MODERATE": self = .moderate
        case "PRICE_LEVEL_EXPENSIVE", "PRICE_LEVEL_VERY_EXPENSIVE": self = .expensive
        default: return nil
        }
    }
}
