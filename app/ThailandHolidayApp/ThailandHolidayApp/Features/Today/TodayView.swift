import SwiftUI
import OSLog

struct TodayView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(TripWeatherService.self) private var weatherService
    @Environment(DiscoverySession.self) private var discovery
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.locationGeocoder) private var locationGeocoder
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date
    @State private var isCalendarPresented = false
    @State private var nearbyLocation: SearchLocation?
    @State private var nearbyRestaurants: [DiscoveryResult] = []
    @State private var nearbyState: DiscoveryLoadState = .idle

    init(selectedDate: Date? = nil, now: () -> Date = Date.init) {
        _selectedDate = State(initialValue: TodayDateSelection.initialDate(selectedDate: selectedDate, now: now()))
    }

    var body: some View {
        NavigationStack {
            Group {
                if tripStore.isLoading && tripStore.trip == nil {
                    ProgressView("Reisplanning laden…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tripStore.errorMessage != nil {
                    ContentUnavailableView(
                        "Reisplanning niet beschikbaar",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Probeer het later opnieuw.")
                    )
                } else if let trip = tripStore.trip {
                    dashboardContent(trip: trip)
                } else {
                    ContentUnavailableView(
                        "Geen reisplanning voor deze dag",
                        systemImage: "sun.max",
                        description: Text("Kies een datum binnen de reisperiode.")
                    )
                }
            }
            .navigationTitle("Vandaag")
            .toolbar { TripContextToolbar() }
            .task(id: weatherRequestKey) {
                await refreshWeather()
            }
            .task(id: discoveryRequestKey) { await refreshNearbyRestaurants() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshWeather() }
            }
        }
    }

    private func dashboardContent(trip: Trip) -> some View {
        let _ = tripStore.dataRevision
        let destination = tripStore.destination(for: selectedDate)
        let accommodation = tripStore.accommodation(for: selectedDate)
        let accommodationDestination = accommodation.flatMap { stay in
            stay.destinationID.flatMap { id in trip.destinations.first { $0.id == id } }
        } ?? destination
        let weatherDestination = destination ?? accommodation.flatMap(weatherDestination(for:))
        let flights = tripStore.flights(on: selectedDate)
        let activities = tripStore.activities(on: selectedDate)
        let restaurants = tripStore.restaurants(on: selectedDate)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                TodayHeader(
                    date: selectedDate,
                    locationName: todayLocationName(accommodation: accommodation, destination: accommodationDestination),
                    timeZone: trip.timeZone,
                    canGoToPreviousDay: true,
                    canGoToNextDay: true,
                    previousDayAction: { moveSelectedDate(by: -1, in: trip) },
                    nextDayAction: { moveSelectedDate(by: 1, in: trip) },
                    dateAction: { isCalendarPresented = true },
                    locationAction: openDailyLocationInMap
                )

                if let weatherDestination {
                    WeatherCard(
                        destinationName: weatherDestination.name,
                        forecast: weatherService.hourlyForecast,
                        state: weatherService.state,
                        timeZone: trip.timeZone
                    )

                } else {
                    if activities.isEmpty && restaurants.isEmpty && accommodation == nil && flights.isEmpty {
                        ContentUnavailableView(
                            "Geen reisplanning voor deze dag",
                            systemImage: "sun.max",
                            description: Text("Voor deze reisdag zijn nog geen details ingevuld.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                if let accommodation {
                    TripStatusCard(destination: accommodationDestination, accommodation: accommodation, timeZone: trip.timeZone)
                }

                QuickActionsView(accommodation: accommodation, hasFlights: !flights.isEmpty)

                if !flights.isEmpty {
                    sectionHeader("Volgende verplaatsing")
                    ForEach(flights) { flight in
                        FlightCard(flight: flight, timeZone: trip.timeZone)
                    }
                }

                planningSection(activities: activities, restaurants: restaurants, timeZone: trip.timeZone)
                suggestionsSection()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.travelBackground)
        .refreshable { await refreshToday() }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isCalendarPresented) {
            NavigationStack {
                DatePicker("Kies datum", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .onChange(of: selectedDate) { _, _ in isCalendarPresented = false }
                    .navigationTitle("Kies datum")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Vandaag") { selectedDate = .now; isCalendarPresented = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Sluit") { isCalendarPresented = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private var weatherRequestKey: TripWeatherCacheKey? {
        guard let trip = tripStore.trip else { return nil }
        let destination = tripStore.destination(for: selectedDate)
            ?? tripStore.accommodation(for: selectedDate).flatMap(weatherDestination(for:))
        guard let destination else { return nil }
        let day = TripCalendar.calendar(in: trip.timeZone).startOfDay(for: selectedDate)
        return TripWeatherCacheKey(destinationID: destination.id, day: day)
    }

    private func refreshWeather() async {
        guard let trip = tripStore.trip else { return }
        let destination = tripStore.destination(for: selectedDate)
            ?? tripStore.accommodation(for: selectedDate).flatMap(weatherDestination(for:))
        guard let destination else { return }
        await weatherService.refresh(destination: destination, date: selectedDate, timeZone: trip.timeZone)
    }

    private func weatherDestination(for accommodation: Accommodation) -> Destination? {
        guard let latitude = accommodation.latitude, let longitude = accommodation.longitude else { return nil }
        return Destination(
            id: accommodation.id,
            name: accommodation.placeName ?? accommodation.name,
            country: tripStore.trip?.country ?? "Thailand",
            region: accommodation.placeName ?? "",
            arrivalDate: accommodation.checkIn,
            departureDate: accommodation.checkOut,
            latitude: latitude,
            longitude: longitude,
            description: nil,
            imageReference: nil,
            notes: nil
        )
    }

    private func moveSelectedDate(by dayOffset: Int, in trip: Trip) {
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: selectedDate) else { return }
        selectedDate = date
    }

    private func planningSection(activities: [Activity], restaurants: [RestaurantReservation], timeZone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Planning vandaag")

            if activities.isEmpty && restaurants.isEmpty {
                ContentUnavailableView(
                    "Geen activiteiten gepland",
                    systemImage: "calendar",
                    description: Text("Geniet van een vrije dag.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        NavigationLink {
                            ActivityDetailView(activityID: activity.id)
                        } label: {
                            ActivityRow(
                                activity: activity,
                                timeZone: timeZone,
                                isLast: index == activities.count - 1 && restaurants.isEmpty
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(Array(restaurants.enumerated()), id: \.element.id) { index, restaurant in
                        NavigationLink {
                            TripItemEditorView(kind: .restaurant, itemID: restaurant.id)
                        } label: {
                            TodayRestaurantRow(restaurant: restaurant, timeZone: timeZone,
                                               isLast: index == restaurants.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .travelCardShadow()
            }
        }
    }

    private func suggestionsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(nearbyLocation.map { "In de buurt van \($0.name)" } ?? "In de buurt")
                Spacer()
                if nearbyLocation != nil {
                    Button("Bekijk alles") { openDiscover() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.travelTeal)
                    .frame(minHeight: 44)
                    .accessibilityHint("Opent restaurants in Ontdekken")
                }
            }

            if nearbyLocation == nil {
                Text("Geen locatie beschikbaar voor deze dag.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if nearbyState == .loading {
                ProgressView("Restaurants zoeken…")
            } else if nearbyRestaurants.isEmpty {
                Text(nearbyState == .failed ? "Locaties konden tijdelijk niet worden geladen." : "Geen restaurants gevonden.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(nearbyRestaurants.prefix(4)) { result in
                            Button { openDiscover(selectedResultID: result.id) } label: {
                                TodayDiscoveryCard(result: result)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opent deze locatie in Ontdekken")
                        }
                    }
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
            }
        }
    }

    private var discoveryRequestKey: String? {
        guard let trip = tripStore.trip else { return nil }
        let day = TripCalendar.calendar(in: trip.timeZone).startOfDay(for: selectedDate).timeIntervalSince1970
        let stay = tripStore.accommodation(for: selectedDate)
        return "\(trip.id)-\(day)-\(tripStore.dataRevision)-\(stay?.id.uuidString ?? "none")-\(stay?.latitude ?? 0)-\(stay?.longitude ?? 0)-\(stay?.placeName ?? "")"
    }

    private func refreshNearbyRestaurants() async {
        guard let trip = tripStore.trip else { return }
        nearbyState = .loading
        let location = await TripSearchLocationResolver(geocoder: locationGeocoder).resolve(for: selectedDate, in: trip)
        nearbyLocation = location
        guard let location else { nearbyRestaurants = []; nearbyState = .idle; return }
        await discovery.activate(location, category: .restaurant)
        nearbyRestaurants = discovery.results
        nearbyState = discovery.state
#if DEBUG
        Self.logger.debug("Today date=\(self.selectedDate, privacy: .public) accommodationID=\(tripStore.accommodation(for: selectedDate)?.id.uuidString ?? "none", privacy: .public) location=\(location.name, privacy: .public) restaurants=\(tripStore.restaurants(on: selectedDate).count, privacy: .public) activities=\(tripStore.activities(on: selectedDate).count, privacy: .public) nearby=\(nearbyRestaurants.count, privacy: .public)")
#endif
    }

    private func refreshToday() async {
        await refreshWeather()
        await refreshNearbyRestaurants()
    }

    private static let logger = Logger(subsystem: "nl.martijnkooi.ThailandHolidayApp", category: "Today")

    private func todayLocationName(accommodation: Accommodation?, destination: Destination?) -> String? {
        let place = accommodation?.placeName?.nilIfBlank ?? destination?.name.nilIfBlank ?? nearbyLocation?.name.nilIfBlank
        guard let place else { return nil }
        let country = tripStore.trip?.country.nilIfBlank
        return [place, country].compactMap { $0 }.joined(separator: ", ")
    }

    private func openDailyLocationInMap() {
        guard let nearbyLocation else { return }
        navigationState.openMap(focus: nearbyLocation, date: selectedDate)
    }

    private func openDiscover(selectedResultID: String? = nil) {
        guard let nearbyLocation else { return }
        navigationState.openDiscover(location: nearbyLocation, category: .restaurant,
                                     selectedResultID: selectedResultID)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
    }
}

private struct TodayRestaurantRow: View {
    let restaurant: RestaurantReservation
    let timeZone: TimeZone
    let isLast: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .foregroundStyle(Color.travelCoral)
                .frame(width: 32, height: 32)
                .background(Color.travelCoral.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name).font(.headline)
                HStack(spacing: 6) {
                    Text(AppFormatters.time(in: timeZone).string(from: restaurant.time))
                    if let address = restaurant.address?.nilIfBlank { Text("·"); Text(address).lineLimit(1) }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast { Divider().padding(.leading, 46) }
        }
    }
}

struct TodayDateSelection {
    static func initialDate(selectedDate: Date?, now: Date) -> Date { selectedDate ?? now }
    static func moving(_ date: Date, by days: Int, timeZone: TimeZone) -> Date {
        TripCalendar.calendar(in: timeZone).date(byAdding: .day, value: days, to: date) ?? date
    }
}

#Preview("Vandaag") {
    TodayPreview(selectedDate: TripCalendar.date(2026, 9, 9, hour: 12))
}

#Preview("Geen reisplanning") {
    TodayPreview(selectedDate: TripCalendar.date(2026, 9, 4, hour: 12))
}

private struct TodayPreview: View {
    @State private var tripStore = TripStore()
    @State private var weatherService = TripWeatherService(provider: PreviewWeatherProvider())
    let selectedDate: Date

    var body: some View {
        TodayView(selectedDate: selectedDate)
            .environment(tripStore)
            .environment(weatherService)
            .task { tripStore.loadIfNeeded() }
    }
}

private struct PreviewWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] { [] }
}
