import SwiftUI

struct WeatherCard: View {
    let destinationName: String
    let forecast: [TripHourWeather]
    let dailyForecast: TripDayWeather?
    let state: TripWeatherState
    let errorCategory: WeatherErrorCategory?
    let errorDetails: WeatherErrorDetails?
    let timeZone: TimeZone

    private var diagnosticsEnabled: Bool {
#if DEBUG
        true
#else
        Bundle.main.object(forInfoDictionaryKey: "WeatherDiagnosticsEnabled") as? Bool == true
#endif
    }

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
                if let dailyForecast {
                    precipitation(dailyForecast.precipitationChance)
                } else { HStack(spacing: 8) {
                    ForEach(forecast) { hour in
                        VStack(spacing: 9) {
                            Text(AppFormatters.time(in: timeZone).string(from: hour.date))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: hour.symbolName)
                                .font(.title3)
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 24)
                            Text(TripWeatherSelector.celsiusText(hour.temperatureCelsius))
                                .font(.headline.monospacedDigit())
                            precipitation(hour.precipitationChance)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } }
            case .unavailable:
                diagnosticText
            case .failed:
                diagnosticText
            }
        }
        .padding(14)
        .background(Color.reizzCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .travelCardShadow()
        .accessibilityElement(children: .contain)
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
        if let dailyForecast { return "\(TripWeatherSelector.celsiusText(dailyForecast.highTemperatureCelsius))" }
        if let current = forecast.first { return TripWeatherSelector.celsiusText(current.temperatureCelsius) }
        if errorCategory == .dateOutOfRange { return "Nog geen weersverwachting beschikbaar voor deze datum" }
        if state == .failed { return "Weer tijdelijk niet beschikbaar" }
        if state == .unavailable { return "Nog geen weersverwachting beschikbaar" }
        return "Weer laden…"
    }

    @ViewBuilder private var diagnosticText: some View {
        if diagnosticsEnabled, let errorCategory {
            Text("Diagnose: \(errorCategory.rawValue)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("weatherDiagnosis")
            if let errorDetails {
                Text("Code: \(errorDetails.compactCode)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityIdentifier("weatherDiagnosticCode")
            }
        }
    }
}
