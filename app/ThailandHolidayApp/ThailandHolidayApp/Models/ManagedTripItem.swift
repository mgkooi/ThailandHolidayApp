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
    var supportsMedia: Bool { self == .flight || self == .accommodation || self == .activity }

    var showsGenericDate: Bool {
        switch self {
        case .restaurant, .activity, .other: true
        case .flight, .accommodation, .transfer, .ferry, .train, .rentalVehicle: false
        }
    }
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
        case .restaurant(let value): (value.location, value.name)
        case .activity(let value): (value.location ?? TripLocation(placeName: value.title,
            address: nil, latitude: value.latitude, longitude: value.longitude), value.title)
        case .other(let value): value.location.map {
            (TripLocation(placeName: $0, address: $0, latitude: nil, longitude: nil), value.title)
        }
        default: nil
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
        default: []
        }
    }

    func replacingMedia(_ media: [TripMedia]) -> ManagedTripItem {
        switch self {
        case .flight(var value): value.media = media; return .flight(value)
        case .accommodation(var value): value.media = media; return .accommodation(value)
        case .activity(var value): value.media = media; return .activity(value)
        default: return self
        }
    }

    var presentationMedia: TripMedia? {
        switch self {
        case .flight(let value): value.presentationMedia
        case .accommodation(let value): value.presentationMedia
        case .activity(let value): value.presentationMedia
        default: nil
        }
    }

    func replacingPresentationMedia(_ media: TripMedia?) -> ManagedTripItem {
        switch self {
        case .flight(var value): value.presentationMedia = media; return .flight(value)
        case .accommodation(var value): value.presentationMedia = media; return .accommodation(value)
        case .activity(var value): value.presentationMedia = media; return .activity(value)
        default: return self
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
