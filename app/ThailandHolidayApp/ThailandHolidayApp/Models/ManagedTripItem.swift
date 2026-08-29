import Foundation

enum TripItemKind: String, CaseIterable, Identifiable {
    case flight, accommodation, transfer, ferry, train, rentalVehicle, restaurant, activity, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: "Vlucht"
        case .accommodation: "Accommodatie"
        case .transfer: "Transfer / taxi"
        case .ferry: "Boot / ferry"
        case .train: "Trein"
        case .rentalVehicle: "Huur vervoer"
        case .restaurant: "Restaurant"
        case .activity: "Activiteit"
        case .other: "Overig"
        }
    }

    var symbolName: String {
        switch self {
        case .flight: "airplane"
        case .accommodation: "bed.double.fill"
        case .transfer: "car.fill"
        case .ferry: "ferry.fill"
        case .train: "tram.fill"
        case .rentalVehicle: "key.fill"
        case .restaurant: "fork.knife"
        case .activity: "figure.walk"
        case .other: "mappin.and.ellipse"
        }
    }
}

extension TripItemKind {
    var supportsMedia: Bool { true }

    var showsGenericDate: Bool {
        switch self {
        case .restaurant, .activity, .other: true
        case .flight, .accommodation, .transfer, .ferry, .train, .rentalVehicle: false
        }
    }
}

enum TodaySortPriority: Int, Sendable {
    case transport = 0
    case accommodation = 1
    case activity = 2
    case restaurant = 3
    case other = 4
}

enum ManagedTripItem: Identifiable, Equatable {
    case flight(Flight)
    case accommodation(Accommodation)
    case transfer(Transfer)
    case ferry(Ferry)
    case train(TrainTrip)
    case rentalVehicle(RentalVehicleBooking)
    case restaurant(RestaurantReservation)
    case activity(Activity)
    case other(TripEvent)

    var id: UUID {
        switch self {
        case .flight(let value): value.id
        case .accommodation(let value): value.id
        case .transfer(let value): value.id
        case .ferry(let value): value.id
        case .train(let value): value.id
        case .rentalVehicle(let value): value.id
        case .restaurant(let value): value.id
        case .activity(let value): value.id
        case .other(let value): value.id
        }
    }

    var kind: TripItemKind {
        switch self {
        case .flight: .flight
        case .accommodation: .accommodation
        case .transfer: .transfer
        case .ferry: .ferry
        case .train: .train
        case .rentalVehicle: .rentalVehicle
        case .restaurant: .restaurant
        case .activity: .activity
        case .other: .other
        }
    }

    var todaySortPriority: TodaySortPriority {
        switch self {
        case .flight, .transfer, .ferry, .train, .rentalVehicle: .transport
        case .accommodation: .accommodation
        case .activity: .activity
        case .restaurant: .restaurant
        case .other: .other
        }
    }

    var todayStartDate: Date? {
        switch self {
        case .flight(let value): value.departureTime
        case .accommodation(let value): value.checkIn
        case .transfer(let value): value.startTime
        case .ferry(let value): value.departureTime
        case .train(let value): value.departureTime
        case .rentalVehicle(let value): value.pickupTime
        case .restaurant(let value): value.time
        case .activity(let value): value.startTime
        case .other(let value): value.startTime
        }
    }

    var attachmentFilename: String? {
        switch self {
        case .flight(let value): value.attachmentFilename
        case .accommodation(let value): value.attachmentFilename
        case .transfer(let value): value.attachmentFilename
        case .ferry(let value): value.attachmentFilename
        case .train(let value): value.attachmentFilename
        case .rentalVehicle(let value): value.attachmentFilename
        case .restaurant(let value): value.attachmentFilename
        case .activity(let value): value.attachmentFilename
        case .other(let value): value.attachmentFilename
        }
    }

    var navigationTarget: (location: TripLocation, name: String)? {
        switch self {
        case .accommodation(let value): (value.location, value.name)
        case .flight(let value): value.departureAirport.map { ($0.location, value.originAirport) }
            ?? (TripLocation(placeName: value.originAirport), value.originAirport)
        case .transfer(let value): (TripLocation(placeName: value.origin), value.origin)
        case .ferry(let value): (TripLocation(placeName: value.departureLocation), value.departureLocation)
        case .train(let value): (TripLocation(placeName: value.originStation), value.originStation)
        case .rentalVehicle(let value): (TripLocation(placeName: value.pickupLocation), value.pickupLocation)
        case .restaurant(let value): (value.location, value.name)
        case .activity(let value): (value.location ?? TripLocation(placeName: value.title,
            address: nil, latitude: value.latitude, longitude: value.longitude), value.title)
        case .other(let value): value.location.map {
            (TripLocation(placeName: $0, address: $0, latitude: nil, longitude: nil), value.title)
        }
        }
    }

    func replacingAttachment(with filename: String?) -> ManagedTripItem {
        switch self {
        case .flight(var value): value.attachmentFilename = filename; return .flight(value)
        case .accommodation(var value): value.attachmentFilename = filename; return .accommodation(value)
        case .transfer(var value): value.attachmentFilename = filename; return .transfer(value)
        case .ferry(var value): value.attachmentFilename = filename; return .ferry(value)
        case .train(var value): value.attachmentFilename = filename; return .train(value)
        case .rentalVehicle(var value): value.attachmentFilename = filename; return .rentalVehicle(value)
        case .restaurant(var value): value.attachmentFilename = filename; return .restaurant(value)
        case .activity(let value): return .activity(value.updating(attachmentFilename: .some(filename)))
        case .other(var value): value.attachmentFilename = filename; return .other(value)
        }
    }

    var mediaItems: [TripMedia] {
        switch self {
        case .flight(let value): value.mediaItems
        case .accommodation(let value): value.mediaItems
        case .activity(let value): value.mediaItems
        case .transfer(let value): value.mediaItems
        case .ferry(let value): value.mediaItems
        case .train(let value): value.mediaItems
        case .rentalVehicle(let value): value.mediaItems
        case .restaurant(let value): value.mediaItems
        case .other(let value): value.mediaItems
        }
    }

    func replacingMedia(_ media: [TripMedia]) -> ManagedTripItem {
        switch self {
        case .flight(var value): value.media = media; return .flight(value)
        case .accommodation(var value): value.media = media; return .accommodation(value)
        case .activity(var value): value.media = media; return .activity(value)
        case .transfer(var value): value.media = media; return .transfer(value)
        case .ferry(var value): value.media = media; return .ferry(value)
        case .train(var value): value.media = media; return .train(value)
        case .rentalVehicle(var value): value.media = media; return .rentalVehicle(value)
        case .restaurant(var value): value.media = media; return .restaurant(value)
        case .other(var value): value.media = media; return .other(value)
        }
    }

    var presentationMedia: TripMedia? {
        switch self {
        case .flight(let value): value.presentationMedia
        case .accommodation(let value): value.presentationMedia
        case .activity(let value): value.presentationMedia
        case .transfer(let value): value.presentationMedia
        case .ferry(let value): value.presentationMedia
        case .train(let value): value.presentationMedia
        case .rentalVehicle(let value): value.presentationMedia
        case .restaurant(let value): value.presentationMedia
        case .other(let value): value.presentationMedia
        }
    }

    func replacingPresentationMedia(_ media: TripMedia?) -> ManagedTripItem {
        switch self {
        case .flight(var value): value.presentationMedia = media; return .flight(value)
        case .accommodation(var value): value.presentationMedia = media; return .accommodation(value)
        case .activity(var value): value.presentationMedia = media; return .activity(value)
        case .transfer(var value): value.presentationMedia = media; return .transfer(value)
        case .ferry(var value): value.presentationMedia = media; return .ferry(value)
        case .train(var value): value.presentationMedia = media; return .train(value)
        case .rentalVehicle(var value): value.presentationMedia = media; return .rentalVehicle(value)
        case .restaurant(var value): value.presentationMedia = media; return .restaurant(value)
        case .other(var value): value.presentationMedia = media; return .other(value)
        }
    }

    func replacingGooglePlaceID(_ placeID: String?) -> ManagedTripItem {
        switch self {
        case .accommodation(var value): value.googlePlaceID = placeID; return .accommodation(value)
        case .activity(var value):
            if value.location == nil {
                value.location = TripLocation(placeName: value.title, address: nil,
                                              latitude: value.latitude, longitude: value.longitude)
            }
            value.location?.googlePlaceID = placeID
            return .activity(value)
        case .restaurant(var value): value.googlePlaceID = placeID; return .restaurant(value)
        case .other(var value): value.googlePlaceID = placeID; return .other(value)
        default: return self
        }
    }

    func assigningLocalFilename(_ filename: String) -> ManagedTripItem {
        var values = mediaItems
        if values.isEmpty { values = [TripMedia(filename: filename)] }
        else {
            values[values.startIndex].filename = filename
        }
        return replacingMedia(values).replacingAttachment(with: filename)
    }
}

enum TodayItemSorter {
    static func sorted(_ items: [ManagedTripItem]) -> [ManagedTripItem] {
        items.sorted { lhs, rhs in
            if lhs.todaySortPriority != rhs.todaySortPriority {
                return lhs.todaySortPriority.rawValue < rhs.todaySortPriority.rawValue
            }
            switch (lhs.todayStartDate, rhs.todayStartDate) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }
}
