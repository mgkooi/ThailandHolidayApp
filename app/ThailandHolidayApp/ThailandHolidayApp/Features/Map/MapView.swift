import MapKit
import SwiftUI

struct MapView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(AppNavigationState.self) private var navigationState
    @Environment(\.mapSearchProvider) private var searchProvider
    @Environment(\.mapOpening) private var mapOpening
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var mapSelection: MapSelection<String>?
    @State private var nativeSelectionGeneration = 0
    @State private var query = ""
    @State private var results: [MapPlace] = []
    @State private var isSearching = false
    @State private var selectedPlace: MapPlace?
    @State private var placeForTypeSelection: MapPlace?
    @State private var addRequest: MapAddRequest?
    @State private var duplicate: TripMapAnnotation?
    @State private var duplicateRequest: MapAddRequest?

    private var annotations: [TripMapAnnotation] {
        tripStore.trip.map { TripMapAnnotationBuilder(airportLookup: AirportLookup()).annotations(for: $0) } ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                Map(position: $position, selection: $mapSelection) {
                    ForEach(annotations) { annotation in
                        Annotation(annotation.title, coordinate: annotation.coordinate) {
                            mapPin(symbol: annotation.type.symbolName, color: pinColor(annotation))
                                .accessibilityLabel(annotation.title)
                        }.tag(annotation.id)
                    }
                    ForEach(results) { place in
                        Marker(place.name, systemImage: "magnifyingglass", coordinate: .init(latitude: place.latitude, longitude: place.longitude))
                            .tint(Color.travelOrange)
                            .tag(place.id)
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange { context in visibleRegion = context.region }
                .safeAreaInset(edge: .bottom) { detailCard.padding(.horizontal, 16).padding(.bottom, 8) }
            }
            .navigationTitle("Kaart")
            .toolbar { TripContextToolbar() }
            .task(id: focusKey) { applyFocus() }
            .onChange(of: selectedID) { _, value in
                if let value, let place = results.first(where: { $0.id == value }) {
                    selectedPlace = place
                } else { selectedPlace = nil }
            }
            .onChange(of: mapSelection) { _, selection in
                nativeSelectionGeneration += 1
                let generation = nativeSelectionGeneration
                if let id = selection?.value {
                    selectedID = id
                    selectedPlace = results.first { $0.id == id }
                } else if let feature = selection?.feature {
                    selectedID = nil
                    Task {
                        if let place = try? await NativeMapFeatureResolver().place(for: feature) {
                            guard generation == nativeSelectionGeneration else { return }
                            selectedPlace = place
                        }
                    }
                }
            }
            .confirmationDialog("Wat wil je toevoegen?", item: $placeForTypeSelection) { place in
                if place.isViewpoint {
                    Button("Toevoegen als Viewpoint") { prepareAdd(place: place, kind: .activity, asViewpoint: true) }
                }
                ForEach(MapAddRequest.supportedKinds) { kind in
                    Button(kind.title) { prepareAdd(place: place, kind: kind) }
                }
                Button("Annuleer", role: .cancel) {}
            }
            .alert("Deze locatie lijkt al in deze reis te staan.", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate=nil } })) {
                Button("Bekijk bestaande") { selectedID = duplicate?.id; duplicate=nil }
                Button("Toch toevoegen") {
                    addRequest = duplicateRequest
                    duplicate=nil
                }
                Button("Annuleer", role: .cancel) { duplicate=nil }
            }
            .sheet(item: $addRequest) { request in
                NavigationStack {
                    TripItemEditorView(kind: request.kind,
                        extraction: request.asViewpoint ? viewpointExtraction(for: request.place) : nil,
                        mapPlace: request.place)
                }
            }
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Zoek locatie", text: $query).textFieldStyle(.roundedBorder).submitLabel(.search)
                    .onSubmit { Task { await search() } }.accessibilityIdentifier("mapSearchField")
                if isSearching { ProgressView() }
                else { Button { Task { await search() } } label: { Image(systemName: "magnifyingglass") } }
            }
            if !results.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(results.prefix(10)) { place in
                            Button {
                                select(place)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(place.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(place.placeName ?? place.address ?? "Locatie").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Color.travelBackground)
    }

    @ViewBuilder private var detailCard: some View {
        if let selectedPlace {
            MapPlaceCard(place: selectedPlace, showAdd: true) { placeForTypeSelection = selectedPlace }
        } else if let selected = annotations.first(where: { $0.id == selectedID }) {
            MapAnnotationCard(annotation: selected)
        }
    }

    private func search() async {
        isSearching=true; defer { isSearching=false }
        results = (try? await searchProvider.search(query: query, visibleRegion: visibleRegion)) ?? []
        if let first=results.first { select(first) }
    }
    private func select(_ place: MapPlace) {
        selectedPlace=place; selectedID=place.id
        position = .region(TripMapRegionBuilder.region(around: SearchLocation(name: place.name, latitude: place.latitude, longitude: place.longitude), radiusMeters: 2_000))
    }
    private func prepareAdd(place: MapPlace, kind: TripItemKind, asViewpoint: Bool = false) {
        if let trip=tripStore.trip, let match=TripMapDuplicateDetector().duplicate(of: place, in: trip) {
            duplicate=match; duplicateRequest=MapAddRequest(place:place,kind:kind,asViewpoint:asViewpoint)
        } else { addRequest=MapAddRequest(place: place, kind: kind, asViewpoint: asViewpoint) }
    }
    private func viewpointExtraction(for place: MapPlace) -> BookingExtractionResult {
        BookingExtractionResult(detectedType: .activity, classificationConfidence: 1,
            fields: ["title": .init(value: place.name, confidence: 1),
                     "placeName": .init(value: place.placeName ?? place.name, confidence: 1),
                     "activityCategory": .init(value: "viewpoint", confidence: 1)],
            warnings: [], originalRecognizedText: "", normalizedText: "")
    }
    private var focusKey: String {
        guard let focus=navigationState.mapFocus else { return "automatic-\(tripStore.dataRevision)" }
        return "\(focus.latitude)-\(focus.longitude)-\(tripStore.dataRevision)"
    }
    private func applyFocus() {
        if let focus=navigationState.mapFocus { position = .region(TripMapRegionBuilder.region(around: focus)) }
        else if let first=annotations.first { position = .region(TripMapRegionBuilder.region(around: SearchLocation(name:first.title,latitude:first.coordinate.latitude,longitude:first.coordinate.longitude))) }
        else { position = .automatic }
    }
    private func mapPin(symbol:String,color:Color)->some View { Image(systemName:symbol).font(.callout.weight(.bold)).foregroundStyle(.white).frame(width:34,height:34).background(color,in:Circle()).overlay(Circle().stroke(.white,lineWidth:2)) }
    private func pinColor(_ annotation:TripMapAnnotation)->Color {
        if let focusDate=navigationState.mapFocusDate, let trip=tripStore.trip, let date=annotation.date,
           TripCalendar.calendar(in:trip.timeZone).isDate(date,inSameDayAs:focusDate) { return .travelCoral }
        return .travelTeal
    }
}

private struct MapAddRequest: Identifiable {
    let id=UUID(); let place:MapPlace; let kind:TripItemKind; var asViewpoint = false
    static let supportedKinds:[TripItemKind] = [.accommodation,.restaurant,.activity,.transfer,.rentalVehicle,.ferry,.train,.other]
}

private extension MapPlace {
    var isViewpoint: Bool {
        let value = [category, name].compactMap { $0 }.joined(separator: " ").lowercased()
        return ["viewpoint", "lookout", "observation point", "scenic"].contains { value.contains($0) }
    }
}

struct MapPlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mapSearchProvider) private var searchProvider
    let onSelect:(MapPlace)->Void
    @State private var query=""
    @State private var results:[MapPlace]=[]
    @State private var selected:MapPlace?
    @State private var position:MapCameraPosition = .automatic
    @State private var region:MKCoordinateRegion?
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                TextField("Zoek locatie",text:$query).textFieldStyle(.roundedBorder).submitLabel(.search)
                    .onSubmit { Task { results=(try? await searchProvider.search(query:query,visibleRegion:region)) ?? []; if let first=results.first { choose(first) } } }
                    .padding()
                List(results) { place in Button { choose(place) } label: { VStack(alignment:.leading) { Text(place.name); Text(place.placeName ?? place.address ?? "").font(.caption).foregroundStyle(.secondary) } } }.frame(maxHeight: results.isEmpty ? 0 : 180)
                Map(position:$position) {
                    if let selected { Marker(selected.name,coordinate:.init(latitude:selected.latitude,longitude:selected.longitude)) }
                }.onMapCameraChange { region=$0.region }
                if let selected {
                    Button("Gebruik deze locatie") { onSelect(selected); dismiss() }.buttonStyle(.borderedProminent).tint(.travelTeal).padding()
                }
            }.navigationTitle("Kies locatie").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Annuleer") { dismiss() } } }
        }
    }
    private func choose(_ place:MapPlace) { selected=place; position = .region(TripMapRegionBuilder.region(around:SearchLocation(name:place.name,latitude:place.latitude,longitude:place.longitude),radiusMeters:1_500)) }
}

private struct MapPlaceCard: View {
    @Environment(\.mapOpening) private var opener
    let place:MapPlace; let showAdd:Bool; let add:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(place.name).font(.headline)
            if let locality=place.placeName { Text(locality).font(.subheadline).foregroundStyle(.secondary) }
            if let address=place.address { Text(address).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Ontdek") { Task { _=await opener.openPlace(place.location,name:place.name) } }.buttonStyle(.bordered)
                Button("Navigeer") { Task { _=await opener.navigate(to:place.location,name:place.name) } }.buttonStyle(.borderedProminent).tint(.travelTeal)
                if showAdd { Button("Toevoegen",action:add).buttonStyle(.bordered) }
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
    }
}

private struct MapAnnotationCard:View {
    @Environment(\.mapOpening) private var opener
    let annotation:TripMapAnnotation
    var body:some View { VStack(alignment:.leading,spacing:8) { Label(annotation.title,systemImage:annotation.type.symbolName).font(.headline); Text(annotation.type.title).font(.caption.weight(.semibold)).foregroundStyle(Color.travelTeal); if let subtitle=annotation.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }; Button { Task { _ = await opener.navigate(to: annotation.location,name:annotation.title) } } label:{ Label("Navigeer",systemImage:"arrow.triangle.turn.up.right.diamond.fill") }.buttonStyle(.borderedProminent).tint(.travelTeal) }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20)) }
}

private extension View {
    func confirmationDialog<Item, Actions: View>(_ title: String, item: Binding<Item?>, @ViewBuilder actions: @escaping (Item) -> Actions) -> some View {
        confirmationDialog(title, isPresented: Binding(get:{ item.wrappedValue != nil },set:{ if !$0 { item.wrappedValue=nil } })) {
            if let value=item.wrappedValue { actions(value) }
        }
    }
}
