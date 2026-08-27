import Foundation
import OSLog

struct MediaSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let thumbnailURL: URL
    let imageURL: URL
    let sourceURL: URL?
    let sourceName: String
    let attribution: String?
}

enum MediaSearchSubject: Sendable { case place, flight, generic }

struct MediaSearchRequest: Sendable {
    let query: String
    let limit: Int
    var subject: MediaSearchSubject = .generic
    var googlePlaceID: String? = nil
}

protocol MediaSearchService: Sendable {
    func searchImages(request: MediaSearchRequest) async throws -> [MediaSearchResult]
}

extension MediaSearchService {
    func searchImages(query: String, limit: Int) async throws -> [MediaSearchResult] {
        try await searchImages(request: MediaSearchRequest(query: query, limit: limit))
    }
}

enum MediaSearchError: LocalizedError {
    case notConfigured, invalidResponse, downloadFailed
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Beeldzoeken is nog niet geconfigureerd. Voeg BRAVE_SEARCH_API_KEY of UNSPLASH_ACCESS_KEY toe aan de externe buildconfiguratie."
        case .invalidResponse: "De beeldprovider gaf een ongeldig antwoord."
        case .downloadFailed: "De gekozen afbeelding kon niet worden gedownload."
        }
    }
}

struct MediaSearchConfiguration: Sendable {
    let googlePlacesAPIKey: String?
    let braveSearchAPIKey: String?
    let unsplashAccessKey: String?
    static var app: Self {
        func configured(_ key: String) -> String? {
            guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.nilIfBlank,
                  !value.hasPrefix("$(") else { return nil }
            return value
        }
        return Self(googlePlacesAPIKey: configured("GOOGLE_PLACES_API_KEY"),
                    braveSearchAPIKey: configured("BRAVE_SEARCH_API_KEY"),
                    unsplashAccessKey: configured("UNSPLASH_ACCESS_KEY"))
    }
}

struct PreferredMediaSearchService: MediaSearchService {
    private let web: WebMediaSearchService

    init(configuration: MediaSearchConfiguration = .app, session: URLSession = .shared) {
        web = WebMediaSearchService(configuration: configuration, session: session)
    }

    func searchImages(request: MediaSearchRequest) async throws -> [MediaSearchResult] {
        return try await web.searchImages(request: request)
    }
}

struct WebMediaSearchService: MediaSearchService {
    private let primary: BraveImageSearchService
    private let fallback: UnsplashMediaSearchService
    private let configuration: MediaSearchConfiguration
    init(configuration: MediaSearchConfiguration = .app, session: URLSession = .shared) {
        self.configuration = configuration
        primary = BraveImageSearchService(configuration: configuration, session: session)
        fallback = UnsplashMediaSearchService(configuration: configuration, session: session)
    }
    func searchImages(request: MediaSearchRequest) async throws -> [MediaSearchResult] {
        if configuration.braveSearchAPIKey != nil {
            do { return try await primary.searchImages(request: request) }
            catch where configuration.unsplashAccessKey != nil { return try await fallback.searchImages(request: request) }
        }
        return try await fallback.searchImages(request: request)
    }
}

struct GooglePlaceCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let formattedAddress: String?
    let latitude: Double?
    let longitude: Double?
    var imageQuery: String { [displayName, formattedAddress].compactMap { $0?.nilIfBlank }.joined(separator: " ") }
}

protocol GooglePlacesResolving: Sendable {
    var isConfigured: Bool { get }
    func resolve(query: String, existingPlaceID: String?) async throws -> [GooglePlaceCandidate]
}

/// Entity resolution only. It deliberately does not request or persist Google photos.
struct GooglePlacesEntityResolver: GooglePlacesResolving {
    private let apiKey: String?
    private let session: URLSession
    init(configuration: MediaSearchConfiguration = .app, session: URLSession = .shared) {
        apiKey = configuration.googlePlacesAPIKey; self.session = session
    }
    var isConfigured: Bool { apiKey != nil }

    func resolve(query: String, existingPlaceID: String?) async throws -> [GooglePlaceCandidate] {
        guard let apiKey else { throw MediaSearchError.notConfigured }
        if let existingPlaceID {
            return [try await details(placeID: existingPlaceID, apiKey: apiKey).candidate(fallbackID: existingPlaceID)]
        }
        return try await textSearch(query: query, apiKey: apiKey).map { $0.candidate(fallbackID: $0.id ?? "") }
    }

    private func textSearch(query: String, apiKey: String) async throws -> [GooglePlace] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(TextSearchBody(textQuery: query, maxResultCount: 5))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let places = try? JSONDecoder().decode(TextSearchResponse.self, from: data).places,
              !places.isEmpty else {
            throw MediaSearchError.invalidResponse
        }
        return places
    }

    private func details(placeID: String, apiKey: String) async throws -> GooglePlace {
        let encoded = placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? placeID
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places/\(encoded)")!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("id,displayName,formattedAddress,location", forHTTPHeaderField: "X-Goog-FieldMask")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MediaSearchError.invalidResponse }
        return try JSONDecoder().decode(GooglePlace.self, from: data)
    }

    private struct TextSearchBody: Encodable { let textQuery: String; let maxResultCount: Int }
    private struct TextSearchResponse: Decodable { let places: [GooglePlace] }
    private struct GooglePlace: Decodable {
        let id: String?; let displayName: DisplayName?; let formattedAddress: String?; let location: Location?
        struct DisplayName: Decodable { let text: String }
        struct Location: Decodable { let latitude: Double?; let longitude: Double? }
        func candidate(fallbackID: String) -> GooglePlaceCandidate {
            GooglePlaceCandidate(id: id ?? fallbackID, displayName: displayName?.text ?? formattedAddress ?? "Locatie",
                                 formattedAddress: formattedAddress, latitude: location?.latitude,
                                 longitude: location?.longitude)
        }
    }
}

struct BraveImageSearchService: MediaSearchService {
    private let apiKey: String?
    private let session: URLSession
    init(configuration: MediaSearchConfiguration = .app, session: URLSession = .shared) {
        apiKey = configuration.braveSearchAPIKey; self.session = session
    }

    func searchImages(request mediaRequest: MediaSearchRequest) async throws -> [MediaSearchResult] {
        guard let apiKey else { throw MediaSearchError.notConfigured }
        let query = mediaRequest.query, limit = mediaRequest.limit
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/images/search")!
        components.queryItems = [
            .init(name: "q", value: query), .init(name: "count", value: String(min(max(limit, 1), 20))),
            .init(name: "country", value: "ALL"), .init(name: "safesearch", value: "strict")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MediaSearchError.invalidResponse }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        return payload.results.compactMap { result in
            guard let imageURL = URL(string: result.properties?.url ?? result.url),
                  let thumbnailURL = URL(string: result.thumbnail?.src ?? result.properties?.url ?? result.url) else { return nil }
            let contextURL = result.source.flatMap(URL.init(string:))
            return MediaSearchResult(id: result.id ?? imageURL.absoluteString, thumbnailURL: thumbnailURL,
                imageURL: imageURL, sourceURL: contextURL, sourceName: result.sourceDomain ?? contextURL?.host ?? "Brave Search",
                attribution: result.title)
        }
    }

    private struct Response: Decodable { let results: [Result] }
    private struct Result: Decodable {
        let id: String?; let title: String?; let url: String; let source: String?
        let properties: Properties?; let thumbnail: Thumbnail?
        var sourceDomain: String? { source.flatMap { URL(string: $0)?.host } }
        struct Properties: Decodable { let url: String? }
        struct Thumbnail: Decodable { let src: String? }
    }
}

struct UnsplashMediaSearchService: MediaSearchService {
    private let accessKey: String?
    private let session: URLSession
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
                                       category: "MediaSearch")
    init(configuration: MediaSearchConfiguration = .app, session: URLSession = .shared) {
        accessKey = configuration.unsplashAccessKey; self.session = session
    }

    func searchImages(request mediaRequest: MediaSearchRequest) async throws -> [MediaSearchResult] {
        guard let accessKey else { throw MediaSearchError.notConfigured }
        let query = mediaRequest.query, limit = mediaRequest.limit
        var components = URLComponents(string: "https://api.unsplash.com/search/photos")!
        components.queryItems = [.init(name: "query", value: query),
                                 .init(name: "per_page", value: String(min(max(limit, 1), 30))),
                                 .init(name: "orientation", value: "landscape")]
        var request = URLRequest(url: components.url!)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        Self.logger.info("Searching media; query length \(query.count, privacy: .public), limit \(limit, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MediaSearchError.invalidResponse }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        return payload.results.compactMap { photo in
            guard let thumbnail = URL(string: photo.urls.small), let image = URL(string: photo.urls.regular) else { return nil }
            return MediaSearchResult(id: photo.id, thumbnailURL: thumbnail, imageURL: image,
                sourceURL: URL(string: photo.links.html), sourceName: "Unsplash",
                attribution: photo.user.name.map { "Foto: \($0) / Unsplash" })
        }
    }

    private struct Response: Decodable { let results: [Photo] }
    private struct Photo: Decodable {
        let id: String; let urls: URLs; let links: Links; let user: User
        struct URLs: Decodable { let small: String; let regular: String }
        struct Links: Decodable { let html: String }
        struct User: Decodable { let name: String? }
    }
}

struct MediaQueryBuilder {
    func accommodation(name: String, place: String?, country: String, address: String?) -> String {
        joined([name, place, country, address])
    }
    func flight(carrierName: String, aircraft: String?) -> String { joined([carrierName, aircraft]) }
    func activity(name: String, place: String?, country: String) -> String { joined([name, place, country]) }
    private func joined(_ values: [String?]) -> String {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            .reduce(into: [String]()) { parts, value in
                if !parts.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { parts.append(value) }
            }.joined(separator: " ")
    }
}

struct MediaDownloader: Sendable {
    private let session: URLSession
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
                                       category: "MediaDownload")
    init(session: URLSession = .shared) { self.session = session }
    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            Self.logger.error("Media download failed")
            throw MediaSearchError.downloadFailed
        }
        Self.logger.info("Media download completed; bytes \(data.count, privacy: .public)")
        return data
    }
}
