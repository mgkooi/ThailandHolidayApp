import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct MapPlace: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: String?
    let placeName: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let phone: String?
    let websiteURL: URL?
    let googlePlaceID: String?

    var location: TripLocation {
        TripLocation(placeName: placeName ?? name, address: address, latitude: latitude, longitude: longitude)
    }

    init(id: String, name: String, category: String? = nil, placeName: String? = nil, address: String? = nil,
         latitude: Double, longitude: Double, phone: String? = nil, websiteURL: URL? = nil,
         googlePlaceID: String? = nil) {
        self.id=id; self.name=name; self.category=category; self.placeName=placeName; self.address=address
        self.latitude=latitude; self.longitude=longitude; self.phone=phone; self.websiteURL=websiteURL
        self.googlePlaceID=googlePlaceID
    }

    @MainActor init(mapItem: MKMapItem) {
        let coordinate = mapItem.location.coordinate
        let locality = mapItem.placemark.locality ?? mapItem.placemark.subAdministrativeArea
            ?? mapItem.placemark.administrativeArea ?? mapItem.placemark.country
        let address = mapItem.address?.fullAddress
        let name = mapItem.name ?? locality ?? "Locatie"
        self.init(id: "\(coordinate.latitude)-\(coordinate.longitude)-\(name)", name: name,
                  category: mapItem.pointOfInterestCategory?.rawValue, placeName: locality, address: address,
                  latitude: coordinate.latitude, longitude: coordinate.longitude,
                  phone: mapItem.phoneNumber, websiteURL: mapItem.url)
    }
}

@MainActor protocol NativeMapFeatureResolving {
    func place(for feature: MapFeature) async throws -> MapPlace
}

@MainActor struct NativeMapFeatureResolver: NativeMapFeatureResolving {
    func place(for feature: MapFeature) async throws -> MapPlace {
        let item = try await MKMapItemRequest(feature: feature).mapItem
        return MapPlace(mapItem: item)
    }
}

enum MapPlaceRouteRole: String, CaseIterable, Identifiable {
    case origin, destination
    var id: String { rawValue }
    var title: String { self == .origin ? "Vertrek- of ophaallocatie" : "Bestemming of aankomstlocatie" }
}
