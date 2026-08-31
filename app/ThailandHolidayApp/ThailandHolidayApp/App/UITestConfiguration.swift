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
            || ProcessInfo.processInfo.arguments.contains("--ui-weather-no-data")
            || ProcessInfo.processInfo.arguments.contains("--ui-weather-error-code")
            || ProcessInfo.processInfo.arguments.contains("--ui-weather-today") {
            return TripCalendar.date(2026, 9, 9, hour: 12)
        }
        return TripCalendar.date(2026, 9, 6, hour: 12)
    }

    static var weatherNow: Date? {
        guard isEnabled else { return nil }
        if ProcessInfo.processInfo.arguments.contains("--ui-weather-out-of-range") {
            return TripCalendar.date(2026, 8, 30, hour: 12)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-weather-today") {
            return TripCalendar.date(2026, 9, 9, hour: 14)
        }
        guard ProcessInfo.processInfo.arguments.contains("--ui-weather-no-data")
                || ProcessInfo.processInfo.arguments.contains("--ui-weather-error-code") else { return nil }
        return TripCalendar.date(2026, 9, 9, hour: 12)
    }

    static func resetDocumentsIfRequested() {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
              let directory = documentsDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        ["discovery.maxDistance", "discovery.minimumRating", "discovery.minimumReviews", "discovery.openNow",
         AppAppearance.storageKey]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

struct UITestWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] {
        if ProcessInfo.processInfo.arguments.contains("--ui-weather-error-code") {
            throw NSError(domain: "WeatherKit.WeatherError", code: 2)
        }
        guard ProcessInfo.processInfo.arguments.contains("--ui-weather-today") else { return [] }
        return TripWeatherSelector.requestedHours.map { hour in
            TripHourWeather(date: TripCalendar.date(2026, 9, 9, hour: hour),
                            temperatureCelsius: Double(18 + hour / 2),
                            symbolName: hour == 20 ? "moon.stars.fill" : "cloud.sun.fill",
                            precipitationChance: hour == 16 ? 0.3 : nil)
        }
    }
    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather] { [] }
}
