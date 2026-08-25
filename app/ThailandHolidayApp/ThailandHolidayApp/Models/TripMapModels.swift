import CoreLocation
import Foundation
import MapKit

enum TripMapAnnotationType: String, CaseIterable {
    case accommodation, airport, restaurant, activity, ferry, train, rentalVehicle, transfer, other

    var title: String {
        switch self {
        case .accommodation: "Accommodatie"; case .airport: "Luchthaven"; case .restaurant: "Restaurant"
        case .activity: "Activiteit"; case .ferry: "Ferry"; case .train: "Trein"
        case .rentalVehicle: "Huur vervoer"; case .transfer: "Transfer"; case .other: "Overig"
        }
    }
    var symbolName: String {
        switch self {
        case .accommodation: "bed.double.fill"; case .airport: "airplane"; case .restaurant: "fork.knife"
        case .activity: "figure.walk"; case .ferry: "ferry.fill"; case .train: "train.side.front.car"
        case .rentalVehicle: "car.fill"; case .transfer: "car.side.fill"; case .other: "mappin"
        }
    }
}

struct TripMapAnnotation: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let type: TripMapAnnotationType
    let sourceID: UUID?
    let date: Date?
    let location: TripLocation
}

struct TripMapRegionBuilder {
    static func region(around location: SearchLocation, radiusMeters: CLLocationDistance = 10_000) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                           latitudinalMeters: radiusMeters * 2, longitudinalMeters: radiusMeters * 2)
    }
}

struct TripMapAnnotationBuilder {
    let airportLookup: AirportLookup

    func annotations(for trip: Trip) -> [TripMapAnnotation] {
        var result: [TripMapAnnotation] = []
        for item in trip.accommodations {
            append(&result, id: "hotel-\(item.id)", title: item.name, subtitle: item.placeName,
                   location: item.location, type: .accommodation, sourceID: item.id, date: item.checkIn)
        }
        for flight in trip.flights {
            appendAirport(&result, flight.departureAirport ?? airportLookup.bestMatch(for: flight.originAirport),
                          id: "flight-\(flight.id)-departure", date: flight.departureTime)
            appendAirport(&result, flight.arrivalAirport ?? airportLookup.bestMatch(for: flight.destinationAirport),
                          id: "flight-\(flight.id)-arrival", date: flight.arrivalDateTime(in: trip.timeZone))
        }
        for item in trip.restaurants {
            append(&result, id: "restaurant-\(item.id)", title: item.name, subtitle: item.address,
                   location: item.location, type: .restaurant, sourceID: item.id, date: item.time)
        }
        for item in trip.activities {
            guard let location = item.location else { continue }
            append(&result, id: "activity-\(item.id)", title: item.title, subtitle: location.placeName,
                   location: location, type: .activity, sourceID: item.id, date: item.startTime)
        }
        return result
    }

    private func append(_ result: inout [TripMapAnnotation], id: String, title: String, subtitle: String?,
                        location: TripLocation, type: TripMapAnnotationType, sourceID: UUID?, date: Date?) {
        guard let latitude = location.latitude, let longitude = location.longitude else { return }
        result.append(TripMapAnnotation(id: id, title: title, subtitle: subtitle,
            coordinate: .init(latitude: latitude, longitude: longitude), type: type, sourceID: sourceID,
            date: date, location: location))
    }

    private func appendAirport(_ result: inout [TripMapAnnotation], _ airport: AirportInfo?, id: String, date: Date) {
        guard let airport else { return }
        append(&result, id: id, title: "\(airport.code) · \(airport.name)", subtitle: airport.city,
               location: airport.location, type: .airport, sourceID: nil, date: date)
    }
}
