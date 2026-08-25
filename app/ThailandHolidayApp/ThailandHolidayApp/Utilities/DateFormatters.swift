import Foundation

enum AppFormatters {
    static let dutchDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.timeZone = TripCalendar.thailandTimeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.timeZone = TripCalendar.thailandTimeZone
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.timeZone = TripCalendar.thailandTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func dutchDate(in timeZone: TimeZone) -> DateFormatter {
        formatter(dateFormat: "EEEE d MMMM", timeZone: timeZone)
    }

    static func shortDate(in timeZone: TimeZone) -> DateFormatter {
        formatter(dateFormat: "d MMM", timeZone: timeZone)
    }

    static func time(in timeZone: TimeZone) -> DateFormatter {
        formatter(dateFormat: "HH:mm", timeZone: timeZone)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) uur" : "\(hours) u \(minutes) min"
    }

    static func distance(_ meters: Int) -> String {
        if meters < 1_000 { return "\(meters) m" }
        return String(format: "%.1f km", Double(meters) / 1_000)
            .replacingOccurrences(of: ".", with: ",")
    }

    private static func formatter(dateFormat: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.calendar = TripCalendar.calendar(in: timeZone)
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }
}
