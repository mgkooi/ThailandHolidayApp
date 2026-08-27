import CoreLocation
import MapKit
import Observation

@MainActor protocol LocalDiscoverySearching {
    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult]
}

@MainActor protocol RadiusLocalDiscoverySearching {
    func search(around location: SearchLocation, category: DiscoveryCategory,
                radiusMeters: Double) async throws -> [DiscoveryResult]
}

struct DiscoveryCacheKey: Hashable {
    let latitudeBucket: Int
    let longitudeBucket: Int
    let category: DiscoveryCategory
    let radiusBucket: Int
}

@MainActor final class MapKitLocalDiscoveryService: LocalDiscoverySearching {
    private var cache: [DiscoveryCacheKey: [DiscoveryResult]] = [:]

    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult] {
        try await search(around: location, category: category, radiusMeters: 25_000)
    }

    func search(around location: SearchLocation, category: DiscoveryCategory,
                radiusMeters: Double) async throws -> [DiscoveryResult] {
        let key = DiscoveryCacheKey(latitudeBucket: Int((location.latitude * 1_000).rounded()),
                           longitudeBucket: Int((location.longitude * 1_000).rounded()), category: category,
                           radiusBucket: Int(radiusMeters.rounded()))
        if let cached = cache[key] { return cached }

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        let queries: [String]
        switch category {
        case .activity:
            queries = ["Tourist attraction", "Museum", "National park", "Temple", "Things to do"]
        case .viewpoint:
            queries = ["Viewpoint", "Scenic viewpoint", "Lookout", "Observation point", "Sunset viewpoint"]
        default:
            queries = [category.query]
        }
        var mapItems: [MKMapItem] = []
        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            if category == .restaurant {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
            } else if category == .atm {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.atm])
            }
            // Do not combine broad activity/viewpoint terms with a narrow POI filter:
            // MapKit otherwise removes temples, lookouts and other valid attractions.
            if let response = try? await MKLocalSearch(request: request).start() { mapItems += response.mapItems }
        }
        if mapItems.isEmpty { throw LocalDiscoveryError.noResults }
        let origin = CLLocation(latitude: location.latitude, longitude: location.longitude)
        var seen = Set<String>()
        let results = mapItems.compactMap { item -> DiscoveryResult? in
            let coordinate = item.location.coordinate
            let identity = "\(coordinate.latitude.rounded(toPlaces: 5))-\(coordinate.longitude.rounded(toPlaces: 5))-\(item.name ?? "")"
            guard seen.insert(identity).inserted else { return nil }
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= radiusMeters else { return nil }
            return DiscoveryResult(
                id: "\(category.rawValue)-\(coordinate.latitude)-\(coordinate.longitude)-\(item.name ?? "")",
                name: item.name ?? category.title,
                category: category,
                address: item.address?.fullAddress,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distanceMeters: distance,
                phone: item.phoneNumber,
                websiteURL: item.url
            )
        }.sorted(by: DiscoveryResult.nearestFirst)
        cache[key] = results
        return results
    }
}

extension MapKitLocalDiscoveryService: RadiusLocalDiscoverySearching {}

extension MapKitLocalDiscoveryService: DiscoveryProviding {
    func search(category: DiscoveryCategory, near location: SearchLocation,
                radiusMeters: Double) async throws -> [DiscoveryRecommendation] {
        try await search(around: location, category: category, radiusMeters: radiusMeters)
    }
}

enum LocalDiscoveryError: Error { case noResults }

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places)); return (self * factor).rounded() / factor
    }
}

extension DiscoveryResult {
    static func nearestFirst(_ lhs: DiscoveryResult, _ rhs: DiscoveryResult) -> Bool {
        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (left?, right?): left < right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

struct TripSearchLocationResolver {
    let geocoder: any LocationGeocoding

    func resolve(for date: Date, in trip: Trip) async -> SearchLocation? {
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        let accommodation = trip.accommodations.first {
            let day = calendar.startOfDay(for: date)
            return day >= calendar.startOfDay(for: $0.checkIn) && day < calendar.startOfDay(for: $0.checkOut)
        }
        if let accommodation {
            if let location = coordinateLocation(accommodation.location, fallbackName: accommodation.name) { return location }
            if let location = await geocodedLocation(accommodation.location, fallbackName: accommodation.name) { return location }
        }
        if let destination = trip.destinations.first(where: {
            let day = calendar.startOfDay(for: date)
            return day >= calendar.startOfDay(for: $0.arrivalDate) && day <= calendar.startOfDay(for: $0.departureDate)
        }) {
            return SearchLocation(name: destination.name, latitude: destination.latitude, longitude: destination.longitude)
        }
        for activity in trip.activities where calendar.isDate(activity.date, inSameDayAs: date) {
            if let location = activity.location,
               let resolved = coordinateLocation(location, fallbackName: activity.title) { return resolved }
            if let location = activity.location,
               let resolved = await geocodedLocation(location, fallbackName: activity.title) { return resolved }
        }
        return nil
    }

    private func coordinateLocation(_ location: TripLocation, fallbackName: String) -> SearchLocation? {
        guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
        return SearchLocation(name: location.placeName?.nilIfBlank ?? fallbackName, latitude: latitude, longitude: longitude)
    }

    private func geocodedLocation(_ location: TripLocation, fallbackName: String) async -> SearchLocation? {
        let query = [location.address?.nilIfBlank, location.placeName?.nilIfBlank].compactMap { $0 }.joined(separator: ", ")
        guard !query.isEmpty, let coordinate = try? await geocoder.geocode(address: query) else { return nil }
        return SearchLocation(name: location.placeName?.nilIfBlank ?? fallbackName,
                              latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

@MainActor @Observable
final class DiscoverySession {
    private let searcher: any LocalDiscoverySearching
    private let geocoder: any LocationGeocoding
    private let editorialProvider: any EditorialRecommendationProviding
    var activeLocation: SearchLocation?
    var selectedCategory: DiscoveryCategory = .restaurant
    var selectedFeed: DiscoveryFeed? = .forYou
    private(set) var results: [DiscoveryResult] = []
    private(set) var state: DiscoveryLoadState = .idle
    private var searchGeneration = 0
    private(set) var searchRadiusMeters: Double = 25_000

    init(searcher: any LocalDiscoverySearching, geocoder: any LocationGeocoding,
         editorialProvider: any EditorialRecommendationProviding) {
        self.searcher = searcher; self.geocoder = geocoder; self.editorialProvider = editorialProvider
    }

    convenience init(searcher: any LocalDiscoverySearching, geocoder: any LocationGeocoding) {
        self.init(searcher: searcher, geocoder: geocoder,
                  editorialProvider: DisabledEditorialRecommendationProvider())
    }

    func activate(_ location: SearchLocation, category: DiscoveryCategory = .restaurant,
                  radiusMeters: Double = 25_000) async {
        activeLocation = location; selectedCategory = category; selectedFeed = nil
        searchRadiusMeters = radiusMeters
        await refresh()
    }

    func select(_ category: DiscoveryCategory, radiusMeters: Double? = nil) async {
        selectedCategory = category; selectedFeed = nil
        if let radiusMeters { searchRadiusMeters = radiusMeters }
        await refresh()
    }

    func selectFeed(_ feed: DiscoveryFeed, radiusMeters: Double? = nil) async {
        selectedFeed = feed
        if let first = feed.categories.first { selectedCategory = first }
        if let radiusMeters { searchRadiusMeters = radiusMeters }
        await refresh()
    }

    @discardableResult
    func searchPlace(_ query: String, radiusMeters: Double = 25_000) async -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        searchGeneration += 1
        let generation = searchGeneration
        state = .loading
        guard let coordinate = try? await geocoder.geocode(address: trimmed) else {
            guard generation == searchGeneration else { return false }
            results = []; state = .failed; return false
        }
        guard generation == searchGeneration else { return false }
        activeLocation = SearchLocation(name: trimmed, latitude: coordinate.latitude, longitude: coordinate.longitude)
        searchRadiusMeters = radiusMeters
        await refresh()
        return true
    }

    func refresh(radiusMeters: Double? = nil) async {
        guard let activeLocation else { results = []; state = .idle; return }
        if let radiusMeters { searchRadiusMeters = radiusMeters }
        searchGeneration += 1
        let generation = searchGeneration
        let category = selectedCategory
        let feed = selectedFeed
        let radius = searchRadiusMeters
        state = .loading
        do {
            var found: [DiscoveryResult] = []
            for requestedCategory in feed?.categories ?? [category] {
                let values: [DiscoveryResult]
                if let radiusSearcher = searcher as? any RadiusLocalDiscoverySearching {
                    values = try await radiusSearcher.search(around: activeLocation, category: requestedCategory, radiusMeters: radius)
                } else {
                    values = try await searcher.search(around: activeLocation, category: requestedCategory)
                }
                found.append(contentsOf: values)
            }
            guard generation == searchGeneration, self.activeLocation == activeLocation,
                  selectedCategory == category, selectedFeed == feed else { return }
            var seen = Set<String>()
            var local = found.filter { candidate in
                let identity = candidate.googlePlaceID ?? candidate.id
                return seen.insert(identity).inserted && (candidate.distanceMeters.map { $0 <= radius } ?? false)
            }
            if category.supportsRecommendations,
               let editorial = try? await editorialProvider.recommendations(for: activeLocation, category: category) {
                let matcher = EditorialRecommendationMatcher()
                local = local.map { candidate in
                    var enriched = candidate
                    let matched = matcher.signals(for: candidate, city: activeLocation.name,
                                                  recommendations: editorial)
                    enriched.editorialSignals = Array(Set(candidate.editorialSignals + matched))
                    return enriched
                }
            }
            guard generation == searchGeneration else { return }
            var ranked = RecommendationScorer().enrichAndRank(local)
            if feed == .hiddenGems { ranked = ranked.filter { $0.badges.contains(.hiddenGem) } }
            if feed == .nearby { ranked.sort(by: DiscoveryResult.nearestFirst) }
            if feed == .forYou { ranked = DiscoveryDiversifier().diversified(ranked) }
            results = ranked
            state = results.isEmpty ? .empty : .loaded
        } catch {
            guard generation == searchGeneration else { return }
            results = []; state = .failed
        }
    }
}

struct UITestDiscoveryService: LocalDiscoverySearching {
    func search(around location: SearchLocation, category: DiscoveryCategory) async throws -> [DiscoveryResult] {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-discovery") { return [] }
        return (0..<4).map { index in
            DiscoveryResult(id: "ui-\(category.rawValue)-\(index)", name: "\(category.title) test \(index + 1)",
                category: category, address: "Testadres \(index + 1)", latitude: location.latitude + Double(index) * 0.001,
                longitude: location.longitude, distanceMeters: Double(index + 1) * 250, phone: nil,
                websiteURL: URL(string: "https://example.com/\(category.rawValue)/\(index)"),
                rating: 4.7 - Double(index) * 0.1, reviewCount: 1200 - index * 200,
                priceLevel: category.isFood ? .moderate : nil, googlePlaceID: "ui-place-\(category.rawValue)-\(index)",
                primaryType: category.rawValue, isOpenNow: index != 3, sourceProviders: ["UI Fixture"])
        }
    }
}
