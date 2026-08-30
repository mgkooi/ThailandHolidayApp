import SwiftUI
import OSLog

struct TodayView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(TripWeatherService.self) private var weatherService
    @Environment(DiscoverySession.self) private var discovery
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(DiscoveryDeviceLocationService.self) private var deviceLocationService
    @Environment(\.locationGeocoder) private var locationGeocoder
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date
    @State private var isCalendarPresented = false
    @State private var nearbyLocation: SearchLocation?
    @State private var nearbyRestaurants: [DiscoveryResult] = []
    @State private var nearbyState: DiscoveryLoadState = .idle
    @State private var navigationDirection = 1
    @State private var coverTarget: ManagedTripItem?
    @State private var weatherLocation: TripWeatherLocation?

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
            .task(id: weatherRequestKey) {
                await refreshWeather()
            }
            .task(id: discoveryRequestKey) { await refreshNearbyRestaurants() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshWeather() }
            }
            .sheet(item: $coverTarget) { CoverEditorView(itemID: $0.id, kind: $0.kind) }
        }
    }

    private func dashboardContent(trip: Trip) -> some View {
        let _ = tripStore.dataRevision
        let destination = tripStore.destination(for: selectedDate)
        let accommodation = tripStore.accommodation(for: selectedDate)
        let accommodationDestination = accommodation.flatMap { stay in
            stay.destinationID.flatMap { id in trip.destinations.first { $0.id == id } }
        } ?? destination
        let flights = tripStore.flights(on: selectedDate)
        let transfers = tripStore.transfers(on: selectedDate)
        let ferries = tripStore.ferries(on: selectedDate)
        let trains = tripStore.trains(on: selectedDate)
        let rentalVehicles = tripStore.rentalVehicles(on: selectedDate)
        let activities = tripStore.activities(on: selectedDate)
        let restaurants = tripStore.restaurants(on: selectedDate)
        let otherItems = tripStore.otherItems(on: selectedDate)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                TodayHeader(
                    date: selectedDate,
                    timeZone: trip.timeZone,
                    canGoToPreviousDay: TodayDateSelection.canMove(selectedDate, by: -1, in: trip),
                    canGoToNextDay: TodayDateSelection.canMove(selectedDate, by: 1, in: trip),
                    previousDayAction: { moveSelectedDate(by: -1, in: trip) },
                    nextDayAction: { moveSelectedDate(by: 1, in: trip) },
                    dateAction: { isCalendarPresented = true }
                )

                if let weatherLocation {
                    VStack(alignment: .leading, spacing: 8) {
                        WeatherCard(
                            destinationName: weatherLocation.name,
                            forecast: weatherService.hourlyForecast,
                            dailyForecast: weatherService.dailyForecast,
                            state: weatherService.state,
                            errorCategory: weatherService.errorCategory,
                            forecastDate: selectedDate,
                            showsHourlyForecast: TripWeatherPresentation.showsHourlyForecast(
                                for: selectedDate, now: UITestConfiguration.weatherNow ?? .now,
                                timeZone: trip.timeZone),
                            timeZone: trip.timeZone
                        )
                        .accessibilityIdentifier("todayWeatherCard")

                        if let locationName = todayLocationName(accommodation: accommodation,
                                                                destination: accommodationDestination) {
                            TodayLocationRow(name: locationName, action: openDailyLocationInMap)
                                .accessibilityIdentifier("todayLocationRow")
                        }
                    }

                } else {
                    if activities.isEmpty && restaurants.isEmpty && otherItems.isEmpty && accommodation == nil
                        && flights.isEmpty && transfers.isEmpty && ferries.isEmpty && trains.isEmpty && rentalVehicles.isEmpty {
                        ContentUnavailableView(
                            "Geen reisplanning voor deze dag",
                            systemImage: "sun.max",
                            description: Text("Voor deze reisdag zijn nog geen details ingevuld.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                if !flights.isEmpty || !transfers.isEmpty || !ferries.isEmpty || !trains.isEmpty || !rentalVehicles.isEmpty {
                    sectionHeader("Transport").accessibilityIdentifier("todaySection.transport")
                    ForEach(TodayItemSorter.sorted(flights.map(ManagedTripItem.flight)
                        + transfers.map(ManagedTripItem.transfer) + ferries.map(ManagedTripItem.ferry)
                        + trains.map(ManagedTripItem.train) + rentalVehicles.map(ManagedTripItem.rentalVehicle))) { item in
                        if case .flight(let flight) = item {
                            FlightCard(flight: flight, timeZone: trip.timeZone,
                                       coverAction: { coverTarget = item })
                        } else { transportCard(item, timeZone: trip.timeZone) }
                    }
                }

                if let accommodation {
                    sectionHeader("Accommodation").accessibilityIdentifier("todaySection.accommodation")
                    TripStatusCard(destination: accommodationDestination, accommodation: accommodation,
                                   timeZone: trip.timeZone,
                                   coverAction: { coverTarget = .accommodation(accommodation) })
                }

                QuickActionsView(accommodation: accommodation, hasFlights: !flights.isEmpty)

                planningSection(activities: activities, restaurants: restaurants, otherItems: otherItems,
                                timeZone: trip.timeZone)
                suggestionsSection()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 96)
            .accessibilityIdentifier("todayScrollableContent")
            .accessibilityValue(trip.name)
        }
        .background(Color.reizzBackground)
        .id(TripCalendar.calendar(in: trip.timeZone).startOfDay(for: selectedDate))
        .transition(.asymmetric(insertion: .move(edge: navigationDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: navigationDirection > 0 ? .leading : .trailing).combined(with: .opacity)))
        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
            guard let offset = TodaySwipeNavigation.dayOffset(horizontal: value.translation.width,
                                                               vertical: value.translation.height) else { return }
            moveSelectedDate(by: offset, in: trip)
        })
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

    private var weatherRequestKey: String? {
        guard let trip = tripStore.trip else { return nil }
        let day = TripCalendar.calendar(in: trip.timeZone).startOfDay(for: selectedDate)
        return "\(trip.id)-\(day.timeIntervalSince1970)-\(tripStore.dataRevision)"
    }

    private func refreshWeather() async {
        guard let trip = tripStore.trip else { return }
        let accommodation = tripStore.accommodation(for: selectedDate)
        var geocodedAccommodation: TripWeatherLocation?
        if let accommodation, accommodation.latitude == nil || accommodation.longitude == nil {
            let query = [accommodation.address.nilIfBlank, accommodation.placeName?.nilIfBlank]
                .compactMap { $0 }.joined(separator: ", ")
            if let coordinate = try? await locationGeocoder.geocode(address: query) {
                geocodedAccommodation = TripWeatherLocation(name: accommodation.placeName ?? accommodation.name,
                    latitude: coordinate.latitude, longitude: coordinate.longitude, source: .accommodationGeocode)
            }
        }
        let planned = plannedItems(on: selectedDate)
        let contextual = TripWeatherLocationSelector.select(accommodation: accommodation,
            plannedItems: planned, currentLocation: nil, destination: nil)
        let isSelectedToday = TripCalendar.calendar(in: trip.timeZone).isDate(selectedDate, inSameDayAs: .now)
        let current = geocodedAccommodation == nil && contextual == nil && isSelectedToday
            ? await deviceLocationService.currentLocation() : nil
        let location = geocodedAccommodation ?? contextual
            ?? TripWeatherLocationSelector.select(accommodation: nil, plannedItems: [],
                currentLocation: current, destination: tripStore.destination(for: selectedDate))
        weatherLocation = location
        guard let location else { return }
        await weatherService.refresh(location: location, date: selectedDate, timeZone: trip.timeZone,
                                     now: UITestConfiguration.weatherNow ?? .now)
    }

    private func plannedItems(on date: Date) -> [ManagedTripItem] {
        tripStore.flights(on: date).map(ManagedTripItem.flight)
            + tripStore.transfers(on: date).map(ManagedTripItem.transfer)
            + tripStore.ferries(on: date).map(ManagedTripItem.ferry)
            + tripStore.trains(on: date).map(ManagedTripItem.train)
            + tripStore.rentalVehicles(on: date).map(ManagedTripItem.rentalVehicle)
            + tripStore.activities(on: date).map(ManagedTripItem.activity)
            + tripStore.restaurants(on: date).map(ManagedTripItem.restaurant)
            + tripStore.otherItems(on: date).map(ManagedTripItem.other)
    }

    private func moveSelectedDate(by dayOffset: Int, in trip: Trip) {
        guard let date = TodayDateSelection.moving(selectedDate, by: dayOffset, in: trip) else { return }
        navigationDirection = dayOffset
        withAnimation(.easeInOut(duration: 0.22)) { selectedDate = date }
    }

    private func planningSection(activities: [Activity], restaurants: [RestaurantReservation],
                                 otherItems: [TripEvent], timeZone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Planning").accessibilityIdentifier("todaySection.planning")

            if activities.isEmpty && restaurants.isEmpty && otherItems.isEmpty {
                ContentUnavailableView(
                    "Geen activiteiten gepland",
                    systemImage: "calendar",
                    description: Text("Geniet van een vrije dag.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(TodayItemSorter.sorted(activities.map(ManagedTripItem.activity)
                        + restaurants.map(ManagedTripItem.restaurant) + otherItems.map(ManagedTripItem.other))) { item in
                        planningCard(item, timeZone: timeZone)
                    }
                }
            }
        }
    }

    private func transportCard(_ item: ManagedTripItem, timeZone: TimeZone) -> some View {
        TodayTransportCard(item: item, timeZone: timeZone, coverAction: { coverTarget = item })
    }

    private func planningCard(_ item: ManagedTripItem, timeZone: TimeZone) -> some View {
        TodayPlanningCard(item: item, timeZone: timeZone, coverAction: { coverTarget = item })
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
            .foregroundStyle(Color.reizzBrandForeground)
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
    static func moving(_ date: Date, by days: Int, in trip: Trip) -> Date? {
        let calendar = TripCalendar.calendar(in: trip.timeZone)
        guard let candidate = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        let day = calendar.startOfDay(for: candidate)
        guard day >= calendar.startOfDay(for: trip.startDate),
              day <= calendar.startOfDay(for: trip.endDate) else { return nil }
        return candidate
    }
    static func canMove(_ date: Date, by days: Int, in trip: Trip) -> Bool { moving(date, by: days, in: trip) != nil }
}

struct TodaySwipeNavigation {
    static let minimumDistance: CGFloat = 60
    static func dayOffset(horizontal: CGFloat, vertical: CGFloat) -> Int? {
        guard abs(horizontal) >= minimumDistance, abs(horizontal) > abs(vertical) else { return nil }
        return horizontal < 0 ? 1 : -1
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
    @State private var locationService = DiscoveryDeviceLocationService()
    let selectedDate: Date

    var body: some View {
        TodayView(selectedDate: selectedDate)
            .environment(tripStore)
            .environment(weatherService)
            .environment(locationService)
            .task { tripStore.loadIfNeeded() }
    }
}

private struct PreviewWeatherProvider: TripWeatherProviding {
    func hourlyWeather(latitude: Double, longitude: Double) async throws -> [TripHourWeather] { [] }
}
