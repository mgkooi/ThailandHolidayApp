import SwiftUI

struct DiscoverView: View {
    @Environment(DiscoverySession.self) private var discovery
    @Environment(AppNavigationState.self) private var navigationState
    @State private var locationQuery = ""
    @State private var filters = DiscoveryFilters()
    @State private var showsFilters = false
    @State private var resultToAdd: DiscoveryResult?

    var body: some View {
        @Bindable var discovery = discovery
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Zoek plaats of locatie", text: $locationQuery)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .accessibilityIdentifier("discoveryLocationField")
                        .onSubmit { Task { await discovery.searchPlace(locationQuery, radiusMeters: providerRadius) } }

                    if let location = discovery.activeLocation {
                        Text("Ontdekken rond \(location.name)")
                            .font(.headline)
                            .accessibilityIdentifier("discoveryLocationContext")
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DiscoveryCategory.allCases) { category in
                                Button(category.title) { Task { await discovery.select(category, radiusMeters: providerRadius) } }
                                    .buttonStyle(.borderedProminent)
                                    .tint(discovery.selectedCategory == category ? Color.travelTeal : Color.secondary.opacity(0.25))
                                    .accessibilityAddTraits(discovery.selectedCategory == category ? .isSelected : [])
                            }
                        }
                    }
                    if discovery.selectedCategory.supportsRecommendations {
                        Button { showsFilters = true } label: {
                            Label(filters.activeCount == 0 ? "Filters" : "Filters (\(filters.activeCount))",
                                  systemImage: "line.3.horizontal.decrease.circle")
                        }.buttonStyle(.bordered)
                    }
                }
                .padding(20)

                discoveryContent
            }
            .background(Color.travelBackground)
            .navigationTitle("Ontdekken")
            .toolbar { TripContextToolbar() }
            .refreshable { await discovery.refresh(radiusMeters: providerRadius) }
            .sheet(isPresented: $showsFilters) {
                DiscoveryFilterSheet(filters: $filters, showsPrice: discovery.selectedCategory.supportsPrice)
            }
            .onChange(of: showsFilters) { wasShowing, isShowing in
                if wasShowing && !isShowing { Task { await discovery.refresh(radiusMeters: providerRadius) } }
            }
            .sheet(item: $resultToAdd) { result in
                NavigationStack {
                    TripItemEditorView(kind: result.category == .restaurant ? .restaurant : .activity,
                        extraction: extraction(for: result), mapPlace: mapPlace(for: result))
                }
            }
            .task(id: navigationContextKey) {
                guard let location = navigationState.discoverLocation else { return }
                await discovery.activate(location, category: navigationState.discoverCategory,
                                         radiusMeters: providerRadius)
            }
        }
    }

    @ViewBuilder private var discoveryContent: some View {
        switch discovery.state {
        case .idle:
            ContentUnavailableView("Kies een locatie", systemImage: "mappin.and.ellipse",
                description: Text("Zoek op een plaats, hotel of adres."))
        case .loading:
            ProgressView("Locaties zoeken…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("Geen resultaten gevonden in deze omgeving.", systemImage: "magnifyingglass")
        case .failed:
            ContentUnavailableView("Locaties konden tijdelijk niet worden geladen", systemImage: "exclamationmark.triangle")
        case .loaded:
            if filteredResults.isEmpty {
                ContentUnavailableView("Geen resultaten gevonden in deze omgeving.", systemImage: "magnifyingglass")
            } else {
                List(filteredResults) { result in
                    DiscoveryResultRow(result: result,
                        onAdd: [.activity, .viewpoint, .restaurant].contains(discovery.selectedCategory) ? { resultToAdd = result } : nil)
                        .listRowBackground(result.id == navigationState.discoverResultID
                            ? Color.travelSun.opacity(0.18) : Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filteredResults: [DiscoveryResult] {
        guard discovery.selectedCategory.supportsRecommendations else { return discovery.results }
        return discovery.results.filter { filters.includes($0, category: discovery.selectedCategory) }
    }

    private var providerRadius: Double { filters.maxDistanceMeters ?? 25_000 }

    private func extraction(for result: DiscoveryResult) -> BookingExtractionResult {
        var fields: [String: ExtractedBookingField] = [
            "placeName": .init(value: result.name, confidence: 1)
        ]
        fields[result.category == .restaurant ? "name" : "title"] = .init(value: result.name, confidence: 1)
        if let address = result.address { fields["address"] = .init(value: address, confidence: 1) }
        if let url = result.websiteURL { fields["url"] = .init(value: url.absoluteString, confidence: 1) }
        if result.category == .viewpoint { fields["activityCategory"] = .init(value: "viewpoint", confidence: 1) }
        return BookingExtractionResult(detectedType: result.category == .restaurant ? .restaurant : .activity,
                                       classificationConfidence: 1, fields: fields,
                                       warnings: [], originalRecognizedText: "", normalizedText: "")
    }

    private func mapPlace(for result: DiscoveryResult) -> MapPlace {
        MapPlace(id: result.id, name: result.name, category: result.category.rawValue,
                 placeName: result.name, address: result.address, latitude: result.latitude,
                 longitude: result.longitude, phone: result.phone, websiteURL: result.websiteURL)
    }

    private var navigationContextKey: String {
        guard let location = navigationState.discoverLocation else { return "none" }
        return "\(location.latitude)-\(location.longitude)-\(navigationState.discoverCategory.rawValue)"
    }
}

private struct DiscoveryResultRow: View {
    @Environment(\.mapOpening) private var mapOpening
    let result: DiscoveryResult
    let onAdd: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: result.category.symbolName).foregroundStyle(Color.travelTeal)
                Text(result.name).font(.headline)
                Spacer()
                if let distance = result.distanceMeters {
                    Text(DiscoveryDistanceFormatter.string(meters: distance))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if let address = result.address { Text(address).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                if let rating = result.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                if let count = result.reviewCount { Text("\(count) beoordelingen") }
                if let price = result.priceLevel { Text(price.title) }
            }.font(.caption).foregroundStyle(.secondary)
            if !result.badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(RecommendationBadge.allCases.filter(result.badges.contains), id: \.self) { badge in
                        Text(badge.title).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.travelSun.opacity(0.2), in: Capsule())
                    }
                }
            }
            if !result.editorialSignals.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aanbevolen door:").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(result.editorialSignals, id: \.self) { signal in
                            if let url = signal.sourceURL {
                                Link(signal.source.title, destination: url).font(.caption.weight(.semibold))
                            } else {
                                Text(signal.source.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    Task { await DiscoveryMapActions(opener: mapOpening).discover(result) }
                } label: {
                    Label("Ontdek", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await DiscoveryMapActions(opener: mapOpening).navigate(result) }
                } label: {
                    Label("Navigeer", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Color.travelTeal)
            }
            if let onAdd {
                Button(action: onAdd) { Label("Toevoegen aan reis", systemImage: "plus.circle.fill") }
                    .buttonStyle(.bordered).tint(Color.travelGreen)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DiscoveryFilterSheet: View {
    @Binding var filters: DiscoveryFilters
    let showsPrice: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if showsPrice { Section("Prijs") {
                    ForEach(DiscoveryPriceLevel.allCases, id: \.self) { level in
                        Toggle(level.title, isOn: Binding(get: { filters.priceLevels.contains(level) }, set: {
                            if $0 { filters.priceLevels.insert(level) } else { filters.priceLevels.remove(level) }
                        }))
                    }
                } }
                Section("Waardering") {
                    Picker("Minimaal", selection: $filters.minimumRating) {
                        Text("Alle").tag(Double?.none)
                        ForEach([3.5, 4.0, 4.5], id: \.self) { Text("\($0, specifier: "%.1f")+").tag(Optional($0)) }
                    }
                }
                Section("Aantal beoordelingen") {
                    Picker("Minimaal", selection: $filters.minimumReviewCount) {
                        Text("Alle").tag(Int?.none)
                        ForEach([50, 100, 500, 1000], id: \.self) { Text("\($0)+").tag(Optional($0)) }
                    }
                }
                Section("Afstand") {
                    Picker("Maximaal", selection: $filters.maxDistanceMeters) {
                        Text("Alles").tag(Double?.none)
                        ForEach([1, 2, 5, 10, 25], id: \.self) { Text("\($0) km").tag(Optional(Double($0 * 1000))) }
                    }
                }
                Section("Speciaal") {
                    Toggle("Star Worthy", isOn: $filters.starWorthyOnly)
                    Toggle("Hidden Gem", isOn: $filters.hiddenGemOnly)
                    Toggle("Instagram Worthy", isOn: $filters.instagramWorthyOnly)
                }
                Section { Button("Wis filters") { filters = DiscoveryFilters() }.foregroundStyle(Color.travelCoral) }
            }
            .navigationTitle("Filters")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Toepassen") { dismiss() } } }
        }
    }
}
