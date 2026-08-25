import MapKit
import SwiftUI

@MainActor protocol MapSearchProviding {
    func search(query: String, visibleRegion: MKCoordinateRegion?) async throws -> [MapPlace]
}

@MainActor struct MapSearchService: MapSearchProviding {
    func search(query: String, visibleRegion: MKCoordinateRegion?) async throws -> [MapPlace] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = value
        if let visibleRegion { request.region = visibleRegion }
        return try await MKLocalSearch(request: request).start().mapItems.map(MapPlace.init(mapItem:))
    }
}

private struct MapSearchProviderKey: EnvironmentKey {
    static let defaultValue: any MapSearchProviding = MapSearchService()
}

extension EnvironmentValues {
    var mapSearchProvider: any MapSearchProviding {
        get { self[MapSearchProviderKey.self] }
        set { self[MapSearchProviderKey.self] = newValue }
    }
}

struct TripMapDuplicateDetector {
    func duplicate(of place: MapPlace, in trip: Trip) -> TripMapAnnotation? {
        let normalizedName = normalize(place.name)
        let normalizedAddress = normalize(place.address ?? "")
        let target = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return TripMapAnnotationBuilder(airportLookup: AirportLookup()).annotations(for: trip).first { annotation in
            let sameName = !normalizedName.isEmpty && normalize(annotation.title).contains(normalizedName)
            let sameAddress = !normalizedAddress.isEmpty && normalize(annotation.location.address ?? "") == normalizedAddress
            let existing = CLLocation(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude)
            return sameAddress || (sameName && target.distance(from: existing) <= 75)
        }
    }
    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

@MainActor struct UITestMapSearchService: MapSearchProviding {
    func search(query: String, visibleRegion: MKCoordinateRegion?) async throws -> [MapPlace] {
        [MapPlace(id:"ui-test-hotel",name:"Test Hotel Khao Sok",category:"Hotel",placeName:"Khao Sok",
                  address:"62 Khlong Sok, Phanom",latitude:8.91,longitude:98.53,
                  phone:nil,websiteURL:URL(string:"https://example.com"))]
    }
}
