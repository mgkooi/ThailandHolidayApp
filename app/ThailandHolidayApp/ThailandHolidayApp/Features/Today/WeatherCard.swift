import SwiftUI

struct WeatherCard: View {
    let destinationName: String
    let forecast: [TripHourWeather]
    let dailyForecast: TripDayWeather?
    let state: TripWeatherState
    let errorCategory: WeatherErrorCategory?
    let forecastDate: Date
    let showsHourlyForecast: Bool
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: weatherSymbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.reizzBrandForeground)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText).font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(Color.reizzPrimaryText)
                        .accessibilityIdentifier("weatherPrimary")
                    Text(destinationName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Link(" Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            switch state {
            case .loading, .idle:
                ProgressView().controlSize(.small)
            case .available:
                if showsHourlyForecast {
                    hourlySlots
                } else if let dailyForecast {
                    precipitation(dailyForecast.precipitationChance)
                }
            case .unavailable, .failed:
                EmptyView()
            }
        }
        .padding(14)
        .background(Color.reizzCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .travelCardShadow()
        .accessibilityElement(children: .contain)
    }

    private var hourlySlots: some View {
        HStack(spacing: 8) {
            ForEach(TripWeatherSelector.hourlySlots(from: forecast, for: forecastDate, timeZone: timeZone)) { slot in
                VStack(spacing: 7) {
                    Text(String(format: "%02d:00", slot.hour))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let hour = slot.forecast {
                        Image(systemName: hour.symbolName)
                            .font(.title3)
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 24)
                        Text(TripWeatherSelector.celsiusText(hour.temperatureCelsius))
                            .font(.headline.monospacedDigit())
                    } else {
                        Image(systemName: "minus").font(.caption).foregroundStyle(.tertiary).frame(height: 24)
                        Text("–").font(.headline).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: slot))
                .accessibilityIdentifier("weatherHourlySlot.\(slot.hour)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weatherHourlyForecast")
    }

    @ViewBuilder
    private func precipitation(_ chance: Double?) -> some View {
        if let chance {
            Label("\(Int((chance * 100).rounded()))%", systemImage: "drop.fill")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var weatherSymbol: String {
        dailyForecast?.symbolName ?? forecast.first?.symbolName ?? (state == .failed ? "exclamationmark.icloud" : "cloud.sun")
    }

    private var primaryText: String {
        if let dailyForecast {
            return "\(TripWeatherSelector.celsiusText(dailyForecast.lowTemperatureCelsius))–\(TripWeatherSelector.celsiusText(dailyForecast.highTemperatureCelsius))"
        }
        if let current = forecast.first { return TripWeatherSelector.celsiusText(current.temperatureCelsius) }
        if errorCategory == .dateOutOfRange { return "Nog geen weersverwachting beschikbaar voor deze datum" }
        if state == .failed { return "Weer tijdelijk niet beschikbaar" }
        if state == .unavailable { return "Nog geen weersverwachting beschikbaar" }
        return "Weer laden…"
    }

    private func accessibilityLabel(for slot: TripWeatherSelector.HourlySlot) -> String {
        let time = String(format: "%02d:00", slot.hour)
        guard let forecast = slot.forecast else { return "\(time), geen verwachting beschikbaar" }
        return "\(time), \(conditionDescription(for: forecast.symbolName)), \(Int(forecast.temperatureCelsius.rounded())) graden"
    }

    private func conditionDescription(for symbolName: String) -> String {
        if symbolName.contains("thunderstorm") { return "onweer" }
        if symbolName.contains("snow") { return "sneeuw" }
        if symbolName.contains("rain") || symbolName.contains("drizzle") { return "regen" }
        if symbolName.contains("fog") || symbolName.contains("haze") { return "mist" }
        if symbolName.contains("cloud.sun") || symbolName.contains("cloud.moon") { return "half bewolkt" }
        if symbolName.contains("cloud") { return "bewolkt" }
        if symbolName.contains("moon") { return "helder" }
        if symbolName.contains("sun") { return "zonnig" }
        return "weersverwachting"
    }
}
