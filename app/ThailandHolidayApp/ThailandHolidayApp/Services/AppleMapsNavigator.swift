import MapKit
import SwiftUI

@MainActor protocol MapOpening {
    func navigate(to location: TripLocation, name: String?) async -> Bool
    func openPlace(_ location: TripLocation, name: String?) async -> Bool
}

enum MapLocationResolution: Equatable {
    case coordinate(Double, Double)
    case address(String)
    case placeName(String)
    case unavailable
}

struct MapLocationResolver {
    func resolution(for location: TripLocation) -> MapLocationResolution {
        if let latitude = location.latitude, let longitude = location.longitude {
            return .coordinate(latitude, longitude)
        }
        if let address = location.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            return .address(address)
        }
        if let placeName = location.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !placeName.isEmpty {
            return .placeName(placeName)
        }
        return .unavailable
    }
}

@MainActor
struct AppleMapsNavigator: MapOpening {
    @discardableResult
    func open(_ location: TripLocation, name: String? = nil) async -> Bool {
        await navigate(to: location, name: name)
    }

    @discardableResult
    func navigate(to location: TripLocation, name: String? = nil) async -> Bool {
        guard let mapItem = await mapItem(for: location, name: name) else { return false }
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        return true
    }

    @discardableResult
    func openPlace(_ location: TripLocation, name: String? = nil) async -> Bool {
        guard let mapItem = await mapItem(for: location, name: name) else { return false }
        mapItem.openInMaps(launchOptions: nil)
        return true
    }

    private func mapItem(for location: TripLocation, name: String?) async -> MKMapItem? {
        let mapItem: MKMapItem?
        switch MapLocationResolver().resolution(for: location) {
        case .coordinate(let latitude, let longitude):
            mapItem = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        case .address(let query), .placeName(let query):
            mapItem = try? await MKGeocodingRequest(addressString: query)?.mapItems.first
        case .unavailable:
            return nil
        }
        guard let mapItem else { return nil }
        if let name { mapItem.name = name }
        return mapItem
    }
}

private struct MapOpeningKey: EnvironmentKey {
    static let defaultValue: any MapOpening = AppleMapsNavigator()
}

extension EnvironmentValues {
    var mapOpening: any MapOpening {
        get { self[MapOpeningKey.self] }
        set { self[MapOpeningKey.self] = newValue }
    }
}

@MainActor
struct DiscoveryMapActions {
    let opener: any MapOpening
    func discover(_ result: DiscoveryResult) async {
        _ = await opener.openPlace(result.location, name: result.name)
    }
    func navigate(_ result: DiscoveryResult) async {
        _ = await opener.navigate(to: result.location, name: result.name)
    }
}
