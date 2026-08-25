import Foundation

struct LocalTripRepository: TripRepository {
    private let dataProvider: () throws -> Data

    init(bundle: Bundle = .main, resourceName: String = "thailand-trip") {
        dataProvider = {
            let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Data")
                ?? bundle.url(forResource: resourceName, withExtension: "json")
            guard let url else { throw TripRepositoryError.resourceNotFound }
            return try Data(contentsOf: url)
        }
    }

    init(data: Data) {
        dataProvider = { data }
    }

    func loadPackage() throws -> TripDataPackage {
        try TripJSONCoding.decoder().decode(TripDataPackage.self, from: dataProvider())
    }

    func currentTrip() throws -> Trip {
        try loadPackage().trip
    }

    func tripDay(on date: Date) throws -> TripDay? {
        TripResolver(trip: try currentTrip()).tripDay(on: date)
    }

    func currentDestination(on date: Date) throws -> Destination? {
        TripResolver(trip: try currentTrip()).currentDestination(on: date)
    }

    func currentAccommodation(on date: Date) throws -> Accommodation? {
        TripResolver(trip: try currentTrip()).currentAccommodation(on: date)
    }

    func nextTransport(after date: Date) throws -> TransportItem? {
        TripResolver(trip: try currentTrip()).nextTransport(after: date)
    }

    func dashboard(on date: Date) throws -> TodayDashboardData? {
        let package = try loadPackage()
        let resolver = TripResolver(trip: package.trip)
        guard let tripDay = resolver.tripDay(on: date) else { return nil }
        guard let destination = package.trip.destinations.first(where: { $0.id == tripDay.destinationID }) else {
            throw TripRepositoryError.tripDayHasUnknownDestination
        }

        return TodayDashboardData(
            trip: package.trip,
            tripDay: tripDay,
            destination: destination,
            accommodation: resolver.currentAccommodation(on: date),
            nextTransport: resolver.nextTransport(after: date),
            nearbySuggestions: package.nearbySuggestions
        )
    }

    func sampleDashboard() throws -> TodayDashboardData {
        let trip = try currentTrip()
        guard let dashboard = try dashboard(on: trip.startDate) else {
            throw TripRepositoryError.tripDayHasUnknownDestination
        }
        return dashboard
    }
}
