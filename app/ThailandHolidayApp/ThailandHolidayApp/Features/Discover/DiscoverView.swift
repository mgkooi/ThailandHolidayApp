import MapKit
import SwiftUI

struct DiscoverView: View {
    @Environment(DiscoverySession.self) private var discovery
    @Environment(TripStore.self) private var tripStore
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.locationGeocoder) private var geocoder
    @Environment(DiscoveryDeviceLocationService.self) private var deviceLocation
    @State private var locationQuery = ""
    @State private var filters = DiscoveryFilters()
    @State private var sort: DiscoverySort = .recommended
    @State private var showsFilters = false
    @State private var selectedResult: DiscoveryResult?
    @State private var displayMode: DiscoveryDisplayMode = .list
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var mapRegion: MKCoordinateRegion?
    @State private var searchedRegion: MKCoordinateRegion?
    @State private var selectedMapID: String?
    @AppStorage("discovery.maxDistance") private var storedDistance = 10_000.0
    @AppStorage("discovery.minimumRating") private var storedRating = 0.0
    @AppStorage("discovery.minimumReviews") private var storedReviews = 0
    @AppStorage("discovery.openNow") private var storedOpenNow = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) { header; resultToolbar; discoveryContent }
                .background(Color.travelBackground)
                .navigationTitle("Ontdekken").navigationBarTitleDisplayMode(.inline)
                .toolbar { TripContextToolbar() }
                .refreshable { await discovery.refresh(radiusMeters: providerRadius) }
                .sheet(isPresented: $showsFilters) { DiscoveryFilterSheet(filters: $filters) }
                .sheet(item: $selectedResult) { DiscoveryDetailView(result: $0) }
                .task(id: navigationContextKey) { await establishContext() }
                .onAppear { restoreFilters() }
                .onChange(of: filters) { _, value in persist(value) }
                .onChange(of: showsFilters) { wasShowing, isShowing in
                    if wasShowing && !isShowing { Task { await discovery.refresh(radiusMeters: providerRadius) } }
                }
                .onChange(of: displayMode) { _, mode in
                    guard mode == .map, let location = discovery.activeLocation else { return }
                    mapPosition = .region(TripMapRegionBuilder.region(around: location, radiusMeters: providerRadius))
                }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ontdek \(discovery.activeLocation?.name ?? "je bestemming")")
                .font(.largeTitle.bold()).accessibilityIdentifier("discoverTitle")
            Label(discovery.activeLocation.map { "Rond \($0.name)" } ?? "Kies een locatie", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.travelTeal)
                .accessibilityIdentifier("discoveryLocationContext")
            TextField("Wijzig locatie", text: $locationQuery).textFieldStyle(.roundedBorder).submitLabel(.search)
                .accessibilityIdentifier("discoveryLocationField")
                .onSubmit { Task { await discovery.searchPlace(locationQuery, radiusMeters: providerRadius) } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(DiscoveryFeed.allCases) { feed in
                    chip(feed.title, selected: discovery.selectedFeed == feed) { Task { await discovery.selectFeed(feed, radiusMeters: providerRadius) } }
                } }
            }
            Text("Categorieën").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(DiscoveryCategory.allCases) { category in
                    chip(category.title, selected: discovery.selectedFeed == nil && discovery.selectedCategory == category) { Task { await discovery.select(category, radiusMeters: providerRadius) } }
                } }
            }
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.reizzFilterSelectedForeground : Color.reizzFilterInactiveForeground)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(selected ? Color.reizzFilterSelectedBackground : Color.reizzFilterInactiveBackground,
                        in: Capsule())
        }
            .buttonStyle(.plain)
            .accessibilityValue(selected ? "Geselecteerd" : "Niet geselecteerd")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var resultToolbar: some View {
        HStack(spacing: 10) {
            Picker("Weergave", selection: $displayMode) {
                Label("Lijst", systemImage: "list.bullet").tag(DiscoveryDisplayMode.list)
                Label("Kaart", systemImage: "map").tag(DiscoveryDisplayMode.map)
            }.pickerStyle(.segmented).frame(maxWidth: 190).accessibilityIdentifier("discoveryDisplayMode")
            Spacer()
            Menu { Picker("Sortering", selection: $sort) { ForEach(DiscoverySort.allCases) { Text($0.title).tag($0) } } }
                label: { Label(sort.title, systemImage: "arrow.up.arrow.down") }
            Button { showsFilters = true } label: {
                Label(filters.activeCount == 0 ? "Filters" : "Filters (\(filters.activeCount))", systemImage: "line.3.horizontal.decrease.circle.fill")
            }.accessibilityIdentifier("discoveryFilters")
        }.font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.bottom, 10)
    }

    @ViewBuilder private var discoveryContent: some View {
        switch discovery.state {
        case .idle: ContentUnavailableView("Kies een locatie", systemImage: "mappin.and.ellipse", description: Text("Zoek op een plaats, hotel of adres."))
        case .loading: DiscoveryLoadingView()
        case .failed:
            ContentUnavailableView { Label("Ontdekken heeft internet nodig", systemImage: "wifi.slash") }
                description: { Text("Controleer je verbinding en probeer opnieuw.") }
                actions: { Button("Opnieuw proberen") { Task { await discovery.refresh() } }.buttonStyle(.borderedProminent) }
        case .empty, .loaded:
            if visibleResults.isEmpty { emptyState } else if displayMode == .list { resultList } else { resultMap }
        }
    }

    private var resultList: some View {
        ScrollView { LazyVStack(spacing: 14) { ForEach(visibleResults) { result in
            Button { selectedResult = result } label: {
                DiscoveryCard(result: result, isSaved: tripStore.isDiscoverySaved(result),
                    isPlanned: tripStore.trip.map { DiscoveryDuplicateDetector().contains(result, in: $0) } ?? false)
            }.buttonStyle(.plain)
        } }.padding(.horizontal, 20).padding(.bottom, 28) }.accessibilityIdentifier("discoveryResultList")
    }

    private var resultMap: some View {
        Map(position: $mapPosition, selection: $selectedMapID) {
            ForEach(visibleResults) { result in
                Marker(result.name, systemImage: result.category.symbolName, coordinate: .init(latitude: result.latitude, longitude: result.longitude))
                    .tint(Color.travelTeal).tag(result.id)
            }
        }.mapControls { MapCompass(); MapScaleView() }.onMapCameraChange { mapRegion = $0.region }
            .overlay(alignment: .top) { if shouldSearchVisibleArea { Button("Zoek in dit gebied") { searchVisibleArea() }.buttonStyle(.borderedProminent).tint(Color.travelTeal).padding(10).accessibilityIdentifier("searchThisArea") } }
            .safeAreaInset(edge: .bottom) { if let result = visibleResults.first(where: { $0.id == selectedMapID }) { DiscoveryMapPreview(result: result, onDetails: { selectedResult = result }).padding(.horizontal, 16).padding(.bottom, 8) } }
            .accessibilityIdentifier("discoveryMap")
    }

    private var emptyState: some View {
        ContentUnavailableView { Label("Geen resultaten binnen deze filters", systemImage: "line.3.horizontal.decrease.circle") }
            description: { Text("Vergroot de afstand of wis je filters.") }
            actions: { Button("Vergroot afstand") { filters.maxDistanceMeters = 25_000 }; Button("Wis filters") { filters = DiscoveryFilters(maxDistanceMeters: nil) } }
            .accessibilityIdentifier("discoveryEmptyState")
    }

    private var visibleResults: [DiscoveryResult] {
        let filtered = discovery.results.filter { filters.includes($0, category: discovery.selectedCategory) }
        return switch sort { case .recommended: filtered; case .distance: filtered.sorted { ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude) }; case .rating: filtered.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }; case .reviewCount: filtered.sorted { ($0.reviewCount ?? 0) > ($1.reviewCount ?? 0) } }
    }
    private var providerRadius: Double { filters.maxDistanceMeters ?? 25_000 }
    private var navigationContextKey: String { navigationState.discoverLocation.map { "\($0.latitude)-\($0.longitude)-\(navigationState.discoverCategory.rawValue)" } ?? "auto-\(tripStore.dataRevision)" }
    private func establishContext() async {
        if let location = navigationState.discoverLocation { await discovery.activate(location, category: navigationState.discoverCategory, radiusMeters: providerRadius); return }
        guard discovery.activeLocation == nil, let trip = tripStore.trip else { return }
        let date = UITestConfiguration.selectedDate ?? Date()
        let tripLocation = await TripSearchLocationResolver(geocoder: geocoder).resolve(for: date, in: trip)
            ?? trip.destinations.first.map({ SearchLocation(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) })
        let current = UITestConfiguration.isEnabled ? nil : await deviceLocation.currentLocation()
        let location = current.flatMap { value in
            guard let tripLocation else { return nil }
            let distance = CLLocation(latitude: value.latitude, longitude: value.longitude)
                .distance(from: CLLocation(latitude: tripLocation.latitude, longitude: tripLocation.longitude))
            return distance <= 100_000 ? value : nil
        } ?? tripLocation
        if let location {
            await discovery.activate(location, category: .restaurant, radiusMeters: providerRadius)
            await discovery.selectFeed(.forYou, radiusMeters: providerRadius)
        }
    }
    private var shouldSearchVisibleArea: Bool { guard let mapRegion, let searchedRegion else { return false }; return hypot(mapRegion.center.latitude - searchedRegion.center.latitude, mapRegion.center.longitude - searchedRegion.center.longitude) > 0.02 }
    private func searchVisibleArea() { guard let region = mapRegion else { return }; searchedRegion = region; let location = SearchLocation(name: "kaartgebied", latitude: region.center.latitude, longitude: region.center.longitude); Task { await discovery.activate(location, category: discovery.selectedCategory, radiusMeters: providerRadius) } }
    private func restoreFilters() { filters.maxDistanceMeters = storedDistance <= 0 ? nil : storedDistance; filters.minimumRating = storedRating <= 0 ? nil : storedRating; filters.minimumReviewCount = storedReviews <= 0 ? nil : storedReviews; filters.openNowOnly = storedOpenNow }
    private func persist(_ value: DiscoveryFilters) { storedDistance = value.maxDistanceMeters ?? 0; storedRating = value.minimumRating ?? 0; storedReviews = value.minimumReviewCount ?? 0; storedOpenNow = value.openNowOnly }
}

private enum DiscoveryDisplayMode: String { case list, map }

struct DiscoveryCard: View {
    let result: DiscoveryResult; let isSaved: Bool; let isPlanned: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoveryPhotoView(photo: result.previewPhoto, category: result.category,
                               maxPixelWidth: 720, maxPixelHeight: 405,
                               accessibilityIdentifier: result.previewPhoto == nil
                                   ? "discoveryPhotoFallback.\(result.id)" : "discoveryPhoto.\(result.id)")
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if let photo = result.previewPhoto {
                        Text(photo.authors.isEmpty ? "Google Maps" : "\(photo.authors.map(\.displayName).joined(separator: ", ")) · Google Maps")
                            .font(.caption2).foregroundStyle(.white)
                            .lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.58), in: Capsule()).padding(7)
                    }
                }
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(result.name).font(.headline).lineLimit(2); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                Text(result.primaryType ?? result.category.title).font(.caption.weight(.semibold)).foregroundStyle(Color.travelTeal)
                HStack(spacing: 8) { if let rating = result.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }; if let count = result.reviewCount { Text("(\(count.formatted()))") }; if let price = result.priceLevel { Text(price.title) } }.font(.caption).foregroundStyle(.secondary)
                if let distance = result.distanceMeters { Label(DiscoveryDistanceFormatter.string(meters: distance), systemImage: "location").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 5) { if result.isOpenNow == true { badge("Open", color: .travelGreen) }; if result.isOpenNow == false { badge("Gesloten", color: .travelCoral) }; if result.badges.contains(.hiddenGem) { badge("Verborgen parel", color: .travelSun) }; if isPlanned { badge("In reis", color: .travelTeal) } else if isSaved { badge("Bewaard", color: .travelPurple) } }
                if let reason { Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }.background(.background, in: RoundedRectangle(cornerRadius: 22)).clipShape(RoundedRectangle(cornerRadius: 22)).travelCardShadow()
            .accessibilityElement(children: .contain).accessibilityIdentifier("discoveryCard.\(result.id)")
    }
    private var reason: String? { if !result.editorialSignals.isEmpty { return "Genoemd door \(Set(result.editorialSignals.map(\.source)).count) reisgids(en)" }; if (result.reviewCount ?? 0) >= 1_000 { return "Veel betrouwbare beoordelingen" }; if result.badges.contains(.hiddenGem) { return "Sterk beoordeeld, buiten de grootste hotspots" }; return nil }
    private func badge(_ text: String, color: Color) -> some View { Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3).background(color.opacity(0.18), in: Capsule()) }
}

private struct DiscoveryDetailView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppFeedbackState.self) private var feedback
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.mapOpening) private var mapOpening
    @Environment(\.dismiss) private var dismiss
    let result: DiscoveryResult
    @State private var showsAdd = false
    @State private var addedItem: ManagedTripItem?
    @State private var showsCover = false
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            DiscoveryPhotoView(photo: result.previewPhoto, category: result.category,
                               maxPixelWidth: 1_440, maxPixelHeight: 960,
                               accessibilityIdentifier: result.previewPhoto == nil
                                   ? "discoveryDetailPhotoFallback" : "discoveryDetailPhoto")
                .aspectRatio(3 / 2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 24))
            if let photo = result.previewPhoto { DiscoveryPhotoAttribution(photo: photo) }
            Text(result.name).font(.largeTitle.bold()); metadata
            if !result.editorialSignals.isEmpty { editorial }
            Map(initialPosition: .region(TripMapRegionBuilder.region(around: SearchLocation(name: result.name, latitude: result.latitude, longitude: result.longitude), radiusMeters: 1_500))) { Marker(result.name, coordinate: .init(latitude: result.latitude, longitude: result.longitude)) }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 20)).allowsHitTesting(false)
            HStack { action("Navigeer", symbol: "location.fill") { Task { await DiscoveryMapActions(opener: mapOpening).navigate(result) } }; action(store.isDiscoverySaved(result) ? "Bewaard" : "Bewaar", symbol: store.isDiscoverySaved(result) ? "bookmark.fill" : "bookmark") { if store.saveDiscovery(result) { feedback.show("Plek bewaard") } } }
            Button { showsAdd = true } label: { Label(planned ? "Gepland" : "Voeg aan dag toe", systemImage: planned ? "checkmark.circle.fill" : "calendar.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(Color.travelTeal).disabled(planned).accessibilityIdentifier("addDiscoveryToDay")
        }.padding(20) }.navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Sluit") { dismiss() } } }
            .sheet(isPresented: $showsAdd) { DiscoveryAddToDaySheet(result: result) { item in addedItem = item } }
            .sheet(isPresented: $showsCover) { if let item = addedItem { CoverEditorView(itemID: item.id, kind: item.kind) } }
            .confirmationDialog("Toegevoegd aan je reis", isPresented: Binding(get: { addedItem != nil && !showsCover }, set: { if !$0 { addedItem = nil } })) { Button("Bekijk Vandaag") { addedItem = nil; dismiss(); navigation.selectedTab = .today }; Button("Omslag kiezen") { showsCover = true }; Button("Gereed") { addedItem = nil } } message: { Text("Je kunt nu een lokale, exporteerbare omslag kiezen via de bestaande beeldzoeker.") }
        }.accessibilityIdentifier("discoveryDetail")
    }
    private var planned: Bool { store.trip.map { DiscoveryDuplicateDetector().contains(result, in: $0) } ?? false }
    private var metadata: some View { VStack(alignment: .leading, spacing: 8) { Label(result.primaryType ?? result.category.title, systemImage: result.category.symbolName); if let rating = result.rating { Text("\(rating, specifier: "%.1f") ★ (\((result.reviewCount ?? 0).formatted()))") }; if let distance = result.distanceMeters { Label(DiscoveryDistanceFormatter.string(meters: distance), systemImage: "location") }; if let address = result.address { Text(address) }; if let isOpen = result.isOpenNow { Label(isOpen ? "Nu open" : "Nu gesloten", systemImage: "clock") }; if let website = result.websiteURL { Link("Website", destination: website) } }.font(.subheadline).foregroundStyle(.secondary) }
    private var editorial: some View { VStack(alignment: .leading, spacing: 8) { Text("Bronvermeldingen").font(.headline); ForEach(result.editorialSignals, id: \.self) { signal in if let url = signal.sourceURL { Link(signal.source.title, destination: url) } else { Text(signal.source.title) } } } }
    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View { Button(action: perform) { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
}

private struct DiscoveryAddToDaySheet: View {
    @Environment(TripStore.self) private var store
    @Environment(AppFeedbackState.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    let result: DiscoveryResult; let onAdded: (ManagedTripItem) -> Void
    @State private var date = UITestConfiguration.selectedDate ?? Date(); @State private var time = Date(); @State private var duplicate = false
    var body: some View { NavigationStack { Form { Section("Planning") { DatePicker("Datum", selection: $date, in: dateRange, displayedComponents: .date); DatePicker("Tijd", selection: $time, displayedComponents: .hourAndMinute); LabeledContent("Type", value: DiscoveryTripItemMapper().kind(for: result.category).title) }; Section { Button("Voeg toe") { add() }.frame(maxWidth: .infinity).accessibilityIdentifier("confirmAddDiscovery") } }.navigationTitle("Voeg aan dag toe").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } } }.alert("Deze plek staat al op deze dag", isPresented: $duplicate) { Button("OK", role: .cancel) {} } } }
    private var dateRange: ClosedRange<Date> { guard let trip = store.trip else { return Date()...Date() }; return trip.startDate...trip.endDate }
    private func add() { guard let trip = store.trip else { return }; if DiscoveryDuplicateDetector().contains(result, on: date, in: trip) { duplicate = true; return }; let item = DiscoveryTripItemMapper().item(from: result, date: date, time: time, trip: trip); guard store.saveManagedItem(item) else { return }; feedback.show("Toegevoegd aan \(AppFormatters.shortDate(in: trip.timeZone).string(from: date))"); dismiss(); onAdded(item) }
}

private struct DiscoveryMapPreview: View {
    @Environment(TripStore.self) private var store; @Environment(\.mapOpening) private var opener
    let result: DiscoveryResult; let onDetails: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 8) { HStack(spacing: 12) { DiscoveryPhotoView(photo: result.previewPhoto, category: result.category, maxPixelWidth: 320, maxPixelHeight: 180, accessibilityIdentifier: result.previewPhoto == nil ? "discoveryMapPhotoFallback" : "discoveryMapPhoto").frame(width: 112, height: 72).clipShape(RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 4) { Text(result.name).font(.headline).lineLimit(2); if let rating = result.rating { Text("\(rating, specifier: "%.1f") ★ (\((result.reviewCount ?? 0).formatted()))").font(.caption) }; if let photo = result.previewPhoto { DiscoveryPhotoAttribution(photo: photo, compact: true) } } }; HStack { Button("Details", action: onDetails).buttonStyle(.bordered); Button("Navigeer") { Task { await DiscoveryMapActions(opener: opener).navigate(result) } }.buttonStyle(.borderedProminent).tint(.travelTeal); Button { _ = store.saveDiscovery(result) } label: { Image(systemName: store.isDiscoverySaved(result) ? "bookmark.fill" : "bookmark") }.buttonStyle(.bordered) } }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
}

private struct DiscoveryLoadingView: View { var body: some View { ScrollView { LazyVStack(spacing: 14) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 22).fill(.quaternary).frame(height: 156).overlay(alignment: .leading) { VStack(alignment: .leading, spacing: 10) { RoundedRectangle(cornerRadius: 4).fill(.tertiary).frame(width: 180, height: 18); RoundedRectangle(cornerRadius: 4).fill(.tertiary).frame(width: 120, height: 12) }.padding(20) } } }.padding(.horizontal, 20) }.accessibilityLabel("Resultaten laden") } }

private struct DiscoveryFilterSheet: View {
    @Binding var filters: DiscoveryFilters; @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { Form {
        Section("Afstand") { Picker("Maximaal", selection: $filters.maxDistanceMeters) { Text("Alles").tag(Double?.none); ForEach([1,2,5,10,25], id: \.self) { Text("\($0) km").tag(Optional(Double($0 * 1000))) } } }
        Section("Waardering") { Picker("Minimaal", selection: $filters.minimumRating) { Text("Alle").tag(Double?.none); ForEach([4.0,4.3,4.5,4.7], id: \.self) { Text("\($0, specifier: "%.1f")+").tag(Optional($0)) } } }
        Section("Aantal beoordelingen") { Picker("Minimaal", selection: $filters.minimumReviewCount) { Text("Geen minimum").tag(Int?.none); ForEach([50,100,500,1000], id: \.self) { Text("\($0)+").tag(Optional($0)) } } }
        Section("Prijs") { ForEach(DiscoveryPriceLevel.allCases, id: \.self) { level in Toggle(level.title, isOn: Binding(get: { filters.priceLevels.contains(level) }, set: { if $0 { filters.priceLevels.insert(level) } else { filters.priceLevels.remove(level) } })) } }
        Section("Nu") { Toggle("Alleen nu open", isOn: $filters.openNowOnly); Toggle("Verborgen parels", isOn: $filters.hiddenGemOnly); Toggle("Bijzonder", isOn: $filters.starWorthyOnly) }
        Section("Categorie") { ForEach(DiscoveryCategory.allCases.filter(\.supportsRecommendations)) { category in Toggle(category.title, isOn: Binding(get: { filters.categories.contains(category) }, set: { if $0 { filters.categories.insert(category) } else { filters.categories.remove(category) } })) } }
        Section { Button("Wis filters") { filters = DiscoveryFilters() }.foregroundStyle(Color.travelCoral) }
    }.navigationTitle("Filters").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Toepassen") { dismiss() } } } } }
}
