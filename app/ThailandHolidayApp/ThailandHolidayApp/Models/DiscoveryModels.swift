import Foundation

struct SearchLocation: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double

    var tripLocation: TripLocation {
        TripLocation(placeName: name, address: nil, latitude: latitude, longitude: longitude)
    }
}

enum DiscoveryCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case restaurant, cafe, bar, activity, attraction, museum, temple, park, viewpoint, market, shopping, atm, sevenEleven

    var id: String { rawValue }
    var title: String {
        switch self {
        case .restaurant: "Restaurants"
        case .cafe: "Cafés"
        case .bar: "Bars"
        case .activity: "Activiteiten"
        case .attraction: "Bezienswaardigheden"
        case .museum: "Musea"
        case .temple: "Tempels"
        case .park: "Parken"
        case .viewpoint: "Viewpoints"
        case .market: "Markten"
        case .shopping: "Winkels"
        case .atm: "ATM's"
        case .sevenEleven: "7-Eleven"
        }
    }
    var query: String {
        switch self {
        case .restaurant: "Restaurant"
        case .cafe: "Cafe"
        case .bar: "Bar"
        case .activity: "Tourist attraction"
        case .attraction: "Tourist attraction"
        case .museum: "Museum"
        case .temple: "Temple"
        case .park: "Park"
        case .viewpoint: "Scenic viewpoint"
        case .market: "Market"
        case .shopping: "Shopping"
        case .atm: "ATM cash machine"
        case .sevenEleven: "7-Eleven"
        }
    }
    var symbolName: String {
        switch self {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .bar: "wineglass.fill"
        case .activity: "figure.hiking"
        case .attraction: "camera.fill"
        case .museum: "building.columns.fill"
        case .temple: "building.columns"
        case .park: "leaf.fill"
        case .viewpoint: "binoculars.fill"
        case .market: "basket.fill"
        case .shopping: "bag.fill"
        case .atm: "banknote.fill"
        case .sevenEleven: "cart.fill"
        }
    }
    var supportsRecommendations: Bool { self != .atm && self != .sevenEleven }
    var supportsPrice: Bool { [.restaurant, .cafe, .bar, .activity, .attraction, .market, .shopping].contains(self) }
    var isFood: Bool { [.restaurant, .cafe, .bar].contains(self) }
    var googleIncludedType: String? {
        switch self {
        case .restaurant: "restaurant"
        case .cafe: "cafe"
        case .bar: "bar"
        case .activity, .attraction: "tourist_attraction"
        case .museum: "museum"
        case .temple: "hindu_temple"
        case .park: "park"
        case .viewpoint: nil
        case .market: "market"
        case .shopping: "shopping_mall"
        case .atm: "atm"
        case .sevenEleven: "convenience_store"
        }
    }
}

enum DiscoveryFeed: String, CaseIterable, Identifiable, Sendable {
    case forYou, food, activities, sights, viewpoints, hiddenGems, nearby
    var id: String { rawValue }
    var title: String { switch self { case .forYou: "Voor jou"; case .food: "Eten"; case .activities: "Doen"; case .sights: "Zien"; case .viewpoints: "Viewpoints"; case .hiddenGems: "Verborgen parels"; case .nearby: "In de buurt" } }
    var categories: [DiscoveryCategory] { switch self {
        case .forYou: [.restaurant, .activity, .attraction, .viewpoint, .market]
        case .food: [.restaurant, .cafe, .bar]
        case .activities: [.activity, .park, .market]
        case .sights: [.attraction, .museum, .temple]
        case .viewpoints: [.viewpoint]
        case .hiddenGems: [.restaurant, .activity, .attraction, .viewpoint]
        case .nearby: [.restaurant, .cafe, .activity, .attraction, .viewpoint]
    } }
}

enum DiscoveryPriceLevel: Int, CaseIterable, Equatable, Hashable, Sendable {
    case free = 0, inexpensive = 1, moderate = 2, expensive = 3
    var title: String { self == .free ? "Gratis" : String(repeating: "€", count: rawValue) }
}

typealias ActivityPriceLevel = DiscoveryPriceLevel

enum EditorialSource: String, CaseIterable, Hashable, Sendable {
    case tripAdvisor, reisjunk, tipsThailand, travelfish, lonelyPlanet
    var title: String {
        switch self {
        case .tripAdvisor: "TripAdvisor"
        case .reisjunk: "Reisjunk"
        case .tipsThailand: "Tips Thailand"
        case .travelfish: "Travelfish"
        case .lonelyPlanet: "Lonely Planet"
        }
    }
}

struct EditorialSignal: Equatable, Hashable, Sendable {
    let source: EditorialSource
    let sourceURL: URL?
    let matchConfidence: Double
    var isScenic: Bool = false
}

/// Session-only Google Places photo data. Trip and favorite persistence deliberately
/// never reference this type, so photo resource names cannot enter a trip archive.
struct DiscoveryPhotoMetadata: Equatable, Sendable {
    struct AuthorAttribution: Equatable, Sendable, Identifiable {
        let displayName: String
        let profileURL: URL?
        let profilePhotoURL: URL?

        var id: String { "\(displayName)|\(profileURL?.absoluteString ?? "")" }
    }

    let resourceName: String
    let width: Int?
    let height: Int?
    let authors: [AuthorAttribution]
    let googleMapsURL: URL?
}

enum RecommendationBadge: String, CaseIterable, Hashable, Sendable {
    case starWorthy, hiddenGem, instagramWorthy
    var title: String {
        switch self {
        case .starWorthy: "Star Worthy"
        case .hiddenGem: "Hidden Gem"
        case .instagramWorthy: "Instagram Worthy"
        }
    }
}

struct DiscoveryRecommendation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: DiscoveryCategory
    let address: String?
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double?
    let phone: String?
    let websiteURL: URL?
    var rating: Double? = nil
    var reviewCount: Int? = nil
    var priceLevel: DiscoveryPriceLevel? = nil
    var estimatedPrice: Decimal? = nil
    var currencyCode: String? = nil
    var editorialSignals: [EditorialSignal] = []
    var recommendationScore: Double? = nil
    var badges: Set<RecommendationBadge> = []
    var googlePlaceID: String? = nil
    var primaryType: String? = nil
    var isOpenNow: Bool? = nil
    var previewImageURL: URL? = nil
    var photoAttribution: String? = nil
    var previewPhoto: DiscoveryPhotoMetadata? = nil
    var sourceProviders: Set<String> = []

    var location: TripLocation {
        TripLocation(placeName: name, address: address, latitude: latitude, longitude: longitude)
    }
}

typealias DiscoveryResult = DiscoveryRecommendation

struct DiscoveryFilters: Equatable, Sendable {
    var maxDistanceMeters: Double? = 10_000
    var priceLevels: Set<DiscoveryPriceLevel> = []
    var minimumRating: Double?
    var minimumReviewCount: Int?
    var starWorthyOnly = false
    var hiddenGemOnly = false
    var instagramWorthyOnly = false
    var openNowOnly = false
    var categories: Set<DiscoveryCategory> = []

    var activeCount: Int {
        (priceLevels.isEmpty ? 0 : 1) + (minimumRating == nil ? 0 : 1)
            + (minimumReviewCount == nil ? 0 : 1) + (maxDistanceMeters == 10_000 ? 0 : 1)
            + [starWorthyOnly, hiddenGemOnly, instagramWorthyOnly, openNowOnly].filter { $0 }.count
            + (categories.isEmpty ? 0 : 1)
    }

    func includes(_ result: DiscoveryRecommendation, category: DiscoveryCategory? = nil) -> Bool {
        if let maximum = maxDistanceMeters, let distance = result.distanceMeters, distance > maximum { return false }
        if !priceLevels.isEmpty {
            guard let level = result.priceLevel, priceLevels.contains(level) else { return false }
        }
        if let minimumRating { guard let rating = result.rating, rating >= minimumRating else { return false } }
        if let minimumReviewCount { guard let count = result.reviewCount, count >= minimumReviewCount else { return false } }
        if openNowOnly && result.isOpenNow != true { return false }
        if !categories.isEmpty && !categories.contains(result.category) { return false }
        let derivedBadges = result.badges.isEmpty ? RecommendationScorer().score(result).badges : result.badges
        if starWorthyOnly && !derivedBadges.contains(.starWorthy) { return false }
        if hiddenGemOnly && !derivedBadges.contains(.hiddenGem) { return false }
        if instagramWorthyOnly && !derivedBadges.contains(.instagramWorthy) { return false }
        return true
    }
}

typealias ActivityFilters = DiscoveryFilters

struct RecommendationScore: Equatable, Sendable {
    let value: Double
    let badges: Set<RecommendationBadge>
}

struct RecommendationScorer: Sendable {
    struct Weights: Equatable, Sendable {
        var rating = 24.0
        var reviews = 10.0
        var distance = 16.0
        var category = 8.0
        var editorial = 12.0
        var availability = 5.0
        static let standard = Weights()
    }
    let weights: Weights
    init(weights: Weights = .standard) { self.weights = weights }

    func score(_ item: DiscoveryRecommendation) -> RecommendationScore {
        guard item.category.supportsRecommendations else { return RecommendationScore(value: proximity(item), badges: []) }
        let rating = item.rating ?? 0
        let reviews = item.reviewCount ?? 0
        let editorial = Set(item.editorialSignals.filter { $0.matchConfidence >= 0.7 }.map(\.source)).count
        var value = proximity(item) * weights.distance / 15
        if item.rating != nil { value += max(0, rating - 3) / 2 * weights.rating }
        if reviews > 0 { value += min(log10(Double(reviews) + 1) / 4, 1) * weights.reviews }
        value += min(Double(editorial), 3) / 3 * weights.editorial
        value += item.category.supportsRecommendations ? weights.category : 0
        if item.isOpenNow == true { value += weights.availability }
        if item.isOpenNow == false { value -= weights.availability }

        var badges = Set<RecommendationBadge>()
        if rating >= 4.6 && reviews >= 250 && (reviews >= 1_000 || editorial >= 2) { badges.insert(.starWorthy) }
        if rating >= 4.5 && (50...1_500).contains(reviews) && (item.distanceMeters ?? 0) <= 15_000 { badges.insert(.hiddenGem) }
        let scenic = item.category == .viewpoint || item.editorialSignals.contains { $0.isScenic && $0.matchConfidence >= 0.7 }
        if scenic && (item.category == .viewpoint || rating >= 4.3 || editorial >= 1) { badges.insert(.instagramWorthy) }
        return RecommendationScore(value: value, badges: badges)
    }

    func enrichAndRank(_ candidates: [DiscoveryRecommendation]) -> [DiscoveryRecommendation] {
        candidates.map { candidate in
            var result = candidate
            let score = score(candidate)
            result.recommendationScore = score.value
            result.badges = score.badges
            return result
        }.sorted {
            if ($0.recommendationScore ?? 0) != ($1.recommendationScore ?? 0) {
                return ($0.recommendationScore ?? 0) > ($1.recommendationScore ?? 0)
            }
            return ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }

    private func proximity(_ item: DiscoveryRecommendation) -> Double {
        guard let distance = item.distanceMeters else { return 0 }
        return max(0, 15 - distance / 1_000)
    }
}

enum DiscoverySort: String, CaseIterable, Identifiable, Sendable {
    case recommended, distance, rating, reviewCount
    var id: String { rawValue }
    var title: String { switch self { case .recommended: "Aanbevolen"; case .distance: "Afstand"; case .rating: "Rating"; case .reviewCount: "Meeste reviews" } }
}

struct DiscoveryDiversifier {
    func diversified(_ values: [DiscoveryResult], maximumConsecutive: Int = 2) -> [DiscoveryResult] {
        var remaining = values
        var output: [DiscoveryResult] = []
        while !remaining.isEmpty {
            let recent = output.suffix(maximumConsecutive).map(\.category)
            let index = recent.count == maximumConsecutive && Set(recent).count == 1
                ? (remaining.firstIndex { $0.category != recent[0] } ?? remaining.startIndex)
                : remaining.startIndex
            output.append(remaining.remove(at: index))
        }
        return output
    }
}

protocol DiscoveryProviding {
    func search(category: DiscoveryCategory, near location: SearchLocation,
                radiusMeters: Double) async throws -> [DiscoveryRecommendation]
}

protocol EditorialRecommendationProviding {
    func recommendations(for location: SearchLocation,
                         category: DiscoveryCategory) async throws -> [EditorialRecommendation]
}

protocol EditorialSourceService: EditorialRecommendationProviding {}

struct DisabledEditorialRecommendationProvider: EditorialSourceService {
    func recommendations(for location: SearchLocation,
                         category: DiscoveryCategory) async throws -> [EditorialRecommendation] { [] }
}

struct CompositeEditorialRecommendationProvider: EditorialRecommendationProviding {
    let providers: [any EditorialRecommendationProviding]
    func recommendations(for location: SearchLocation,
                         category: DiscoveryCategory) async throws -> [EditorialRecommendation] {
        var combined: [EditorialRecommendation] = []
        for provider in providers {
            if let values = try? await provider.recommendations(for: location, category: category) {
                combined.append(contentsOf: values)
            }
        }
        return combined
    }
}

@MainActor final class CachedEditorialRecommendationProvider: EditorialRecommendationProviding {
    private struct Key: Hashable {
        let source: EditorialSource
        let latitudeBucket: Int
        let longitudeBucket: Int
        let category: DiscoveryCategory
    }
    private struct Entry { let date: Date; let values: [EditorialRecommendation] }
    private let source: EditorialSource
    private let provider: any EditorialRecommendationProviding
    private let lifetime: TimeInterval
    private var cache: [Key: Entry] = [:]

    init(source: EditorialSource, provider: any EditorialRecommendationProviding,
         lifetime: TimeInterval = 6 * 60 * 60) {
        self.source = source; self.provider = provider; self.lifetime = lifetime
    }

    func recommendations(for location: SearchLocation,
                         category: DiscoveryCategory) async throws -> [EditorialRecommendation] {
        let key = Key(source: source, latitudeBucket: Int((location.latitude * 100).rounded()),
                      longitudeBucket: Int((location.longitude * 100).rounded()), category: category)
        if let entry = cache[key], Date().timeIntervalSince(entry.date) < lifetime { return entry.values }
        let values = try await provider.recommendations(for: location, category: category)
        cache[key] = Entry(date: Date(), values: values)
        return values
    }
}

struct EditorialRecommendation: Equatable, Sendable {
    let normalizedName: String
    let city: String
    let latitude: Double?
    let longitude: Double?
    let signal: EditorialSignal
    var category: DiscoveryCategory? = nil
}

struct EditorialRecommendationMatcher {
    func signals(for place: DiscoveryRecommendation, city: String,
                 recommendations: [EditorialRecommendation]) -> [EditorialSignal] {
        let placeName = normalize(place.name)
        let placeCity = normalize(city)
        return recommendations.compactMap { editorial in
            guard editorial.signal.matchConfidence >= 0.7 else { return nil }
            guard normalize(editorial.normalizedName) == placeName, normalize(editorial.city) == placeCity else { return nil }
            guard editorial.category == nil || editorial.category == place.category else { return nil }
            if let latitude = editorial.latitude, let longitude = editorial.longitude {
                let delta = hypot(latitude - place.latitude, longitude - place.longitude)
                guard delta < 0.02 else { return nil }
            }
            return editorial.signal
        }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum DiscoveryLoadState: Equatable { case idle, loading, loaded, empty, failed }

struct DiscoveryDistanceFormatter {
    static func string(meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", locale: Locale(identifier: "nl_NL"), meters / 1_000)
    }
}
