import CoreLocation
import Foundation
import Observation
import WeatherKit
import os

struct TripHourWeather: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let temperatureCelsius: Double
    let symbolName: String
}

enum TripWeatherState: Equatable {
    case idle
    case loading
    case available
    case unavailable
    case failed
}

protocol TripWeatherProviding: Sendable {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather]
}

struct AppleTripWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await WeatherKit.WeatherService.shared.weather(for: location, including: .hourly)
        return forecast.map {
            TripHourWeather(
                date: $0.date,
                temperatureCelsius: $0.temperature.converted(to: .celsius).value,
                symbolName: $0.symbolName
            )
        }
    }
}

/// Default provider for builds whose signing team does not support WeatherKit.
/// It deliberately performs no WeatherKit request, so these builds do not need
/// the WeatherKit entitlement at runtime.
struct UnavailableTripWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] {
        []
    }
}

struct TripWeatherCacheKey: Hashable, Sendable {
    let destinationID: UUID
    let day: Date
}

@MainActor
@Observable
final class TripWeatherService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ThailandHolidayApp",
        category: "Weather"
    )

    private struct CacheEntry {
        let forecast: [TripHourWeather]
        let state: TripWeatherState
        let fetchedAt: Date
    }

    private let provider: any TripWeatherProviding
    private let cacheLifetime: TimeInterval
    private var cache: [TripWeatherCacheKey: CacheEntry] = [:]
    private var activeKey: TripWeatherCacheKey?

    private(set) var hourlyForecast: [TripHourWeather] = []
    private(set) var state: TripWeatherState = .idle

    var isLoading: Bool { state == .loading }
    var errorMessage: String? { state == .failed ? "Weer tijdelijk niet beschikbaar" : nil }

    init(cacheLifetime: TimeInterval = 30 * 60) {
#if WEATHERKIT_ENABLED
        provider = AppleTripWeatherProvider()
#else
        provider = UnavailableTripWeatherProvider()
#endif
        self.cacheLifetime = cacheLifetime
    }

    init(provider: any TripWeatherProviding, cacheLifetime: TimeInterval = 30 * 60) {
        self.provider = provider
        self.cacheLifetime = cacheLifetime
    }

    func refresh(
        destination: Destination,
        date: Date,
        timeZone: TimeZone,
        force: Bool = false,
        now: Date = .now
    ) async {
        let calendar = TripCalendar.calendar(in: timeZone)
        let key = TripWeatherCacheKey(destinationID: destination.id, day: calendar.startOfDay(for: date))

        if !force, let cached = cache[key], now.timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            apply(cached, key: key)
            return
        }
        if activeKey == key, state == .loading { return }

        activeKey = key
        hourlyForecast = []
        state = .loading

        do {
            let available = try await provider.hourlyWeather(
                latitude: destination.latitude,
                longitude: destination.longitude
            )
            guard !Task.isCancelled, activeKey == key else { return }
            let selected = TripWeatherSelector.select(from: available, for: date, timeZone: timeZone)
            let resultingState: TripWeatherState = selected.count == TripWeatherSelector.requestedHours.count
                ? .available
                : .unavailable
            let entry = CacheEntry(forecast: selected, state: resultingState, fetchedAt: now)
            cache[key] = entry
            apply(entry, key: key)
        } catch is CancellationError {
            return
        } catch {
            guard activeKey == key else { return }
            hourlyForecast = []
            state = .failed
            Self.logger.error("WeatherKit request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ entry: CacheEntry, key: TripWeatherCacheKey) {
        activeKey = key
        hourlyForecast = entry.forecast
        state = entry.state
    }
}

enum TripWeatherSelector {
    static let requestedHours = [8, 12, 16, 20]

    static func select(
        from forecast: [TripHourWeather],
        for date: Date,
        timeZone: TimeZone
    ) -> [TripHourWeather] {
        let calendar = TripCalendar.calendar(in: timeZone)
        let day = calendar.startOfDay(for: date)

        return requestedHours.compactMap { hour in
            guard let target = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
            return forecast
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
                .flatMap { abs($0.date.timeIntervalSince(target)) <= 90 * 60 ? $0 : nil }
        }
    }

    static func celsiusText(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}
