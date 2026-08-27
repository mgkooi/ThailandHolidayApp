import Foundation

struct Trip: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let country: String
    let startDate: Date
    let endDate: Date
    let travelers: Int
    let timeZoneIdentifier: String
    let destinations: [Destination]
    var flights: [Flight]
    var accommodations: [Accommodation]
    var activities: [Activity]
    var transfers: [Transfer]
    var ferries: [Ferry]
    var trains: [TrainTrip]
    var restaurants: [RestaurantReservation]
    var rentalVehicles: [RentalVehicleBooking]
    var otherItems: [TripEvent]
    let transportItems: [TransportItem]
    let tripDays: [TripDay]
    let bookingLinks: [BookingLink]

    enum CodingKeys: String, CodingKey {
        case id, name, country, startDate, endDate, travelers, timeZoneIdentifier
        case destinations, flights, accommodations, activities, transfers, ferries, trains
        case restaurants, rentalVehicles, otherItems, transportItems, tripDays, bookingLinks
    }

    private enum LegacyCodingKeys: String, CodingKey { case rentalCars }

    init(
        id: UUID,
        name: String,
        country: String,
        startDate: Date,
        endDate: Date,
        travelers: Int,
        timeZoneIdentifier: String,
        destinations: [Destination],
        flights: [Flight],
        accommodations: [Accommodation],
        activities: [Activity],
        transfers: [Transfer] = [],
        ferries: [Ferry] = [],
        trains: [TrainTrip] = [],
        restaurants: [RestaurantReservation] = [],
        rentalVehicles: [RentalVehicleBooking] = [],
        otherItems: [TripEvent] = [],
        transportItems: [TransportItem],
        tripDays: [TripDay],
        bookingLinks: [BookingLink]
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.startDate = startDate
        self.endDate = endDate
        self.travelers = travelers
        self.timeZoneIdentifier = timeZoneIdentifier
        self.destinations = destinations
        self.flights = flights
        self.accommodations = accommodations
        self.activities = activities
        self.transfers = transfers
        self.ferries = ferries
        self.trains = trains
        self.restaurants = restaurants
        self.rentalVehicles = rentalVehicles
        self.otherItems = otherItems
        self.transportItems = transportItems
        self.tripDays = tripDays
        self.bookingLinks = bookingLinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        travelers = try container.decode(Int.self, forKey: .travelers)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        destinations = try container.decode([Destination].self, forKey: .destinations)
        flights = try container.decodeIfPresent([Flight].self, forKey: .flights) ?? []
        accommodations = try container.decodeIfPresent([Accommodation].self, forKey: .accommodations) ?? []
        activities = try container.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        transfers = try container.decodeIfPresent([Transfer].self, forKey: .transfers) ?? []
        ferries = try container.decodeIfPresent([Ferry].self, forKey: .ferries) ?? []
        trains = try container.decodeIfPresent([TrainTrip].self, forKey: .trains) ?? []
        restaurants = try container.decodeIfPresent([RestaurantReservation].self, forKey: .restaurants) ?? []
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        var decodedRentalVehicles = try container.decodeIfPresent([RentalVehicleBooking].self, forKey: .rentalVehicles)
            ?? legacyContainer.decodeIfPresent([RentalVehicleBooking].self, forKey: .rentalCars)
            ?? []
        let decodedOtherItems = try container.decodeIfPresent([TripEvent].self, forKey: .otherItems) ?? []
        let decodedTransportItems = try container.decodeIfPresent([TransportItem].self, forKey: .transportItems) ?? []
        let knownRentalIDs = Set(decodedRentalVehicles.map(\.id))
        decodedRentalVehicles += decodedTransportItems.filter { $0.type == .rentalVehicle && !knownRentalIDs.contains($0.id) }.map {
                RentalVehicleBooking(id: $0.id, vehicleType: .car, company: $0.provider,
                    pickupDate: $0.departureDate, pickupTime: $0.departureDate, pickupLocation: $0.origin,
                    dropoffDate: $0.arrivalDate, dropoffTime: $0.arrivalDate, dropoffLocation: $0.destination,
                    vehicleDescription: nil, bookingReference: $0.referenceNumber, renterName: nil,
                    notes: $0.notes, url: $0.bookingURL, attachmentFilename: nil)
            }
        let migratedRentalIDs = Set(decodedRentalVehicles.map(\.id))
        decodedRentalVehicles += decodedOtherItems.filter {
            $0.title.localizedCaseInsensitiveContains("auto ophalen") && !migratedRentalIDs.contains($0.id)
        }.map {
                RentalVehicleBooking(id: $0.id, vehicleType: .car, company: nil,
                    pickupDate: $0.date, pickupTime: $0.startTime, pickupLocation: $0.location ?? "",
                    dropoffDate: nil, dropoffTime: nil, dropoffLocation: nil, vehicleDescription: nil,
                    bookingReference: nil, renterName: nil, notes: $0.notes, url: $0.url,
                    attachmentFilename: $0.attachmentFilename)
            }
        rentalVehicles = decodedRentalVehicles
        otherItems = decodedOtherItems.filter { !$0.title.localizedCaseInsensitiveContains("auto ophalen") }
        transportItems = decodedTransportItems.filter { $0.type != .rentalVehicle }
        tripDays = try container.decodeIfPresent([TripDay].self, forKey: .tripDays) ?? []
        bookingLinks = try container.decodeIfPresent([BookingLink].self, forKey: .bookingLinks) ?? []
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TripCalendar.thailandTimeZone
    }

    var travelersCount: Int { travelers }

    func contains(_ date: Date) -> Bool {
        let calendar = TripCalendar.calendar(in: timeZone)
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: effectiveStartDate)
            && day <= calendar.startOfDay(for: effectiveEndDate)
    }

    /// Persisted trip dates remain useful metadata, while itinerary data can expand the visible range.
    var effectiveStartDate: Date {
        ([startDate] + itineraryBoundaryDates).min() ?? startDate
    }

    var effectiveEndDate: Date {
        ([endDate] + itineraryBoundaryDates).max() ?? endDate
    }

    private var itineraryBoundaryDates: [Date] {
        var dates = flights.flatMap { [$0.date, $0.departureTime, $0.arrivalDateTime(in: timeZone)] }
        dates.append(contentsOf: accommodations.flatMap { [$0.checkIn, $0.checkOut] })
        dates.append(contentsOf: activities.flatMap { [$0.date, $0.startTime] + [$0.endTime].compactMap { $0 } })
        dates.append(contentsOf: transfers.flatMap { [$0.date, $0.startTime] + [$0.endTime].compactMap { $0 } })
        dates.append(contentsOf: ferries.flatMap { [$0.date, $0.departureTime] + [$0.arrivalTime].compactMap { $0 } })
        dates.append(contentsOf: trains.flatMap { [$0.date, $0.departureTime] + [$0.arrivalTime].compactMap { $0 } })
        dates.append(contentsOf: restaurants.flatMap { [$0.date, $0.time] })
        dates.append(contentsOf: rentalVehicles.flatMap { [$0.pickupDate] + [$0.pickupTime, $0.dropoffDate, $0.dropoffTime].compactMap { $0 } })
        dates.append(contentsOf: otherItems.flatMap { [$0.date] + [$0.startTime, $0.endTime].compactMap { $0 } })
        dates.append(contentsOf: transportItems.flatMap { [$0.departureDate] + [$0.arrivalDate].compactMap { $0 } })
        return dates
    }
}

extension Trip {
    static func empty(name: String, country: String, startDate: Date, endDate: Date,
                      timeZone: TimeZone = .current) -> Trip {
        Trip(id: UUID(), name: name, country: country, startDate: startDate, endDate: endDate,
             travelers: 1, timeZoneIdentifier: timeZone.identifier, destinations: [], flights: [],
             accommodations: [], activities: [], transfers: [], ferries: [], trains: [], restaurants: [],
             rentalVehicles: [], otherItems: [], transportItems: [], tripDays: [], bookingLinks: [])
    }

    func updatingMetadata(name: String, country: String, startDate: Date, endDate: Date,
                          travelers: Int? = nil) -> Trip {
        Trip(id: id, name: name, country: country, startDate: startDate, endDate: endDate,
             travelers: travelers ?? self.travelers, timeZoneIdentifier: timeZoneIdentifier, destinations: destinations,
             flights: flights, accommodations: accommodations, activities: activities, transfers: transfers,
             ferries: ferries, trains: trains, restaurants: restaurants, rentalVehicles: rentalVehicles,
             otherItems: otherItems, transportItems: transportItems, tripDays: tripDays, bookingLinks: bookingLinks)
    }
}

struct TripLocation: Codable, Equatable, Sendable {
    var placeName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var googlePlaceID: String? = nil

    var hasUsableLocation: Bool {
        (latitude != nil && longitude != nil)
            || address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || placeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

struct Destination: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let country: String
    let region: String
    let arrivalDate: Date
    let departureDate: Date
    let latitude: Double
    let longitude: Double
    let description: String?
    let imageReference: String?
    let notes: String?
}

struct Flight: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let airline: String
    let flightNumber: String
    let originAirport: String
    let destinationAirport: String
    let departureTime: Date
    let arrivalDate: Date
    let arrivalTime: Date
    var departureAirport: AirportInfo? = nil
    var arrivalAirport: AirportInfo? = nil
    var bookingReference: String? = nil
    let aircraft: String?
    let cabin: String?
    var notes: String? = nil
    var bookingURL: URL? = nil
    var attachmentFilename: String? = nil
    var media: [TripMedia]? = nil
    var presentationMedia: TripMedia? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, airline, flightNumber, originAirport, destinationAirport
        case departureTime, arrivalDate, arrivalTime, departureAirport, arrivalAirport, bookingReference
        case aircraft, cabin, notes, bookingURL, attachmentFilename, media, presentationMedia
    }

    init(id: UUID, date: Date, airline: String, flightNumber: String, originAirport: String,
         destinationAirport: String, departureTime: Date, arrivalDate: Date? = nil, arrivalTime: Date,
         departureAirport: AirportInfo? = nil, arrivalAirport: AirportInfo? = nil,
         bookingReference: String? = nil, aircraft: String?, cabin: String?, notes: String? = nil, bookingURL: URL? = nil,
         attachmentFilename: String? = nil, media: [TripMedia]? = nil,
         presentationMedia: TripMedia? = nil) {
        self.id = id; self.date = date; self.airline = airline; self.flightNumber = flightNumber
        self.originAirport = originAirport; self.destinationAirport = destinationAirport
        self.departureTime = departureTime; self.arrivalDate = arrivalDate ?? date; self.arrivalTime = arrivalTime
        self.departureAirport = departureAirport; self.arrivalAirport = arrivalAirport; self.bookingReference = bookingReference
        self.aircraft = aircraft; self.cabin = cabin; self.notes = notes
        self.bookingURL = bookingURL; self.attachmentFilename = attachmentFilename
        self.media = media
        self.presentationMedia = presentationMedia
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        airline = try container.decode(String.self, forKey: .airline)
        flightNumber = try container.decode(String.self, forKey: .flightNumber)
        originAirport = try container.decode(String.self, forKey: .originAirport)
        destinationAirport = try container.decode(String.self, forKey: .destinationAirport)
        departureTime = try container.decode(Date.self, forKey: .departureTime)
        arrivalDate = try container.decodeIfPresent(Date.self, forKey: .arrivalDate) ?? date
        arrivalTime = try container.decode(Date.self, forKey: .arrivalTime)
        departureAirport = try container.decodeIfPresent(AirportInfo.self, forKey: .departureAirport)
        arrivalAirport = try container.decodeIfPresent(AirportInfo.self, forKey: .arrivalAirport)
        bookingReference = try container.decodeIfPresent(String.self, forKey: .bookingReference)
        aircraft = try container.decodeIfPresent(String.self, forKey: .aircraft)
        cabin = try container.decodeIfPresent(String.self, forKey: .cabin)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        bookingURL = try container.decodeIfPresent(URL.self, forKey: .bookingURL)
        attachmentFilename = try container.decodeIfPresent(String.self, forKey: .attachmentFilename)
        media = try container.decodeIfPresent([TripMedia].self, forKey: .media)
        presentationMedia = try container.decodeIfPresent(TripMedia.self, forKey: .presentationMedia)
    }

    func arrivalDateTime(in timeZone: TimeZone) -> Date {
        TripCalendar.calendar(in: timeZone).combining(day: arrivalDate, time: arrivalTime)
    }
}

enum AccommodationType: String, Codable, Equatable {
    case hotel
    case resort
    case treehouse
    case guesthouse
    case other
}

struct Accommodation: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: AccommodationType
    let destinationID: UUID?
    var placeName: String? = nil
    let checkIn: Date
    let checkOut: Date
    let address: String
    let latitude: Double?
    let longitude: Double?
    let roomDescription: String
    let bookingReference: String?
    let websiteURL: URL?
    let bookingURL: URL?
    let phoneNumber: String?
    var notes: String? = nil
    var attachmentFilename: String? = nil
    var media: [TripMedia]? = nil
    var presentationMedia: TripMedia? = nil
    var googlePlaceID: String? = nil

    var destinationId: UUID? { destinationID }
    var location: TripLocation {
        TripLocation(placeName: placeName, address: address.nilIfBlank, latitude: latitude, longitude: longitude,
                     googlePlaceID: googlePlaceID)
    }
    var checkInDate: Date { checkIn }
    var checkOutDate: Date { checkOut }
    var roomType: String { roomDescription }
    var legacyNotes: String? { bookingReference }

    func numberOfNights(in timeZone: TimeZone) -> Int {
        let calendar = TripCalendar.calendar(in: timeZone)
        return max(0, calendar.dateComponents([.day], from: checkIn, to: checkOut).day ?? 0)
    }

}

enum TransferType: String, Codable, CaseIterable, Equatable {
    case taxi, privateTransfer, shuttle, rideshare, bus, other

    var title: String {
        switch self {
        case .taxi: "Taxi"
        case .privateTransfer: "Privétransfer"
        case .shuttle: "Shuttle"
        case .rideshare: "Rideshare"
        case .bus: "Bus"
        case .other: "Overig"
        }
    }
}

struct Transfer: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var startTime: Date
    var endTime: Date?
    var type: TransferType
    var provider: String
    var origin: String
    var destination: String
    var bookingReference: String?
    var notes: String?
    var url: URL?
    var attachmentFilename: String?
}

struct Ferry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var operatorName: String
    var departureLocation: String
    var arrivalLocation: String
    var departureTime: Date
    var arrivalTime: Date?
    var bookingReference: String?
    var notes: String?
    var url: URL?
    var attachmentFilename: String?
}

struct TrainTrip: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var operatorName: String
    var trainNumber: String
    var originStation: String
    var destinationStation: String
    var departureTime: Date
    var arrivalTime: Date?
    var carriage: String?
    var seat: String?
    var notes: String?
    var url: URL?
    var attachmentFilename: String?
    var bookingReference: String? = nil
}

struct RestaurantReservation: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var time: Date
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var reservationName: String?
    var reservationReference: String?
    var notes: String?
    var url: URL?
    var attachmentFilename: String?

    var location: TripLocation {
        TripLocation(placeName: name, address: address, latitude: latitude, longitude: longitude)
    }
}

struct TripEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var startTime: Date?
    var endTime: Date?
    var title: String
    var location: String?
    var notes: String?
    var url: URL?
    var attachmentFilename: String?
}

enum RentalVehicleType: String, Codable, CaseIterable, Equatable {
    case car, scooter, motorcycle, bicycle, eBike, quad, other

    var title: String {
        switch self {
        case .car: "Auto"
        case .scooter: "Scooter"
        case .motorcycle: "Motor"
        case .bicycle: "Fiets"
        case .eBike: "E-bike"
        case .quad: "Quad"
        case .other: "Vervoer"
        }
    }

    var symbolName: String {
        switch self {
        case .car: "car.fill"
        case .scooter, .motorcycle: "motorcycle.fill"
        case .bicycle, .eBike: "bicycle"
        case .quad: "car.side.fill"
        case .other: "key.fill"
        }
    }
}

struct RentalVehicleBooking: Identifiable, Codable, Equatable {
    let id: UUID
    var vehicleType: RentalVehicleType
    var company: String?
    var pickupDate: Date
    var pickupTime: Date?
    var pickupLocation: String
    var dropoffDate: Date?
    var dropoffTime: Date?
    var dropoffLocation: String?
    var vehicleDescription: String?
    var bookingReference: String?
    var renterName: String?
    var notes: String?
    var url: URL?
    var attachmentFilename: String?
}

struct Activity: Identifiable, Codable, Equatable {
    let id: UUID
    let destinationId: UUID?
    let date: Date
    let startTime: Date
    let endTime: Date?
    let title: String
    let category: String
    let description: String?
    var location: TripLocation? = nil
    let latitude: Double?
    let longitude: Double?
    let websiteURL: URL?
    let bookingURL: URL?
    let notes: String?
    let url: URL?
    let attachmentFilename: String?
    var isFavorite: Bool
    var isCompleted: Bool
    var bookingReference: String? = nil
    var media: [TripMedia]? = nil
    var presentationMedia: TripMedia? = nil

    func updating(
        destinationId: UUID?? = nil,
        title: String? = nil,
        date: Date? = nil,
        startTime: Date? = nil,
        endTime: Date?? = nil,
        category: String? = nil,
        description: String?? = nil,
        notes: String?? = nil,
        url: URL?? = nil,
        attachmentFilename: String?? = nil,
        isFavorite: Bool? = nil,
        isCompleted: Bool? = nil
    ) -> Activity {
        Activity(
            id: id,
            destinationId: destinationId ?? self.destinationId,
            date: date ?? self.date,
            startTime: startTime ?? self.startTime,
            endTime: endTime ?? self.endTime,
            title: title ?? self.title,
            category: category ?? self.category,
            description: description ?? self.description,
            location: location,
            latitude: latitude,
            longitude: longitude,
            websiteURL: websiteURL,
            bookingURL: bookingURL,
            notes: notes ?? self.notes,
            url: url ?? self.url,
            attachmentFilename: attachmentFilename ?? self.attachmentFilename,
            isFavorite: isFavorite ?? self.isFavorite,
            isCompleted: isCompleted ?? self.isCompleted,
            bookingReference: bookingReference,
            media: media,
            presentationMedia: presentationMedia
        )
    }
}

enum TransportType: String, Codable, Equatable {
    case flight
    case ferry
    case train
    case bus
    case taxi
    case privateTransfer
    case rentalVehicle
    case other

    var title: String {
        switch self {
        case .flight: "Vlucht"
        case .ferry: "Veerboot"
        case .train: "Trein"
        case .bus: "Bus"
        case .taxi: "Taxi"
        case .privateTransfer: "Privétransfer"
        case .rentalVehicle: "Huur vervoer"
        case .other: "Vervoer"
        }
    }

    var symbolName: String {
        switch self {
        case .flight: "airplane"
        case .ferry: "ferry"
        case .train: "tram.fill"
        case .bus, .privateTransfer: "bus.fill"
        case .taxi, .rentalVehicle: "car.fill"
        case .other: "arrow.triangle.swap"
        }
    }
}

struct TransportItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: TransportType
    let provider: String?
    let referenceNumber: String?
    let departureDate: Date
    let arrivalDate: Date?
    let origin: String
    let destination: String
    let durationMinutes: Int?
    let bookingURL: URL?
    let notes: String?
    let flightNumber: String?
    let departureAirportCode: String?
    let arrivalAirportCode: String?
    let terminal: String?
    let aircraft: String?
    let travelClass: String?

    var duration: TimeInterval? {
        if let durationMinutes { return TimeInterval(durationMinutes * 60) }
        guard let arrivalDate else { return nil }
        return arrivalDate.timeIntervalSince(departureDate)
    }
}

struct TripDay: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let destinationID: UUID
    let accommodationID: UUID?
    let itineraryItems: [ItineraryItem]
    let notes: String?

    var sortedItinerary: [ItineraryItem] {
        itineraryItems.sorted { $0.startDate < $1.startDate }
    }
}

enum ItineraryCategory: String, Codable, Equatable, CaseIterable {
    case travel
    case accommodation
    case activity
    case viewpoint
    case restaurant
    case freeTime
    case shopping
    case other

    var title: String {
        switch self {
        case .travel: "Reis"
        case .accommodation: "Verblijf"
        case .activity: "Activiteit"
        case .viewpoint: "Viewpoint"
        case .restaurant: "Restaurant"
        case .freeTime: "Vrije tijd"
        case .shopping: "Winkelen"
        case .other: "Overig"
        }
    }

    var symbolName: String {
        switch self {
        case .travel: "car.fill"
        case .accommodation: "bed.double.fill"
        case .activity: "figure.hiking"
        case .viewpoint: "binoculars.fill"
        case .restaurant: "fork.knife"
        case .freeTime: "sparkles"
        case .shopping: "bag.fill"
        case .other: "calendar"
        }
    }
}

enum ItineraryStatus: String, Codable, Equatable {
    case planned
    case current
    case completed
    case cancelled

    var title: String {
        switch self {
        case .planned: "Gepland"
        case .current: "Nu"
        case .completed: "Afgerond"
        case .cancelled: "Geannuleerd"
        }
    }
}

struct ItineraryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let title: String
    let category: ItineraryCategory
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let description: String?
    let url: URL?
    let status: ItineraryStatus
}

enum BookingLinkType: String, Codable, Equatable {
    case hotel
    case airline
    case ferry
    case booking
    case maps
    case website
    case other
}

struct BookingLink: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let url: URL
    let type: BookingLinkType
}

enum OpeningStatus: String, Codable, Equatable {
    case open
    case closed
    case unknown
}

struct NearbySuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let externalProvider: String
    let externalID: String
    let name: String
    let category: String
    let rating: Double
    let reviewCount: Int
    let latitude: Double
    let longitude: Double
    let distanceMeters: Int
    let priceLevel: Int?
    let openingStatus: OpeningStatus?
    let websiteURL: URL?
    let mapsURL: URL?
}

struct Favorite: Identifiable, Codable, Equatable {
    let id: UUID
    let suggestionID: UUID?
    let externalProvider: String?
    let externalID: String?
    let name: String
    let category: String
    let latitude: Double
    let longitude: Double
    let websiteURL: URL?
    let mapsURL: URL?
    let savedAt: Date
}

struct TripDataPackage: Codable, Equatable {
    let trip: Trip
    let nearbySuggestions: [NearbySuggestion]
    let favorites: [Favorite]
}

/// Versioned application-level persistence root. Trips remain self-contained so an
/// itinerary item can never accidentally leak into another trip.
struct TravelLibrary: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var trips: [Trip]
    var selectedTripId: UUID?
    var nearbySuggestions: [NearbySuggestion]
    var favorites: [Favorite]

    init(schemaVersion: Int = Self.currentSchemaVersion, trips: [Trip], selectedTripId: UUID?,
         nearbySuggestions: [NearbySuggestion] = [], favorites: [Favorite] = []) {
        self.schemaVersion = schemaVersion
        self.trips = trips
        self.selectedTripId = selectedTripId
        self.nearbySuggestions = nearbySuggestions
        self.favorites = favorites
        repairSelection()
    }

    mutating func repairSelection() {
        if let selectedTripId, trips.contains(where: { $0.id == selectedTripId }) { return }
        selectedTripId = trips.first?.id
    }
}
