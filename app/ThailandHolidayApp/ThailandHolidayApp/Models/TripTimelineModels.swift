import Foundation

enum TimelineItemType: String, Equatable, Sendable {
    case flight
    case accommodation
    case activity
    case transfer
    case ferry
    case train
    case rentalVehicle
    case restaurant
    case other

    var title: String {
        switch self {
        case .flight: "Vlucht"
        case .accommodation: "Verblijf"
        case .activity: "Activiteit"
        case .transfer: "Transfer"
        case .ferry: "Veerboot"
        case .train: "Trein"
        case .rentalVehicle: "Huur vervoer"
        case .restaurant: "Restaurant"
        case .other: "Reisitem"
        }
    }

    var symbolName: String {
        switch self {
        case .flight: "airplane"
        case .accommodation: "bed.double.fill"
        case .activity: "figure.walk"
        case .transfer: "car.fill"
        case .ferry: "ferry.fill"
        case .train: "tram.fill"
        case .rentalVehicle: "key.fill"
        case .restaurant: "fork.knife"
        case .other: "mappin.and.ellipse"
        }
    }
}

enum TimelineSource: Equatable, Sendable {
    case flight(UUID)
    case accommodation(UUID, event: AccommodationTimelineEvent)
    case activity(UUID)
    case transport(UUID)
    case transfer(UUID)
    case ferry(UUID)
    case train(UUID)
    case rentalVehicle(UUID, event: RentalVehicleTimelineEvent)
    case restaurant(UUID)
    case other(UUID)
}

enum RentalVehicleTimelineEvent: String, Equatable, Sendable {
    case pickup
    case dropoff
}

enum AccommodationTimelineEvent: String, Equatable, Sendable {
    case checkIn
    case checkOut
}

struct TimelineItem: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let startDate: Date?
    let endDate: Date?
    let type: TimelineItemType
    let title: String
    let subtitle: String?
    let detail: String?
    let source: TimelineSource
    let isFavorite: Bool
    let isCompleted: Bool
    let stableOrder: Int
}

struct TimelineDaySection: Identifiable, Equatable, Sendable {
    let day: Date
    let items: [TimelineItem]

    var id: Date { day }
}
