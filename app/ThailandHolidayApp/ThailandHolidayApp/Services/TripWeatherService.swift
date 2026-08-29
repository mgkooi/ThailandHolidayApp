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
    var precipitationChance: Double? = nil
}

struct TripDayWeather: Equatable, Sendable {
    let date: Date
    let highTemperatureCelsius: Double
    let lowTemperatureCelsius: Double
    let symbolName: String
    let precipitationChance: Double?
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
    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather]
}

extension TripWeatherProviding {
    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather] { [] }
}

struct AppleTripWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await WeatherKit.WeatherService.shared.weather(for: location, including: .hourly)
        return forecast.map {
            TripHourWeather(
                date: $0.date,
                temperatureCelsius: $0.temperature.converted(to: .celsius).value,
                symbolName: $0.symbolName,
                precipitationChance: $0.precipitationChance
            )
        }
    }

    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await WeatherKit.WeatherService.shared.weather(for: location, including: .daily)
        return forecast.map {
            TripDayWeather(date: $0.date,
                highTemperatureCelsius: $0.highTemperature.converted(to: .celsius).value,
                lowTemperatureCelsius: $0.lowTemperature.converted(to: .celsius).value,
                symbolName: $0.symbolName, precipitationChance: $0.precipitationChance)
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
    let latitudeBucket: Int
    let longitudeBucket: Int
    let day: Date

    init(latitude: Double, longitude: Double, day: Date) {
        latitudeBucket = Int((latitude * 1_000).rounded())
        longitudeBucket = Int((longitude * 1_000).rounded())
        self.day = day
    }
}

enum TripWeatherLocationSource: String, Sendable {
    case accommodationCoordinates
    case plannedItem
    case currentLocation
    case destination
    case accommodationGeocode
}

struct TripWeatherLocation: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let source: TripWeatherLocationSource
}

enum TripWeatherLocationSelector {
    static func select(accommodation: Accommodation?, plannedItems: [ManagedTripItem],
                       currentLocation: SearchLocation?, destination: Destination?) -> TripWeatherLocation? {
        if let accommodation, let latitude = accommodation.latitude, let longitude = accommodation.longitude {
            return TripWeatherLocation(name: accommodation.placeName ?? accommodation.name,
                latitude: latitude, longitude: longitude, source: .accommodationCoordinates)
        }
        for item in TodayItemSorter.sorted(plannedItems) {
            guard let target = item.navigationTarget,
                  let latitude = target.location.latitude, let longitude = target.location.longitude else { continue }
            return TripWeatherLocation(name: target.name, latitude: latitude, longitude: longitude, source: .plannedItem)
        }
        if let currentLocation {
            return TripWeatherLocation(name: currentLocation.name, latitude: currentLocation.latitude,
                longitude: currentLocation.longitude, source: .currentLocation)
        }
        if let destination {
            return TripWeatherLocation(name: destination.name, latitude: destination.latitude,
                longitude: destination.longitude, source: .destination)
        }
        return nil
    }
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
        let dailyForecast: TripDayWeather?
        let state: TripWeatherState
        let fetchedAt: Date
    }

    private let provider: any TripWeatherProviding
    private let cacheLifetime: TimeInterval
    private var cache: [TripWeatherCacheKey: CacheEntry] = [:]
    private var activeKey: TripWeatherCacheKey?

    private(set) var hourlyForecast: [TripHourWeather] = []
    private(set) var dailyForecast: TripDayWeather?
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
        location: TripWeatherLocation,
        date: Date,
        timeZone: TimeZone,
        force: Bool = false,
        now: Date = .now
    ) async {
        let calendar = TripCalendar.calendar(in: timeZone)
        let day = calendar.startOfDay(for: date)
        let key = TripWeatherCacheKey(latitude: location.latitude, longitude: location.longitude, day: day)

        if !force, let cached = cache[key], now.timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            apply(cached, key: key)
            return
        }
        if activeKey == key, state == .loading { return }

        activeKey = key
        hourlyForecast = []
        dailyForecast = nil
        state = .loading
#if DEBUG
        Self.logger.debug("Weather location source=\(location.source.rawValue, privacy: .public) lat=\(location.latitude, format: .fixed(precision: 2), privacy: .public) lon=\(location.longitude, format: .fixed(precision: 2), privacy: .public) date=\(day, privacy: .public); request started")
#endif

        do {
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let available = try await provider.hourlyWeather(latitude: location.latitude, longitude: location.longitude)
            let availableDays = isToday ? [] : try await provider.dailyWeather(latitude: location.latitude, longitude: location.longitude)
            guard !Task.isCancelled, activeKey == key else { return }
            let selected = isToday
                ? TripWeatherSelector.selectCurrent(from: available, now: now, timeZone: timeZone)
                : TripWeatherSelector.select(from: available, for: date, timeZone: timeZone)
            dailyForecast = availableDays.first { calendar.isDate($0.date, inSameDayAs: date) }
            let resultingState: TripWeatherState = (!selected.isEmpty || dailyForecast != nil) ? .available : .unavailable
            let entry = CacheEntry(forecast: selected, dailyForecast: dailyForecast,
                                   state: resultingState, fetchedAt: now)
            cache[key] = entry
            apply(entry, key: key)
#if DEBUG
            Self.logger.debug("WeatherKit request succeeded state=\(String(describing: resultingState), privacy: .public)")
#endif
        } catch is CancellationError {
            return
        } catch {
            guard activeKey == key else { return }
            hourlyForecast = []
            dailyForecast = nil
            state = .failed
            Self.logger.error("WeatherKit request failed category=\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    func refresh(destination: Destination, date: Date, timeZone: TimeZone,
                 force: Bool = false, now: Date = .now) async {
        await refresh(location: TripWeatherLocation(name: destination.name, latitude: destination.latitude,
            longitude: destination.longitude, source: .destination), date: date, timeZone: timeZone,
            force: force, now: now)
    }

    private func apply(_ entry: CacheEntry, key: TripWeatherCacheKey) {
        activeKey = key
        hourlyForecast = entry.forecast
        dailyForecast = entry.dailyForecast
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

    static func selectCurrent(from forecast: [TripHourWeather], now: Date,
                              timeZone: TimeZone) -> [TripHourWeather] {
        let calendar = TripCalendar.calendar(in: timeZone)
        return forecast
            .filter { calendar.isDate($0.date, inSameDayAs: now) && $0.date >= now.addingTimeInterval(-30 * 60) }
            .sorted { $0.date < $1.date }
            .prefix(4)
            .map { $0 }
    }

    static func celsiusText(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}
