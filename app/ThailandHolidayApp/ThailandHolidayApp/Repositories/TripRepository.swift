import Foundation

protocol TripRepository {
    func loadPackage() throws -> TripDataPackage
    func currentTrip() throws -> Trip
    func tripDay(on date: Date) throws -> TripDay?
    func currentDestination(on date: Date) throws -> Destination?
    func currentAccommodation(on date: Date) throws -> Accommodation?
    func nextTransport(after date: Date) throws -> TransportItem?
}

enum TripRepositoryError: Error, Equatable {
    case resourceNotFound
    case tripDayHasUnknownDestination
}

enum TripJSONCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

struct TodayDashboardData {
    let trip: Trip
    let tripDay: TripDay
    let destination: Destination
    let accommodation: Accommodation?
    let nextTransport: TransportItem?
    let nearbySuggestions: [NearbySuggestion]
}
