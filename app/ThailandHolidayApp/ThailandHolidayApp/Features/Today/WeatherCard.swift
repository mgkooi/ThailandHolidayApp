import SwiftUI

struct WeatherCard: View {
    let destinationName: String
    let forecast: [TripHourWeather]
    let dailyForecast: TripDayWeather?
    let state: TripWeatherState
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weer · \(destinationName)", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .foregroundStyle(Color.travelTeal)
                Spacer()
                Link(" Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            switch state {
            case .loading, .idle:
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(minHeight: 70)
            case .available:
                if let dailyForecast {
                    HStack(spacing: 14) {
                        Image(systemName: dailyForecast.symbolName)
                            .font(.title2).symbolRenderingMode(.multicolor)
                        Text("\(TripWeatherSelector.celsiusText(dailyForecast.lowTemperatureCelsius)) – \(TripWeatherSelector.celsiusText(dailyForecast.highTemperatureCelsius))")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        precipitation(dailyForecast.precipitationChance)
                    }
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
                unavailableMessage(
                    title: "Weersverwachting niet beschikbaar",
                    detail: nil
                )
            case .failed:
                unavailableMessage(title: "Weer tijdelijk niet beschikbaar", detail: nil)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
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

    private func unavailableMessage(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }
}
