import Foundation

enum TravelDurationFormatter {
    static func duration(from departure: Date?, to arrival: Date?) -> TimeInterval? {
        guard let departure, let arrival, arrival >= departure else { return nil }
        return arrival.timeIntervalSince(departure)
    }

    static func string(from departure: Date?, to arrival: Date?) -> String? {
        guard let interval = duration(from: departure, to: arrival) else { return nil }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)u" }
        return "\(hours)u \(minutes)m"
    }
}
