import Foundation

enum UITestConfiguration {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }

    static var documentsDirectory: URL? {
        guard isEnabled else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("ThailandHolidayApp-UITests", isDirectory: true)
    }

    static var selectedDate: Date? {
        guard isEnabled else { return nil }
        if ProcessInfo.processInfo.arguments.contains("--ui-weather-out-of-range")
            || ProcessInfo.processInfo.arguments.contains("--ui-weather-no-data") {
            return TripCalendar.date(2026, 9, 9, hour: 12)
        }
        return TripCalendar.date(2026, 9, 6, hour: 12)
    }

    static var weatherNow: Date? {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--ui-weather-no-data") else { return nil }
        return TripCalendar.date(2026, 9, 9, hour: 12)
    }

    static func resetDocumentsIfRequested() {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
              let directory = documentsDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        ["discovery.maxDistance", "discovery.minimumRating", "discovery.minimumReviews", "discovery.openNow"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

struct UITestWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] { [] }
    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather] { [] }
}
