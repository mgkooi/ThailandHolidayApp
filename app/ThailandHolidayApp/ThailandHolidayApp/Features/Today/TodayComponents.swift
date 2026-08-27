import SwiftUI

struct TodayHeader: View {
    let date: Date
    let locationName: String?
    let timeZone: TimeZone
    let canGoToPreviousDay: Bool
    let canGoToNextDay: Bool
    let previousDayAction: () -> Void
    let nextDayAction: () -> Void
    let dateAction: () -> Void
    let locationAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Vandaag")
                .font(.largeTitle.bold())
            HStack(spacing: 12) {
                dateNavigationButton(
                    symbol: "chevron.left",
                    label: "Vorige reisdag",
                    isEnabled: canGoToPreviousDay,
                    action: previousDayAction
                )
                Spacer()
                Button(action: dateAction) {
                    Text(AppFormatters.dutchDate(in: timeZone).string(from: date).capitalized)
                        .font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .accessibilityLabel("Kies datum")
                Spacer()
                dateNavigationButton(
                    symbol: "chevron.right",
                    label: "Volgende reisdag",
                    isEnabled: canGoToNextDay,
                    action: nextDayAction
                )
            }
            if let locationName {
                Button(action: locationAction) {
                    HStack(spacing: 5) {
                        Label(locationName, systemImage: "location.fill")
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.travelTeal)
                }
                .accessibilityLabel("Open \(locationName) op kaart")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
    }

    private func dateNavigationButton(
        symbol: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.travelTeal : Color.secondary.opacity(0.35))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

struct TripStatusCard: View {
    @Environment(\.openURL) private var openURL

    let destination: Destination?
    let accommodation: Accommodation
    let timeZone: TimeZone
    var coverAction: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("JE VERBLIJF")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(accommodation.placeName ?? destination?.name ?? accommodation.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "leaf.fill")
                    .font(.title2)
                    .foregroundStyle(Color.travelSun)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(accommodation.name, systemImage: "bed.double.fill")
                    .font(.headline)
                Text(accommodation.roomDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)

            HStack(spacing: 16) {
                Label(dateRange, systemImage: "calendar")
                Label(nightsText, systemImage: "moon.stars.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 10) {
                if accommodation.location.hasUsableLocation {
                    Button {
                        Task { await AppleMapsNavigator().open(accommodation.location, name: accommodation.name) }
                    } label: {
                        Label("Navigeer", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TravelCardButtonStyle())
                }

                if let detailsURL = accommodation.websiteURL ?? accommodation.bookingURL {
                    Button {
                        openURL(detailsURL)
                    } label: {
                        Text("Hotel details")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TravelCardButtonStyle())
                }
                NavigationLink { TripItemEditorView(kind: .accommodation, itemID: accommodation.id) } label: {
                    Text("Details").frame(maxWidth: .infinity)
                }.buttonStyle(TravelCardButtonStyle())
                Button(action: coverAction) { Text("Omslag").frame(maxWidth: .infinity) }
                    .buttonStyle(TravelCardButtonStyle())
            }
        }
        .padding(20)
        .frame(minHeight: accommodation.presentationMedia == nil ? 0 : 220, alignment: .bottom)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(Color.travelTeal)
            if accommodation.presentationMedia != nil {
                TripMediaImage(media: accommodation.presentationMedia).scaledToFill()
                LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .travelCardShadow()
        .accessibilityElement(children: .contain)
    }

    private var dateRange: String {
        "\(AppFormatters.shortDate.string(from: accommodation.checkIn)) – \(AppFormatters.shortDate.string(from: accommodation.checkOut))"
    }

    private var nightsText: String {
        let count = accommodation.numberOfNights(in: timeZone)
        return count == 1 ? "1 nacht" : "\(count) nachten"
    }
}

struct QuickActionsView: View {
    @Environment(\.openURL) private var openURL

    let accommodation: Accommodation?
    let hasFlights: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let accommodation, accommodation.location.hasUsableLocation {
                QuickActionButton(title: "Route", symbol: "location.fill", tint: .travelCoral) {
                    Task { await AppleMapsNavigator().open(accommodation.location, name: accommodation.name) }
                }
            }
            QuickActionButton(title: "Hotel", symbol: "bed.double.fill", tint: .travelGreen) {
                if let url = accommodation?.websiteURL ?? accommodation?.bookingURL { openURL(url) }
            }
            QuickActionButton(title: "Vervoer", symbol: hasFlights ? "airplane" : "car.fill", tint: .travelTeal) { }
            QuickActionButton(title: "Ontdek", symbol: "sparkles", tint: .travelOrange) { }
        }
    }
}

struct TodayDiscoveryCard: View {
    let result: DiscoveryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(result.name).font(.headline).lineLimit(2)
            if let distance = result.distanceMeters {
                Label(DiscoveryDistanceFormatter.string(meters: distance), systemImage: "location")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let address = result.address {
                Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(14)
        .frame(width: 210, alignment: .topLeading)
        .frame(minHeight: 110, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .travelCardShadow()
    }
}

struct FlightCard: View {
    let flight: Flight
    let timeZone: TimeZone
    var coverAction: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Vlucht", systemImage: "airplane")
                    .font(.headline)
                    .foregroundStyle(Color.travelCoral)
                Spacer()
                Text(AppFormatters.shortDate(in: timeZone).string(from: flight.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(flight.airline) · \(flight.flightNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 12) {
                flightStop(time: flight.departureTime, airport: flight.originAirport, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.travelTeal)
                    .accessibilityHidden(true)
                flightStop(time: flight.arrivalDateTime(in: timeZone), airport: flight.destinationAirport, alignment: .trailing,
                    date: flight.arrivalDate)
            }

            if let duration = TravelDurationFormatter.string(from: flight.departureTime,
                                                              to: flight.arrivalDateTime(in: timeZone)) {
                Label(duration, systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                if let aircraft = flight.aircraft {
                    Label(aircraft, systemImage: "airplane")
                }
                if let cabin = flight.cabin {
                    Label(cabin, systemImage: "seat.airline")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                NavigationLink { TripItemEditorView(kind: .flight, itemID: flight.id) } label: {
                    Text("Details").frame(maxWidth: .infinity)
                }.buttonStyle(TravelCardButtonStyle())
                Button(action: coverAction) { Text("Omslag").frame(maxWidth: .infinity) }
                    .buttonStyle(TravelCardButtonStyle())
            }
        }
        .padding(18)
        .frame(minHeight: flight.presentationMedia == nil ? 0 : 210, alignment: .bottom)
        .foregroundStyle(flight.presentationMedia == nil ? Color.primary : Color.white)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .systemBackground))
            if flight.presentationMedia != nil {
                Color.white
                TripMediaImage(media: flight.presentationMedia).scaledToFit().padding(24)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .travelCardShadow()
        .accessibilityElement(children: .contain)
    }

    private func flightStop(time: Date, airport: String, alignment: HorizontalAlignment, date: Date? = nil) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(AppFormatters.time(in: timeZone).string(from: time))
                .font(.title3.bold())
            Text(airport)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            if let date, !TripCalendar.calendar(in: timeZone).isDate(date, inSameDayAs: flight.date) {
                Text(AppFormatters.shortDate(in: timeZone).string(from: date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

struct ActivityHeroCard: View {
    let activity: Activity
    let timeZone: TimeZone
    let coverAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 80)
            Text(activity.title).font(.title3.bold())
            if let place = activity.location?.placeName?.nilIfBlank { Text(place).font(.subheadline) }
            Text(timeRange).font(.subheadline.monospacedDigit().weight(.semibold))
            HStack(spacing: 10) {
                NavigationLink { ActivityDetailView(activityID: activity.id) } label: {
                    Text("Details").frame(maxWidth: .infinity)
                }.buttonStyle(TravelCardButtonStyle())
                Button(action: coverAction) { Text("Omslag").frame(maxWidth: .infinity) }
                    .buttonStyle(TravelCardButtonStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(minHeight: 200, alignment: .bottomLeading)
        .background {
            TripMediaImage(media: activity.presentationMedia).scaledToFill()
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .travelCardShadow()
    }

    private var timeRange: String {
        let formatter = AppFormatters.time(in: timeZone)
        guard let end = activity.endTime else { return formatter.string(from: activity.startTime) }
        return "\(formatter.string(from: activity.startTime)) – \(formatter.string(from: end))"
    }
}

struct ActivityRow: View {
    let activity: Activity
    let timeZone: TimeZone
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if activity.coverMedia != nil {
                TripMediaImage(media: activity.coverMedia).scaledToFill().frame(width: 58, height: 58).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(spacing: 4) {
                Image(systemName: category.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(categoryColor)
                    .frame(width: 34, height: 34)
                    .background(categoryColor.opacity(0.14), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                        .frame(minHeight: 54)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(timeRange)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                    if activity.isCompleted {
                        Label("Afgerond", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if activity.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.travelCoral)
                            .accessibilityLabel("Favoriet")
                    }
                }
                Text(activity.title)
                    .font(.body.weight(.semibold))
                if let description = activity.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String {
        let formatter = AppFormatters.time(in: timeZone)
        let start = formatter.string(from: activity.startTime)
        guard let endTime = activity.endTime else { return start }
        return "\(start) – \(formatter.string(from: endTime))"
    }

    private var category: ItineraryCategory {
        ItineraryCategory(rawValue: activity.category) ?? .other
    }

    private var categoryColor: Color {
        switch category {
        case .travel: .travelTeal
        case .accommodation: .travelGreen
        case .activity: .travelOrange
        case .viewpoint: .travelPurple
        case .restaurant: .travelCoral
        case .freeTime: .travelPurple
        case .shopping: .travelSun
        case .other: .secondary
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: Circle())
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct TransportCard: View {
    @Environment(\.openURL) private var openURL

    let transport: TransportItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(transport.type.title, systemImage: transport.type.symbolName)
                    .font(.headline)
                    .foregroundStyle(Color.travelCoral)
                Spacer()
                Text(departureDay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if transport.provider != nil || transport.referenceNumber != nil {
                Text([transport.provider, transport.referenceNumber].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                transportStop(time: transport.departureDate, name: transport.origin, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.travelTeal)
                    .accessibilityHidden(true)
                transportStop(time: transport.arrivalDate, name: transport.destination, alignment: .trailing)
            }

            HStack(spacing: 14) {
                if let terminal = transport.terminal {
                    Label("Terminal \(terminal)", systemImage: "signpost.right")
                }
                if let duration = transport.duration {
                    Label(AppFormatters.duration(duration), systemImage: "clock")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            if let detailsURL = transport.bookingURL {
                Button("Bekijk vervoer") { openURL(detailsURL) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.travelTeal)
                    .frame(minHeight: 44)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .travelCardShadow()
        .accessibilityElement(children: .contain)
    }

    private var departureDay: String {
        Calendar.current.isDateInToday(transport.departureDate)
            ? "Vandaag"
            : AppFormatters.shortDate.string(from: transport.departureDate)
    }

    private func transportStop(time: Date?, name: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(time.map(AppFormatters.time.string) ?? "—")
                .font(.title3.bold())
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

struct ItineraryRow: View {
    @Environment(\.openURL) private var openURL

    let item: ItineraryItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: item.category.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(categoryColor)
                    .frame(width: 34, height: 34)
                    .background(categoryColor.opacity(0.14), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                        .frame(minHeight: 54)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(AppFormatters.time.string(from: item.startDate))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                    if item.status == .current {
                        Text(item.status.title)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.travelCoral.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.travelCoral)
                    } else if item.status == .completed {
                        Label(item.status.title, systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.title)
                    .font(.body.weight(.semibold))
                if let location = item.location {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let description = item.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let navigationURL = item.url {
                    Button("Route") { openURL(navigationURL) }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.travelTeal)
                        .frame(minHeight: 36)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var categoryColor: Color {
        switch item.category {
        case .travel: .travelTeal
        case .accommodation: .travelGreen
        case .activity: .travelOrange
        case .viewpoint: .travelPurple
        case .restaurant: .travelCoral
        case .freeTime: .travelPurple
        case .shopping: .travelSun
        case .other: .secondary
        }
    }
}

struct SuggestionCard: View {
    let suggestion: NearbySuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: suggestionSymbol)
                .font(.title2)
                .foregroundStyle(Color.travelTeal)
                .frame(width: 42, height: 42)
                .background(Color.travelTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(suggestion.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.travelSun)
                Text(suggestion.rating, format: .number.precision(.fractionLength(1)))
                    .fontWeight(.bold)
                Text("(\(suggestion.reviewCount))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack {
                Text(AppFormatters.distance(suggestion.distanceMeters))
                Spacer()
                if let openingStatus = suggestion.openingStatus, openingStatus != .unknown {
                    let isOpen = openingStatus == .open
                    Label(isOpen ? "Open" : "Gesloten", systemImage: isOpen ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundStyle(isOpen ? Color.travelGreen : .secondary)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .frame(width: 205, alignment: .topLeading)
        .frame(minHeight: 190, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .travelCardShadow()
        .accessibilityElement(children: .combine)
    }

    private var suggestionSymbol: String {
        if suggestion.category.localizedCaseInsensitiveContains("restaurant") { return "fork.knife" }
        if suggestion.category.localizedCaseInsensitiveContains("café") { return "cup.and.saucer.fill" }
        return "leaf.fill"
    }
}

private struct TravelCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.travelTeal)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.white.opacity(configuration.isPressed ? 0.78 : 0.96), in: RoundedRectangle(cornerRadius: 13))
    }
}

extension View {
    func travelCardShadow() -> some View {
        shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }
}

extension Color {
    static let travelTeal = Color(red: 0.02, green: 0.52, blue: 0.55)
    static let travelCoral = Color(red: 0.91, green: 0.25, blue: 0.34)
    static let travelOrange = Color(red: 0.91, green: 0.43, blue: 0.15)
    static let travelSun = Color(red: 1.00, green: 0.72, blue: 0.16)
    static let travelGreen = Color(red: 0.20, green: 0.48, blue: 0.25)
    static let travelPurple = Color(red: 0.48, green: 0.29, blue: 0.55)
    static let travelBackground = Color(uiColor: .systemGroupedBackground)
}

#Preview("Verblijf") {
    let sample = TodayComponentPreview.dashboard
    TripStatusCard(
        destination: sample.destination,
        accommodation: sample.accommodation!,
        timeZone: sample.trip.timeZone
    )
        .padding()
}

#Preview("Vervoer") {
    TransportCard(transport: TodayComponentPreview.dashboard.nextTransport!)
        .padding()
}

#Preview("Suggestie") {
    SuggestionCard(suggestion: TodayComponentPreview.dashboard.nearbySuggestions[0])
        .padding()
}

private enum TodayComponentPreview {
    static var dashboard: TodayDashboardData {
        do {
            return try LocalTripRepository().sampleDashboard()
        } catch {
            preconditionFailure("Bundled trip data could not be loaded: \(error)")
        }
    }
}
