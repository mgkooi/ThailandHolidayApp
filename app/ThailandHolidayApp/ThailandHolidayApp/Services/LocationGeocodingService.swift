import Foundation
import MapKit
import OSLog
import SwiftUI

struct Coordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

protocol LocationGeocoding {
    func geocode(address: String) async throws -> Coordinate?
}

struct AddressCoordinateResolver {
    let geocoder: any LocationGeocoding

    func resolve(
        address: String,
        originalAddress: String,
        existingCoordinate: Coordinate?
    ) async -> Coordinate? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        guard address != originalAddress.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return existingCoordinate
        }
        return try? await geocoder.geocode(address: address)
    }
}

struct LocationGeocodingService: LocationGeocoding {
    private static let logger = Logger(subsystem: "nl.martijnkooi.ThailandHolidayApp", category: "Geocoding")

    func geocode(address: String) async throws -> Coordinate? {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        guard let request = MKGeocodingRequest(addressString: query) else { return nil }
        let candidates = try await request.mapItems
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard let best = candidates.max(by: { score($0, query: normalizedQuery) < score($1, query: normalizedQuery) }) else {
            return nil
        }
        let coordinate = best.location.coordinate
#if DEBUG
        Self.logger.debug("Geocode query=\(query, privacy: .public) locality=\(best.placemark.locality ?? "-", privacy: .public) country=\(best.placemark.country ?? "-", privacy: .public) latitude=\(coordinate.latitude, privacy: .public) longitude=\(coordinate.longitude, privacy: .public)")
#endif
        return Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func score(_ item: MKMapItem, query: String) -> Int {
        let locality = (item.placemark.locality ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let name = (item.name ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let country = (item.placemark.country ?? "").lowercased()
        var value = locality == query ? 100 : (name == query ? 80 : 0)
        if locality.contains(query) || query.contains(locality) && !locality.isEmpty { value += 30 }
        if query == "bangkok" && (country == "thailand" || country == "thailandia") { value += 100 }
        return value
    }
}

struct UITestLocationGeocodingService: LocationGeocoding {
    func geocode(address: String) async throws -> Coordinate? {
        Coordinate(latitude: 13.7563, longitude: 100.5018)
    }
}

private struct LocationGeocoderKey: EnvironmentKey {
    static let defaultValue: any LocationGeocoding = LocationGeocodingService()
}

extension EnvironmentValues {
    var locationGeocoder: any LocationGeocoding {
        get { self[LocationGeocoderKey.self] }
        set { self[LocationGeocoderKey.self] = newValue }
    }
}
