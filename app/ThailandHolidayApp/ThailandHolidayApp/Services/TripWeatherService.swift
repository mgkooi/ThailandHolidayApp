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

enum WeatherErrorCategory: String, Equatable, Sendable {
    case notConfigured
    case entitlementMissing
    case authorizationFailed
    case locationUnavailable
    case dateOutOfRange
    case noForecastData
    case network
    case weatherKitServiceError
    case unknown
}

struct TripWeatherProviderError: Error, Sendable {
    let category: WeatherErrorCategory
    let domain: String
    let code: Int

    init(_ category: WeatherErrorCategory, domain: String = "TripWeather", code: Int = 0) {
        self.category = category
        self.domain = domain
        self.code = code
    }
}

struct WeatherErrorDetails: Equatable, Sendable {
    let errorType: String
    let domain: String
    let code: Int
    let weatherErrorCase: String?
    let failureReason: String?
    let recoverySuggestion: String?

    init(error: Error) {
        let nsError = error as NSError
        errorType = String(reflecting: type(of: error))
        domain = nsError.domain
        code = nsError.code
        if let weatherError = error as? WeatherKit.WeatherError {
            weatherErrorCase = switch weatherError {
            case .permissionDenied: "permissionDenied"
            case .unknown: "unknown"
            @unknown default: "futureCase"
            }
        } else {
            weatherErrorCase = nil
        }
        let localized = error as? LocalizedError
        failureReason = Self.safe(localized?.failureReason ?? nsError.localizedFailureReason)
        recoverySuggestion = Self.safe(localized?.recoverySuggestion ?? nsError.localizedRecoverySuggestion)
    }

    var compactCode: String { "\(domain)/\(code)" }

    private static func safe(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 200,
              !value.localizedCaseInsensitiveContains("token"),
              !value.localizedCaseInsensitiveContains("secret"),
              !value.localizedCaseInsensitiveContains("latitude"),
              !value.localizedCaseInsensitiveContains("longitude"),
              !value.localizedCaseInsensitiveContains("location"),
              !value.localizedCaseInsensitiveContains("http") else { return nil }
        return value
    }
}

enum WeatherErrorClassifier {
    static func category(for error: Error) -> WeatherErrorCategory {
        if let error = error as? TripWeatherProviderError { return error.category }
        if let weatherError = error as? WeatherKit.WeatherError {
            return switch weatherError {
            case .permissionDenied: .authorizationFailed
            case .unknown: .weatherKitServiceError
            @unknown default: .weatherKitServiceError
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }

        let domain = nsError.domain.lowercased()
        let description = String(describing: error).lowercased()
        if domain.contains("authenticator") || domain.contains("authentication") { return .authorizationFailed }
        if description.contains("entitlement") { return .entitlementMissing }
        if description.contains("authoriz") || description.contains("permission") { return .authorizationFailed }
        if domain.contains("weather") { return .weatherKitServiceError }
        return .unknown
    }
}

enum TripWeatherAvailability {
    /// WeatherKit's daily forecast represents today plus the following nine days.
    static let forecastDayCount = 10

    static func isWithinForecastHorizon(date: Date, now: Date, timeZone: TimeZone) -> Bool {
        let calendar = TripCalendar.calendar(in: timeZone)
        let requestedDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard let difference = calendar.dateComponents([.day], from: today, to: requestedDay).day else { return false }
        return difference >= 0 && difference < forecastDayCount
    }
}

protocol TripWeatherProviding: Sendable {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather]
    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather]
}

protocol TripWeatherDiagnosticProbing: TripWeatherProviding {
    func currentWeather(latitude: Double, longitude: Double) async throws
}

extension TripWeatherProviding {
    func dailyWeather(latitude: Double, longitude: Double) async throws -> [TripDayWeather] { [] }
}

struct AppleTripWeatherProvider: TripWeatherDiagnosticProbing {
    func currentWeather(latitude: Double, longitude: Double) async throws {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        _ = try await WeatherKit.WeatherService.shared.weather(for: location, including: .current)
    }

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
        throw TripWeatherProviderError(.notConfigured)
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
        let errorCategory: WeatherErrorCategory?
        let fetchedAt: Date
    }

    private let provider: any TripWeatherProviding
    private let cacheLifetime: TimeInterval
    private var cache: [TripWeatherCacheKey: CacheEntry] = [:]
    private var activeKey: TripWeatherCacheKey?

    private(set) var hourlyForecast: [TripHourWeather] = []
    private(set) var dailyForecast: TripDayWeather?
    private(set) var state: TripWeatherState = .idle
    private(set) var errorCategory: WeatherErrorCategory?
    private(set) var errorDetails: WeatherErrorDetails?
    private(set) var diagnosticProbeResults: [String: Bool] = [:]

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
        errorCategory = nil
        errorDetails = nil
        diagnosticProbeResults = [:]
        state = .loading
        Self.logger.info("provider=WeatherKit locationSource=\(location.source.rawValue, privacy: .public) forecastDate=\(day, privacy: .public) request=started")

        guard TripWeatherAvailability.isWithinForecastHorizon(date: date, now: now, timeZone: timeZone) else {
            let entry = CacheEntry(forecast: [], dailyForecast: nil, state: .unavailable,
                                   errorCategory: .dateOutOfRange, fetchedAt: now)
            cache[key] = entry
            apply(entry, key: key)
            Self.logger.notice("provider=WeatherKit request=skipped category=\(WeatherErrorCategory.dateOutOfRange.rawValue, privacy: .public)")
            return
        }

        do {
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let available = try await provider.hourlyWeather(latitude: location.latitude, longitude: location.longitude)
            let availableDays = isToday ? [] : try await provider.dailyWeather(latitude: location.latitude, longitude: location.longitude)
            guard !Task.isCancelled, activeKey == key else { return }
            let selected = isToday
                ? TripWeatherSelector.selectCurrent(from: available, now: now, timeZone: timeZone)
                : TripWeatherSelector.select(from: available, for: date, timeZone: timeZone)
            dailyForecast = availableDays.first { calendar.isDate($0.date, inSameDayAs: date) }
            let hasForecast = !selected.isEmpty || dailyForecast != nil
            let resultingState: TripWeatherState = hasForecast ? .available : .unavailable
            let entry = CacheEntry(forecast: selected, dailyForecast: dailyForecast,
                                   state: resultingState, errorCategory: hasForecast ? nil : .noForecastData,
                                   fetchedAt: now)
            cache[key] = entry
            apply(entry, key: key)
            Self.logger.info("provider=WeatherKit request=succeeded state=\(String(describing: resultingState), privacy: .public) category=\(entry.errorCategory?.rawValue ?? "none", privacy: .public)")
        } catch is CancellationError {
            return
        } catch {
            guard activeKey == key else { return }
            hourlyForecast = []
            dailyForecast = nil
            let details = WeatherErrorDetails(error: error)
            errorDetails = details
            errorCategory = WeatherErrorClassifier.category(for: error)
            state = .failed
            Self.logger.error("provider=WeatherKit request=failed category=\(self.errorCategory?.rawValue ?? "unknown", privacy: .public) errorType=\(details.errorType, privacy: .public) domain=\(details.domain, privacy: .public) code=\(details.code, privacy: .public) weatherError=\(details.weatherErrorCase ?? "none", privacy: .public) failureReason=\(details.failureReason ?? "none", privacy: .public) recoverySuggestion=\(details.recoverySuggestion ?? "none", privacy: .public)")
            await runDiagnosticProbes(location: location)
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
        errorCategory = entry.errorCategory
        errorDetails = nil
        diagnosticProbeResults = [:]
    }

    private func runDiagnosticProbes(location: TripWeatherLocation) async {
        guard diagnosticsEnabled, let diagnosticProvider = provider as? any TripWeatherDiagnosticProbing else { return }
        await probe("current") { try await diagnosticProvider.currentWeather(
            latitude: location.latitude, longitude: location.longitude) }
        await probe("hourly") { _ = try await diagnosticProvider.hourlyWeather(
            latitude: location.latitude, longitude: location.longitude) }
        await probe("daily") { _ = try await diagnosticProvider.dailyWeather(
            latitude: location.latitude, longitude: location.longitude) }
    }

    private func probe(_ dataset: String, request: () async throws -> Void) async {
        do {
            try await request()
            diagnosticProbeResults[dataset] = true
            Self.logger.info("provider=WeatherKit diagnosticDataset=\(dataset, privacy: .public) result=succeeded")
        } catch {
            let details = WeatherErrorDetails(error: error)
            diagnosticProbeResults[dataset] = false
            Self.logger.error("provider=WeatherKit diagnosticDataset=\(dataset, privacy: .public) result=failed errorType=\(details.errorType, privacy: .public) domain=\(details.domain, privacy: .public) code=\(details.code, privacy: .public) weatherError=\(details.weatherErrorCase ?? "none", privacy: .public)")
        }
    }

    private var diagnosticsEnabled: Bool {
#if DEBUG
        true
#else
        Bundle.main.object(forInfoDictionaryKey: "WeatherDiagnosticsEnabled") as? Bool == true
#endif
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
