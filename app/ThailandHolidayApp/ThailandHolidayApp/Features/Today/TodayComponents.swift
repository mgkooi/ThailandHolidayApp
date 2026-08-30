import SwiftUI

struct TodayHeader: View {
    let date: Date
    let timeZone: TimeZone
    let canGoToPreviousDay: Bool
    let canGoToNextDay: Bool
    let previousDayAction: () -> Void
    let nextDayAction: () -> Void
    let dateAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vandaag")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.reizzPrimaryText)
            HStack(spacing: 6) {
                dateNavigationButton(
                    symbol: "chevron.left",
                    label: "Vorige reisdag",
                    isEnabled: canGoToPreviousDay,
                    action: previousDayAction
                )
                Spacer()
                Button(action: dateAction) {
                    Text(AppFormatters.dutchDate(in: timeZone).string(from: date).capitalized)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
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
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.reizzBrandForeground : Color.secondary.opacity(0.35))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

struct TodayLocationRow: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                Text(name).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.reizzBrandForeground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(name) op kaart")
    }
}

struct TodayActionButton: View {
    let symbol: String
    let accessibilityLabel: String
    var accessibilityHint: String? = nil
    var destination: AnyView? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let destination {
                NavigationLink { destination } label: { buttonLabel }
            } else {
                Button(action: { action?() }) { buttonLabel }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityIdentifier("todayAction.\(accessibilityLabel)")
    }

    private var buttonLabel: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Color.reizzAccent.opacity(0.9), in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.24), lineWidth: 0.5) }
            .contentShape(Circle())
    }
}

struct TodayHeroCard<Content: View, Actions: View>: View {
    let kind: TripItemKind
    let media: TripMedia?
    var minimumHeight: CGFloat = 196
    let content: Content
    let actions: Actions

    init(kind: TripItemKind, media: TripMedia?, minimumHeight: CGFloat = 196,
         @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.media = media
        self.minimumHeight = minimumHeight
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            LinearGradient(colors: [.black.opacity(media == nil ? 0.05 : 0.18), .black.opacity(0.86)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                content
                HStack(spacing: 10) { actions }
            }
            .padding(15)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .bottomLeading)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .travelCardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayHeroCard.\(kind.rawValue)")
    }

    @ViewBuilder private var background: some View {
        if let media {
            if media.presentationStyle == .logo {
                LinearGradient(colors: [.white, Color(uiColor: .secondarySystemBackground)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                TripMediaImage(media: media).scaledToFit().padding(34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TripMediaImage(media: media).scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityIdentifier("todayHeroCover.fullBleed")
            }
        } else {
            LinearGradient(colors: [fallbackColor.opacity(0.92), fallbackColor.opacity(0.58)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: kind.symbolName)
                .font(.system(size: 86, weight: .semibold))
                .foregroundStyle(.white.opacity(0.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)
        }
    }

    private var fallbackColor: Color {
        switch kind {
        case .flight: .travelCoral
        case .accommodation: .travelTeal
        case .train, .ferry, .transfer, .rentalVehicle: .travelPurple
        case .restaurant: .travelCoral
        case .activity: .travelOrange
        case .other: .secondary
        }
    }
}

struct TripStatusCard: View {
    @Environment(\.openURL) private var openURL

    let destination: Destination?
    let accommodation: Accommodation
    let timeZone: TimeZone
    var coverAction: () -> Void = {}

    var body: some View {
        TodayHeroCard(kind: .accommodation, media: accommodation.presentationMedia) {
            Text("JE VERBLIJF").font(.caption.bold()).tracking(1.1).foregroundStyle(.white.opacity(0.8))
            Text(accommodation.placeName ?? destination?.name ?? accommodation.name).font(.title2.bold())
            VStack(alignment: .leading, spacing: 5) {
                Label(accommodation.name, systemImage: "bed.double.fill")
                    .font(.headline)
                if !accommodation.roomDescription.isEmpty { Text(accommodation.roomDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82)) }
            }
            HStack(spacing: 16) {
                Label(dateRange, systemImage: "calendar")
                Label(nightsText, systemImage: "moon.stars.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.92))
        } actions: {
            if accommodation.location.hasUsableLocation {
                TodayActionButton(symbol: "location.fill", accessibilityLabel: "Navigeer",
                    accessibilityHint: "Opent de route naar \(accommodation.name)", action: {
                        Task { await AppleMapsNavigator().open(accommodation.location, name: accommodation.name) }
                    })
            }
            TodayActionButton(symbol: "info.circle.fill", accessibilityLabel: "Bekijk details",
                destination: AnyView(TripItemEditorView(kind: .accommodation, itemID: accommodation.id)))
            TodayActionButton(symbol: "photo.fill", accessibilityLabel: "Wijzig omslag", action: coverAction)
        }
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
        TodayHeroCard(kind: .flight, media: flight.presentationMedia, minimumHeight: 210) {
            HStack {
                Label("Vlucht", systemImage: "airplane")
                    .font(.headline)
                Spacer()
                Text(AppFormatters.shortDate(in: timeZone).string(from: flight.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            Text("\(flight.airline) · \(flight.flightNumber)").font(.title3.bold())

            HStack(alignment: .center, spacing: 12) {
                flightStop(time: flight.departureTime, airport: flight.originAirport, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
                flightStop(time: flight.arrivalDateTime(in: timeZone), airport: flight.destinationAirport, alignment: .trailing,
                    date: flight.arrivalDate)
            }

            if let duration = TravelDurationFormatter.string(from: flight.departureTime,
                                                              to: flight.arrivalDateTime(in: timeZone)) {
                Label(duration, systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
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
            .foregroundStyle(.white.opacity(0.82))
        } actions: {
            if let target = ManagedTripItem.flight(flight).navigationTarget, target.location.hasUsableLocation {
                TodayActionButton(symbol: "location.fill", accessibilityLabel: "Navigeer", action: {
                    Task { await AppleMapsNavigator().open(target.location, name: target.name) }
                })
            }
            TodayActionButton(symbol: "info.circle.fill", accessibilityLabel: "Bekijk details",
                destination: AnyView(TripItemEditorView(kind: .flight, itemID: flight.id)))
            TodayActionButton(symbol: "photo.fill", accessibilityLabel: "Wijzig omslag", action: coverAction)
        }
    }

    private func flightStop(time: Date, airport: String, alignment: HorizontalAlignment, date: Date? = nil) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(AppFormatters.time(in: timeZone).string(from: time))
                .font(.title3.bold())
            Text(airport)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            if let date, !TripCalendar.calendar(in: timeZone).isDate(date, inSameDayAs: flight.date) {
                Text(AppFormatters.shortDate(in: timeZone).string(from: date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.82))
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
        TodayHeroCard(kind: .activity, media: activity.presentationMedia, minimumHeight: 200) {
            Text(activity.title).font(.title3.bold())
            if let place = activity.location?.placeName?.nilIfBlank { Text(place).font(.subheadline) }
            Text(timeRange).font(.subheadline.monospacedDigit().weight(.semibold))
        } actions: {
            if let target = ManagedTripItem.activity(activity).navigationTarget, target.location.hasUsableLocation {
                TodayActionButton(symbol: "location.fill", accessibilityLabel: "Navigeer", action: {
                    Task { await AppleMapsNavigator().open(target.location, name: target.name) }
                })
            }
            TodayActionButton(symbol: "info.circle.fill", accessibilityLabel: "Bekijk details",
                destination: AnyView(TripItemEditorView(kind: .activity, itemID: activity.id)))
            TodayActionButton(symbol: "photo.fill", accessibilityLabel: "Wijzig omslag", action: coverAction)
        }
    }

    private var timeRange: String {
        let formatter = AppFormatters.time(in: timeZone)
        guard let end = activity.endTime else { return formatter.string(from: activity.startTime) }
        return "\(formatter.string(from: activity.startTime)) – \(formatter.string(from: end))"
    }
}

struct TodayTransportCard: View {
    let item: ManagedTripItem
    let timeZone: TimeZone
    let coverAction: () -> Void

    var body: some View {
        TodayHeroCard(kind: item.kind, media: item.presentationMedia, minimumHeight: 188) {
            Label(item.kind.title, systemImage: item.kind.symbolName).font(.headline)
            if !operatorName.isEmpty { Text(operatorName).font(.title3.bold()) }
            HStack(spacing: 12) {
                stop(time: departureTime, name: origin, alignment: .leading)
                Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.8))
                stop(time: arrivalTime, name: destination, alignment: .trailing)
            }
            if let duration = durationText { Label(duration, systemImage: "clock").font(.caption.weight(.semibold)) }
        } actions: {
            if let target = item.navigationTarget, target.location.hasUsableLocation {
                TodayActionButton(symbol: "location.fill", accessibilityLabel: "Navigeer", action: {
                    Task { await AppleMapsNavigator().open(target.location, name: target.name) }
                })
            }
            TodayActionButton(symbol: "info.circle.fill", accessibilityLabel: "Bekijk details",
                destination: AnyView(TripItemEditorView(kind: item.kind, itemID: item.id)))
            TodayActionButton(symbol: "photo.fill", accessibilityLabel: "Wijzig omslag", action: coverAction)
        }
    }

    private var operatorName: String {
        switch item {
        case .transfer(let value): value.provider
        case .ferry(let value): value.operatorName
        case .train(let value): [value.operatorName, value.trainNumber].filter { !$0.isEmpty }.joined(separator: " · ")
        case .rentalVehicle(let value): value.company ?? value.vehicleType.title
        default: ""
        }
    }
    private var origin: String { switch item { case .transfer(let x): x.origin; case .ferry(let x): x.departureLocation; case .train(let x): x.originStation; case .rentalVehicle(let x): x.pickupLocation; default: "" } }
    private var destination: String { switch item { case .transfer(let x): x.destination; case .ferry(let x): x.arrivalLocation; case .train(let x): x.destinationStation; case .rentalVehicle(let x): x.dropoffLocation ?? "—"; default: "" } }
    private var departureTime: Date? { switch item { case .transfer(let x): x.startTime; case .ferry(let x): x.departureTime; case .train(let x): x.departureTime; case .rentalVehicle(let x): x.pickupTime; default: nil } }
    private var arrivalTime: Date? { switch item { case .transfer(let x): x.endTime; case .ferry(let x): x.arrivalTime; case .train(let x): x.arrivalTime; case .rentalVehicle(let x): x.dropoffTime; default: nil } }
    private var durationText: String? { guard let departureTime, let arrivalTime else { return nil }; return TravelDurationFormatter.string(from: departureTime, to: arrivalTime) }

    private func stop(time: Date?, name: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(time.map(AppFormatters.time(in: timeZone).string) ?? "—").font(.title3.bold())
            Text(name).font(.caption).foregroundStyle(.white.opacity(0.82)).lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }.frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

struct TodayPlanningCard: View {
    let item: ManagedTripItem
    let timeZone: TimeZone
    let coverAction: () -> Void

    var body: some View {
        TodayHeroCard(kind: item.kind, media: item.presentationMedia, minimumHeight: 174) {
            Label(item.kind.title, systemImage: item.kind.symbolName).font(.caption.bold())
            Text(title).font(.title3.bold())
            if let time { Text(time).font(.subheadline.monospacedDigit().weight(.semibold)) }
            if let location { Label(location, systemImage: "mappin").font(.subheadline).lineLimit(2) }
        } actions: {
            if let target = item.navigationTarget, target.location.hasUsableLocation {
                TodayActionButton(symbol: "location.fill", accessibilityLabel: "Navigeer", action: {
                    Task { await AppleMapsNavigator().open(target.location, name: target.name) }
                })
            }
            TodayActionButton(symbol: "info.circle.fill", accessibilityLabel: "Bekijk details",
                destination: AnyView(TripItemEditorView(kind: item.kind, itemID: item.id)))
            TodayActionButton(symbol: "photo.fill", accessibilityLabel: "Wijzig omslag", action: coverAction)
        }
    }

    private var title: String { switch item { case .restaurant(let x): x.name; case .activity(let x): x.title; case .other(let x): x.title; default: item.kind.title } }
    private var location: String? { switch item { case .restaurant(let x): x.address; case .activity(let x): x.location?.placeName; case .other(let x): x.location; default: nil } }
    private var time: String? {
        let formatter = AppFormatters.time(in: timeZone)
        switch item { case .restaurant(let x): return formatter.string(from: x.time); case .activity(let x): return formatter.string(from: x.startTime); case .other(let x): return x.startTime.map(formatter.string); default: return nil }
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
    static let travelTeal = Color.reizzBrandForeground
    static let travelCoral = Color(red: 0.91, green: 0.25, blue: 0.34)
    static let travelOrange = Color.reizzAccent
    static let travelSun = Color(red: 1.00, green: 0.72, blue: 0.16)
    static let travelGreen = Color(red: 0.20, green: 0.48, blue: 0.25)
    static let travelPurple = Color(red: 0.48, green: 0.29, blue: 0.55)
    static let travelBackground = Color.reizzBackground
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
