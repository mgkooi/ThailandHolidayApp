import Foundation

enum TripCalendar {
    static let thailandTimeZone = TimeZone(identifier: "Asia/Bangkok")!

    static func calendar(in timeZone: TimeZone = thailandTimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0,
        in timeZone: TimeZone = thailandTimeZone
    ) -> Date {
        calendar(in: timeZone).date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

struct TripResolver {
    let trip: Trip

    private var calendar: Calendar {
        TripCalendar.calendar(in: trip.timeZone)
    }

    func tripDay(on date: Date) -> TripDay? {
        trip.tripDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func currentDestination(on date: Date) -> Destination? {
        guard let destinationID = tripDay(on: date)?.destinationID else { return nil }
        return trip.destinations.first { $0.id == destinationID }
    }

    func currentAccommodation(on date: Date) -> Accommodation? {
        if let accommodationID = tripDay(on: date)?.accommodationID {
            return trip.accommodations.first { $0.id == accommodationID }
        }

        return trip.accommodations.first {
            date >= $0.checkIn && date < $0.checkOut
        }
    }

    func nextTransport(after date: Date) -> TransportItem? {
        trip.transportItems
            .filter { $0.departureDate >= date }
            .min { $0.departureDate < $1.departureDate }
    }
}
