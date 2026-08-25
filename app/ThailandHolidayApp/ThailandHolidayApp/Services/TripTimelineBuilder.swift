import Foundation

struct TripTimelineBuilder {
    let trip: Trip

    private var calendar: Calendar {
        TripCalendar.calendar(in: trip.timeZone)
    }

    func items() -> [TimelineItem] {
        let combined = flightItems() + accommodationItems() + activityItems() + transportItems()
            + transferItems() + ferryItems() + trainItems() + restaurantItems() + otherItems()
            + rentalVehicleItems()
        return combined.sorted(by: isOrderedBefore)
    }

    func sections() -> [TimelineDaySection] {
        let grouped = Dictionary(grouping: items()) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            TimelineDaySection(day: day, items: grouped[day] ?? [])
        }
    }

    private func flightItems() -> [TimelineItem] {
        trip.flights.map { flight in
            let provider = [flight.airline, flight.flightNumber]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return TimelineItem(
                id: "flight-\(flight.id.uuidString)",
                date: flight.departureTime,
                startDate: flight.departureTime,
                endDate: flight.arrivalDateTime(in: trip.timeZone),
                type: .flight,
                title: "\(flight.originAirport) → \(flight.destinationAirport)",
                subtitle: provider.nilIfEmpty,
                detail: [flight.aircraft, TravelDurationFormatter.string(from: flight.departureTime,
                    to: flight.arrivalDateTime(in: trip.timeZone))].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                source: .flight(flight.id),
                isFavorite: false,
                isCompleted: false,
                stableOrder: 10
            )
        }
    }

    private func accommodationItems() -> [TimelineItem] {
        trip.accommodations.flatMap { accommodation in
            let stay = "\(AppFormatters.shortDate(in: trip.timeZone).string(from: accommodation.checkIn)) – \(AppFormatters.shortDate(in: trip.timeZone).string(from: accommodation.checkOut))"
            let detail = [accommodation.roomDescription, stay]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return [
                TimelineItem(
                    id: "accommodation-\(accommodation.id.uuidString)-checkin",
                    date: accommodation.checkIn,
                    startDate: explicitTime(for: accommodation.checkIn),
                    endDate: nil,
                    type: .accommodation,
                    title: "Check-in",
                    subtitle: accommodation.name,
                    detail: detail,
                    source: .accommodation(accommodation.id, event: .checkIn),
                    isFavorite: false,
                    isCompleted: false,
                    stableOrder: 30
                ),
                TimelineItem(
                    id: "accommodation-\(accommodation.id.uuidString)-checkout",
                    date: accommodation.checkOut,
                    startDate: explicitTime(for: accommodation.checkOut),
                    endDate: nil,
                    type: .accommodation,
                    title: "Check-out",
                    subtitle: accommodation.name,
                    detail: accommodation.roomDescription.nilIfEmpty,
                    source: .accommodation(accommodation.id, event: .checkOut),
                    isFavorite: false,
                    isCompleted: false,
                    stableOrder: 20
                )
            ]
        }
    }

    private func activityItems() -> [TimelineItem] {
        trip.activities.map { activity in
            let category = ItineraryCategory(rawValue: activity.category)
            let type: TimelineItemType = category == .restaurant ? .restaurant : .activity
            return TimelineItem(
                id: "activity-\(activity.id.uuidString)",
                date: activity.startTime,
                startDate: activity.startTime,
                endDate: activity.endTime,
                type: type,
                title: activity.title,
                subtitle: category?.title,
                detail: activity.description ?? activity.notes,
                source: .activity(activity.id),
                isFavorite: activity.isFavorite,
                isCompleted: activity.isCompleted,
                stableOrder: 40
            )
        }
    }

    private func transportItems() -> [TimelineItem] {
        trip.transportItems.map { transport in
            TimelineItem(
                id: "transport-\(transport.id.uuidString)",
                date: transport.departureDate,
                startDate: transport.departureDate,
                endDate: transport.arrivalDate,
                type: timelineType(for: transport.type),
                title: "\(transport.origin) → \(transport.destination)",
                subtitle: [transport.provider, transport.referenceNumber]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                    .nilIfEmpty,
                detail: transport.notes,
                source: .transport(transport.id),
                isFavorite: false,
                isCompleted: false,
                stableOrder: 15
            )
        }
    }

    private func transferItems() -> [TimelineItem] {
        trip.transfers.map {
            TimelineItem(id: "transfer-\($0.id)", date: $0.startTime, startDate: $0.startTime, endDate: $0.endTime,
                type: .transfer, title: "\($0.origin) → \($0.destination)",
                subtitle: [$0.type.title, $0.provider].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
                detail: [$0.notes, TravelDurationFormatter.string(from: $0.startTime, to: $0.endTime)]
                    .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                source: .transfer($0.id), isFavorite: false, isCompleted: false, stableOrder: 15)
        }
    }

    private func ferryItems() -> [TimelineItem] {
        trip.ferries.map {
            TimelineItem(id: "ferry-\($0.id)", date: $0.departureTime, startDate: $0.departureTime, endDate: $0.arrivalTime,
                type: .ferry, title: "\($0.departureLocation) → \($0.arrivalLocation)", subtitle: $0.operatorName.nilIfEmpty,
                detail: [$0.notes, TravelDurationFormatter.string(from: $0.departureTime, to: $0.arrivalTime)]
                    .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                source: .ferry($0.id), isFavorite: false, isCompleted: false, stableOrder: 15)
        }
    }

    private func trainItems() -> [TimelineItem] {
        trip.trains.map {
            TimelineItem(id: "train-\($0.id)", date: $0.departureTime, startDate: $0.departureTime, endDate: $0.arrivalTime,
                type: .train, title: "\($0.originStation) → \($0.destinationStation)",
                subtitle: [$0.operatorName, $0.trainNumber].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
                detail: [$0.notes, TravelDurationFormatter.string(from: $0.departureTime, to: $0.arrivalTime)]
                    .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                source: .train($0.id), isFavorite: false, isCompleted: false, stableOrder: 15)
        }
    }

    private func restaurantItems() -> [TimelineItem] {
        trip.restaurants.map {
            TimelineItem(id: "restaurant-\($0.id)", date: $0.time, startDate: $0.time, endDate: nil,
                type: .restaurant, title: $0.name, subtitle: $0.reservationReference, detail: $0.address ?? $0.notes,
                source: .restaurant($0.id), isFavorite: false, isCompleted: false, stableOrder: 40)
        }
    }

    private func rentalVehicleItems() -> [TimelineItem] {
        trip.rentalVehicles.flatMap { booking in
            var result = [TimelineItem(
                id: "rental-\(booking.id)-pickup",
                date: booking.pickupTime ?? booking.pickupDate,
                startDate: booking.pickupTime,
                endDate: nil,
                type: .rentalVehicle,
                title: "\(booking.vehicleType.title) ophalen",
                subtitle: booking.pickupLocation,
                detail: booking.company,
                source: .rentalVehicle(booking.id, event: .pickup),
                isFavorite: false,
                isCompleted: false,
                stableOrder: 15
            )]
            if let dropoffDate = booking.dropoffDate {
                result.append(TimelineItem(
                    id: "rental-\(booking.id)-dropoff",
                    date: booking.dropoffTime ?? dropoffDate,
                    startDate: booking.dropoffTime,
                    endDate: nil,
                    type: .rentalVehicle,
                    title: "\(booking.vehicleType.title) inleveren",
                    subtitle: booking.dropoffLocation,
                    detail: booking.company,
                    source: .rentalVehicle(booking.id, event: .dropoff),
                    isFavorite: false,
                    isCompleted: false,
                    stableOrder: 15
                ))
            }
            return result
        }
    }

    private func otherItems() -> [TimelineItem] {
        trip.otherItems.map {
            TimelineItem(id: "other-\($0.id)", date: $0.startTime ?? $0.date, startDate: $0.startTime, endDate: $0.endTime,
                type: .other, title: $0.title, subtitle: $0.location, detail: $0.notes, source: .other($0.id),
                isFavorite: false, isCompleted: false, stableOrder: 50)
        }
    }

    private func isOrderedBefore(_ lhs: TimelineItem, _ rhs: TimelineItem) -> Bool {
        let lhsDay = calendar.startOfDay(for: lhs.date)
        let rhsDay = calendar.startOfDay(for: rhs.date)
        if lhsDay != rhsDay { return lhsDay < rhsDay }

        switch (lhs.startDate, rhs.startDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.stableOrder != rhs.stableOrder { return lhs.stableOrder < rhs.stableOrder }
            return lhs.id < rhs.id
        }
    }

    private func explicitTime(for date: Date) -> Date? {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hasTime = components.hour != 0 || components.minute != 0 || components.second != 0
        return hasTime ? date : nil
    }

    private func timelineType(for type: TransportType) -> TimelineItemType {
        switch type {
        case .flight: .flight
        case .ferry: .ferry
        case .train: .train
        case .taxi, .privateTransfer, .bus, .rentalVehicle: .transfer
        case .other: .other
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
