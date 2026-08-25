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

protocol MediaSearchService: Sendable {
    func searchImages(query: String, limit: Int) async throws -> [MediaSearchResult]
}

enum MediaSearchError: LocalizedError {
    case notConfigured, invalidResponse, downloadFailed
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Beeldzoeken is nog niet geconfigureerd. Voeg UNSPLASH_ACCESS_KEY toe aan de app-configuratie."
        case .invalidResponse: "De beeldprovider gaf een ongeldig antwoord."
        case .downloadFailed: "De gekozen afbeelding kon niet worden gedownload."
        }
    }
}

struct MediaSearchConfiguration: Sendable {
    let unsplashAccessKey: String?
    static var app: Self {
        let value = Bundle.main.object(forInfoDictionaryKey: "UNSPLASH_ACCESS_KEY") as? String
        return Self(unsplashAccessKey: value?.nilIfBlank)
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

    func searchImages(query: String, limit: Int) async throws -> [MediaSearchResult] {
        guard let accessKey else { throw MediaSearchError.notConfigured }
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
