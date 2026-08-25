import Observation
import PhotosUI
import OSLog
import SwiftUI
import UIKit

struct TripItemEditorView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(AppFeedbackState.self) private var feedbackState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locationGeocoder) private var locationGeocoder
    @Environment(\.mapOpening) private var mapOpening

    let kind: TripItemKind
    let itemID: UUID?
    let extraction: BookingExtractionResult?
    let scannedImageData: Data?
    let mapPlace: MapPlace?

    @State private var draft: TripItemDraft?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var confirmsDeletion = false
    @State private var isSaving = false
    @State private var targetTripID: UUID?
    @State private var showsMapPicker = false
    @State private var pendingMapPlace: MapPlace?
    @State private var showsRouteRole = false
    @State private var confirmsMapDuplicate = false
    @State private var mapDuplicateAcknowledged = false
    @State private var departureAirportSuggestions: [AirportInfo] = []
    @State private var arrivalAirportSuggestions: [AirportInfo] = []

    init(kind: TripItemKind, itemID: UUID? = nil, extraction: BookingExtractionResult? = nil,
         scannedImageData: Data? = nil, mapPlace: MapPlace? = nil, targetTripID: UUID? = nil) {
        self.kind = kind
        self.itemID = itemID
        self.extraction = extraction
        self.scannedImageData = scannedImageData
        self.mapPlace = mapPlace
        _targetTripID = State(initialValue: targetTripID)
    }

    var body: some View {
        Group {
            if let draft, let trip = editingTrip {
                editor(draft, trip: trip)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(itemID == nil ? "Nieuw \(kind.title.lowercased())" : kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { prepareDraft() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    draft?.replacementImageData = try await item.loadTransferable(type: Data.self)
                    draft?.removeAttachment = false
                } catch { errorMessage = "De afbeelding kon niet worden geladen." }
            }
        }
        .alert("Niet opgeslagen", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage ?? "Probeer het opnieuw.") }
        .confirmationDialog("Wil je dit reisitem verwijderen?", isPresented: $confirmsDeletion) {
            Button("Verwijder", role: .destructive) { deleteItem() }
            Button("Annuleer", role: .cancel) { }
        }
        .confirmationDialog("Hoe wil je deze locatie gebruiken?", isPresented: $showsRouteRole) {
            ForEach(MapPlaceRouteRole.allCases) { role in
                Button(role.title) { if let place=pendingMapPlace { draft?.apply(mapPlace: place, routeRole: role) }; pendingMapPlace=nil }
            }
            Button("Annuleer", role:.cancel) { pendingMapPlace=nil }
        }
        .sheet(isPresented: $showsMapPicker) {
            MapPlacePickerView { place in acceptMapPlace(place) }
        }
        .alert("Deze locatie lijkt al in deze reis te staan.", isPresented: $confirmsMapDuplicate) {
            Button("Bekijk bestaande") { dismiss() }
            Button("Toch toevoegen") { mapDuplicateAcknowledged=true; Task { await save() } }
            Button("Annuleer", role:.cancel) {}
        }
    }

    private var editingTrip: Trip? {
        if itemID == nil, let targetTripID { return tripStore.trip(id: targetTripID) ?? tripStore.trip }
        return tripStore.trip
    }

    private var navigationTarget: (location: TripLocation, name: String)? {
        guard let itemID, [.restaurant, .activity, .other].contains(kind),
              let item = tripStore.managedItem(id: itemID, kind: kind) else { return nil }
        return item.navigationTarget
    }

    private func editor(_ draft: TripItemDraft, trip: Trip) -> some View {
        @Bindable var draft = draft
        return Form {
            if itemID == nil {
                Section("Reis") {
                    Picker("Reis", selection: Binding(get: { targetTripID ?? tripStore.selectedTripId }, set: { targetTripID=$0 })) {
                        ForEach(tripStore.trips) { candidate in Text(candidate.name).tag(Optional(candidate.id)) }
                    }
                }
            }
            Section(kind.title) {
                if kind.showsGenericDate {
                    DatePicker("Datum", selection: $draft.date, displayedComponents: .date)
                }
                commonFields(draft, trip: trip)
                if kind != .flight {
                    Button { showsMapPicker=true } label: { Label("Zoek op kaart", systemImage:"map") }
                }
            }


            if let target = navigationTarget {
                Section {
                    Button { Task { _ = await mapOpening.navigate(to: target.location, name: target.name) } } label: {
                        Label("Navigeer", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                }
            }

            Section("Notities") {
                TextEditor(text: $draft.notes).frame(minHeight: 80)
            }

            Section("Boekingslink") {
                TextField("https://…", text: $draft.urlString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                if !draft.urlString.isEmpty, draft.validatedURL == nil {
                    Text("Vul een geldige http- of https-link in.").font(.caption).foregroundStyle(Color.travelCoral)
                }
            }

            Section("Boekingsbewijs") {
                if let image = previewImage(draft) {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasAttachment(draft) ? "Vervang afbeelding" : "Kies afbeelding", systemImage: "photo")
                }
                if hasAttachment(draft) {
                    Button("Verwijder afbeelding", role: .destructive) {
                        draft.replacementImageData = nil
                        draft.removeAttachment = true
                        photoItem = nil
                    }
                }
            }

            Section {
                Button("Bewaar") { Task { await save() } }
                    .frame(maxWidth: .infinity)
                    .disabled(!draft.isValid || isSaving)
                if itemID != nil {
                    Button("Verwijder reisitem", role: .destructive) { confirmsDeletion = true }
                        .frame(maxWidth: .infinity)
                }
                Button("Annuleer", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity)
            }
        }
        .environment(\.timeZone, trip.timeZone)
    }

    @ViewBuilder
    private func commonFields(_ draft: TripItemDraft, trip: Trip) -> some View {
        @Bindable var draft = draft
        switch kind {
        case .flight:
            TextField("Maatschappij", text: $draft.a)
            TextField("Vluchtnummer", text: $draft.b).textInputAutocapitalization(.characters)
            TextField("Vertrekluchthaven", text: $draft.c)
                .task(id: draft.c) { departureAirportSuggestions = await searchAirports(draft.c) }
            airportSuggestions(departureAirportSuggestions, draft: draft, isDeparture: true)
            TextField("Aankomstluchthaven", text: $draft.d)
                .task(id: draft.d) { arrivalAirportSuggestions = await searchAirports(draft.d) }
            airportSuggestions(arrivalAirportSuggestions, draft: draft, isDeparture: false)
            DatePicker("Vertrekdatum", selection: $draft.date, displayedComponents: .date)
            DatePicker("Vertrektijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            DatePicker("Aankomstdatum", selection: $draft.secondaryDate, displayedComponents: .date)
            DatePicker("Aankomsttijd", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            if !draft.hasValidFlightArrival(in: trip.timeZone) {
                Text("De aankomst moet na de vertrektijd liggen.")
                    .font(.caption)
                    .foregroundStyle(Color.travelCoral)
            }
            TextField("Vliegtuig", text: $draft.e)
            TextField("Reisklasse", text: $draft.f)
            TextField("Boekingsnummer", text: $draft.g)
        case .accommodation:
            TextField("Naam", text: $draft.a)
            TextField("Plaats", text: $draft.f)
            TextField("Adres", text: $draft.c)
            DatePicker("Check-in", selection: $draft.startTime)
            DatePicker("Check-out", selection: $draft.endTime)
            TextField("Kamertype", text: $draft.b)
            TextField("Boekingsnummer", text: $draft.g)
        case .transfer:
            Picker("Type", selection: $draft.transferType) {
                ForEach(TransferType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Aanbieder", text: $draft.a)
            TextField("Vertrekpunt", text: $draft.b)
            TextField("Bestemming", text: $draft.c)
            DatePicker("Vertrekdatum", selection: $draft.date, displayedComponents: .date)
            DatePicker("Vertrektijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            DatePicker("Aankomstdatum", selection: $draft.secondaryDate, displayedComponents: .date)
            DatePicker("Aankomst", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            TextField("Boekingsreferentie", text: $draft.d)
        case .ferry:
            TextField("Rederij", text: $draft.a)
            TextField("Vertreklocatie", text: $draft.b)
            TextField("Aankomstlocatie", text: $draft.c)
            DatePicker("Vertrekdatum", selection: $draft.date, displayedComponents: .date)
            DatePicker("Vertrektijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            DatePicker("Aankomstdatum", selection: $draft.secondaryDate, displayedComponents: .date)
            DatePicker("Aankomst", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            TextField("Boekingsreferentie", text: $draft.d)
        case .train:
            TextField("Vervoerder", text: $draft.a)
            TextField("Treinnummer", text: $draft.b)
            TextField("Vertrekstation", text: $draft.c)
            TextField("Aankomststation", text: $draft.d)
            DatePicker("Vertrekdatum", selection: $draft.date, displayedComponents: .date)
            DatePicker("Vertrektijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            DatePicker("Aankomstdatum", selection: $draft.secondaryDate, displayedComponents: .date)
            DatePicker("Aankomst", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            TextField("Rijtuig", text: $draft.e)
            TextField("Stoel", text: $draft.f)
            TextField("Boekingsnummer", text: $draft.g)
        case .rentalVehicle:
            Picker("Type vervoer", selection: $draft.rentalVehicleType) {
                ForEach(RentalVehicleType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Verhuurder", text: $draft.a)
            DatePicker("Ophaaldatum", selection: $draft.date, displayedComponents: .date)
            DatePicker("Ophaaltijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            TextField("Ophaallocatie", text: $draft.b)
            DatePicker("Inleverdatum", selection: $draft.secondaryDate, displayedComponents: .date)
            DatePicker("Inlevertijd", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            TextField("Inleverlocatie", text: $draft.c)
            TextField("Voertuig / model", text: $draft.d)
            TextField("Reserveringsnummer", text: $draft.e)
            TextField("Naam huurder", text: $draft.f)
        case .restaurant:
            TextField("Naam", text: $draft.a)
            DatePicker("Tijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            TextField("Adres", text: $draft.b)
            TextField("Reserveringsnaam", text: $draft.c)
            TextField("Reserveringsreferentie", text: $draft.d)
        case .activity:
            TextField("Titel", text: $draft.a)
            TextField("Plaats", text: $draft.c)
            TextField("Adres", text: $draft.locationAddress)
            DatePicker("Starttijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            DatePicker("Eindtijd", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            Picker("Categorie", selection: $draft.activityCategory) {
                ForEach(ItineraryCategory.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Beschrijving", text: $draft.b)
            TextField("Boekingsnummer", text: $draft.g)
        case .other:
            TextField("Titel", text: $draft.a)
            DatePicker("Starttijd", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            DatePicker("Eindtijd", selection: $draft.endTime, displayedComponents: .hourAndMinute)
            TextField("Locatie", text: $draft.b)
        }
    }

    @ViewBuilder
    private func airportSuggestions(_ suggestions: [AirportInfo], draft: TripItemDraft, isDeparture: Bool) -> some View {
        if !suggestions.isEmpty {
            Menu(isDeparture ? "Kies vertrekluchthaven" : "Kies aankomstluchthaven") {
                ForEach(suggestions) { airport in
                    Button("\(airport.code.isEmpty ? airport.name : "\(airport.code) · \(airport.name)") — \(airport.city), \(airport.country)") {
                        draft.selectAirport(airport, isDeparture: isDeparture)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private func searchAirports(_ query: String) async -> [AirportInfo] {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return [] }
        return await MapKitAirportSearchService().suggestions(for: query)
    }

    private func prepareDraft() {
        guard draft == nil, let trip = tripStore.trip else { return }
        if targetTripID == nil { targetTripID = tripStore.selectedTripId }
        if let itemID, let item = tripStore.managedItem(id: itemID, kind: kind) { draft = TripItemDraft(item: item, trip: trip) }
        else {
            let newDraft = TripItemDraft(kind: kind, trip: trip)
            if let extraction { newDraft.apply(extraction: extraction, trip: trip) }
            if let mapPlace { newDraft.apply(mapPlace: mapPlace) }
            newDraft.replacementImageData = scannedImageData
            draft = newDraft
        }
    }

    private func save() async {
        guard let draft else { return }
        let destinationTrip = itemID == nil
            ? targetTripID.flatMap { tripStore.trip(id: $0) } ?? tripStore.trip
            : tripStore.trip
        guard let trip = destinationTrip else { return }
        if itemID == nil, let mapPlace, !mapDuplicateAcknowledged,
           TripMapDuplicateDetector().duplicate(of: mapPlace, in: trip) != nil {
            confirmsMapDuplicate=true
            return
        }
        isSaving = true
        defer { isSaving = false }
        await geocodeAddressIfNeeded(draft)
        draft.matchDestination(in: trip.destinations)
        let item = draft.makeItem(kind: kind, id: itemID ?? UUID(), trip: trip)
        let succeeded = tripStore.saveManagedItem(item, replacementImageData: draft.replacementImageData,
                                                  removeAttachment: draft.removeAttachment,
                                                  targetTripID: itemID == nil ? targetTripID : nil)
        feedbackState.reportSave(kind: kind, isNew: itemID == nil, succeeded: succeeded, tripName: trip.name)
        guard succeeded else {
            errorMessage = "Het reisitem kon niet worden opgeslagen."
            return
        }
        dismiss()
    }

    private func geocodeAddressIfNeeded(_ draft: TripItemDraft) async {
        if draft.locationSource == .map {
#if DEBUG
            Self.logger.debug("Accommodation/location source=map placeName=\(draft.locationPlaceName, privacy: .public) coordinateAvailable=\(draft.coordinate != nil, privacy: .public)")
#endif
            return
        }
        let query: String
        switch kind {
        case .accommodation:
            query = [draft.c.nilIfBlank, draft.f.nilIfBlank].compactMap { $0 }.joined(separator: ", ")
        case .restaurant: query = draft.b
        case .activity: query = draft.c
        default: return
        }
        let coordinate = await AddressCoordinateResolver(geocoder: locationGeocoder).resolve(
            address: query,
            originalAddress: draft.originalAddress,
            existingCoordinate: draft.coordinate
        )
        if let coordinate { draft.setCoordinate(coordinate) }
        else if query.trimmingCharacters(in: .whitespacesAndNewlines) != draft.originalAddress.trimmingCharacters(in: .whitespacesAndNewlines) {
            draft.clearCoordinates()
        }
    }

    private static let logger = Logger(subsystem: "nl.martijnkooi.ThailandHolidayApp", category: "TripItemEditor")

    private func deleteItem() {
        guard let itemID, let item = tripStore.managedItem(id: itemID, kind: kind) else { return }
        guard tripStore.deleteManagedItem(item) else { errorMessage = "Het reisitem kon niet worden verwijderd."; return }
        dismiss()
    }

    private func previewImage(_ draft: TripItemDraft) -> UIImage? {
        if let data = draft.replacementImageData { return UIImage(data: data) }
        guard !draft.removeAttachment, let filename = draft.originalAttachment,
              let url = tripStore.attachmentURL(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func hasAttachment(_ draft: TripItemDraft) -> Bool { previewImage(draft) != nil }

    private func acceptMapPlace(_ place: MapPlace) {
        switch kind {
        case .transfer, .rentalVehicle, .ferry, .train:
            pendingMapPlace=place; showsRouteRole=true
        default: draft?.apply(mapPlace: place)
        }
    }
}

@MainActor @Observable
final class TripItemDraft {
    enum LocationSource { case manual, map }
    let originalAttachment: String?
    let originalAddress: String
    var date: Date
    var secondaryDate: Date
    var startTime: Date
    var endTime: Date
    var a = ""
    var b = ""
    var c = ""
    var d = ""
    var e = ""
    var f = ""
    var g = ""
    var locationAddress = ""
    var departureAirport: AirportInfo?
    var arrivalAirport: AirportInfo?
    var notes = ""
    var urlString = ""
    var destinationID: UUID?
    var transferType: TransferType = .taxi
    var rentalVehicleType: RentalVehicleType = .car
    var activityCategory: ItineraryCategory = .activity
    var replacementImageData: Data?
    var removeAttachment = false
    private let kind: TripItemKind
    private(set) var locationSource: LocationSource = .manual
    var locationPlaceName: String {
        switch kind { case .accommodation: f; case .activity: c; default: "" }
    }

    init(kind: TripItemKind, trip: Trip) {
        self.kind = kind
        date = trip.startDate
        secondaryDate = trip.startDate
        startTime = trip.startDate
        endTime = TripCalendar.calendar(in: trip.timeZone).date(byAdding: .hour, value: 1, to: trip.startDate)!
        if let testDate = UITestConfiguration.selectedDate {
            date = testDate
            secondaryDate = testDate
            startTime = testDate
            endTime = TripCalendar.calendar(in: trip.timeZone).date(byAdding: .day,
                value: kind == .accommodation ? 2 : 0, to: testDate) ?? testDate
        } else if kind == .accommodation {
            endTime = TripCalendar.calendar(in: trip.timeZone).date(byAdding: .day, value: 1, to: trip.startDate)!
        }
        destinationID = nil
        originalAttachment = nil
        originalAddress = ""
    }

    init(item: ManagedTripItem, trip: Trip) {
        kind = item.kind
        originalAttachment = item.attachmentFilename
        switch item {
        case .accommodation(let value):
            originalAddress = [value.address.nilIfBlank, value.placeName?.nilIfBlank].compactMap { $0 }.joined(separator: ", ")
        case .restaurant(let value): originalAddress = value.address ?? ""
        case .activity(let value): originalAddress = value.location?.placeName ?? ""
        default: originalAddress = ""
        }
        date = trip.startDate; secondaryDate = trip.startDate; startTime = trip.startDate; endTime = trip.startDate
        switch item {
        case .flight(let x): date=x.date; secondaryDate=x.arrivalDate; startTime=x.departureTime; endTime=x.arrivalTime; a=x.airline; b=x.flightNumber; c=x.originAirport; d=x.destinationAirport; e=x.aircraft ?? ""; f=x.cabin ?? ""; g=x.bookingReference ?? ""; departureAirport=x.departureAirport ?? AirportLookup().bestMatch(for:x.originAirport); arrivalAirport=x.arrivalAirport ?? AirportLookup().bestMatch(for:x.destinationAirport); notes=x.notes ?? ""; urlString=x.bookingURL?.absoluteString ?? ""
        case .accommodation(let x): date=x.checkIn; startTime=x.checkIn; endTime=x.checkOut; a=x.name; b=x.roomDescription; c=x.address; d=x.latitude.map { String($0) } ?? ""; e=x.longitude.map { String($0) } ?? ""; f=x.placeName ?? ""; g=x.bookingReference ?? ""; notes=x.notes ?? ""; urlString=x.bookingURL?.absoluteString ?? ""; destinationID=x.destinationID
        case .transfer(let x): date=x.date; startTime=x.startTime; endTime=x.endTime ?? x.startTime; secondaryDate=x.endTime ?? x.date; transferType=x.type; a=x.provider; b=x.origin; c=x.destination; d=x.bookingReference ?? ""; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""
        case .ferry(let x): date=x.date; startTime=x.departureTime; endTime=x.arrivalTime ?? x.departureTime; secondaryDate=x.arrivalTime ?? x.date; a=x.operatorName; b=x.departureLocation; c=x.arrivalLocation; d=x.bookingReference ?? ""; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""
        case .train(let x): date=x.date; startTime=x.departureTime; endTime=x.arrivalTime ?? x.departureTime; secondaryDate=x.arrivalTime ?? x.date; a=x.operatorName; b=x.trainNumber; c=x.originStation; d=x.destinationStation; e=x.carriage ?? ""; f=x.seat ?? ""; g=x.bookingReference ?? ""; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""
        case .rentalVehicle(let x): rentalVehicleType=x.vehicleType; date=x.pickupDate; secondaryDate=x.dropoffDate ?? x.pickupDate; startTime=x.pickupTime ?? x.pickupDate; endTime=x.dropoffTime ?? x.dropoffDate ?? x.pickupDate; a=x.company ?? ""; b=x.pickupLocation; c=x.dropoffLocation ?? ""; d=x.vehicleDescription ?? ""; e=x.bookingReference ?? ""; f=x.renterName ?? ""; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""
        case .restaurant(let x): date=x.date; startTime=x.time; endTime=x.time; a=x.name; b=x.address ?? ""; c=x.reservationName ?? ""; d=x.reservationReference ?? ""; e=x.latitude.map { String($0) } ?? ""; f=x.longitude.map { String($0) } ?? ""; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""
        case .activity(let x): date=x.date; startTime=x.startTime; endTime=x.endTime ?? x.startTime; a=x.title; b=x.description ?? ""; c=x.location?.placeName ?? ""; locationAddress=x.location?.address ?? ""; d=x.latitude.map { String($0) } ?? ""; e=x.longitude.map { String($0) } ?? ""; g=x.bookingReference ?? ""; activityCategory=ItineraryCategory(rawValue:x.category) ?? .activity; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""; destinationID=x.destinationId
        case .other(let x): date=x.date; startTime=x.startTime ?? x.date; endTime=x.endTime ?? x.startTime ?? x.date; a=x.title; b=x.location ?? ""; notes=x.notes ?? ""; urlString=x.url?.absoluteString ?? ""
        }
    }

    var validatedURL: URL? {
        guard let value=urlString.nilIfBlank, let parts=URLComponents(string:value), ["http","https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else { return nil }
        return parts.url
    }

    var coordinate: Coordinate? {
        let values: (String, String)
        switch kind {
        case .accommodation: values = (d, e)
        case .restaurant: values = (e, f)
        case .activity: values = (d, e)
        default: return nil
        }
        guard let latitude = Double(values.0), let longitude = Double(values.1) else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    func setCoordinate(_ coordinate: Coordinate) {
        switch kind {
        case .accommodation:
            d = String(coordinate.latitude); e = String(coordinate.longitude)
        case .restaurant:
            e = String(coordinate.latitude); f = String(coordinate.longitude)
        case .activity:
            d = String(coordinate.latitude); e = String(coordinate.longitude)
        default: break
        }
    }

    func clearCoordinates() {
        switch kind {
        case .accommodation: d = ""; e = ""
        case .restaurant: e = ""; f = ""
        case .activity: d = ""; e = ""
        default: break
        }
    }

    func apply(mapPlace: MapPlace, routeRole: MapPlaceRouteRole = .origin) {
        locationSource = .map
        let location = mapPlace.location
        let label = location.address ?? location.placeName ?? mapPlace.name
        switch kind {
        case .accommodation:
            if a.nilIfBlank == nil { a=mapPlace.name }; f=location.placeName ?? ""; c=location.address ?? ""
            setCoordinate(.init(latitude:mapPlace.latitude,longitude:mapPlace.longitude)); urlString=mapPlace.websiteURL?.absoluteString ?? urlString
        case .restaurant:
            if a.nilIfBlank == nil { a=mapPlace.name }; b=location.address ?? label
            setCoordinate(.init(latitude:mapPlace.latitude,longitude:mapPlace.longitude)); urlString=mapPlace.websiteURL?.absoluteString ?? urlString
        case .activity:
            if a.nilIfBlank == nil { a=mapPlace.name }; c=location.placeName ?? mapPlace.name; locationAddress=location.address ?? ""
            setCoordinate(.init(latitude:mapPlace.latitude,longitude:mapPlace.longitude)); urlString=mapPlace.websiteURL?.absoluteString ?? urlString
        case .transfer: if routeRole == .origin { b=label } else { c=label }
        case .rentalVehicle: if routeRole == .origin { b=label } else { c=label }
        case .ferry: if routeRole == .origin { b=label } else { c=label }
        case .train: if routeRole == .origin { c=label } else { d=label }
        case .other: b=label
        case .flight: break
        }
    }

    func matchDestination(in destinations: [Destination]) {
        let placeName: String?
        switch kind {
        case .accommodation: placeName = f.nilIfBlank
        case .activity: placeName = c.nilIfBlank
        default: return
        }
        guard let placeName else { return }
        destinationID = destinations.first {
            $0.name.compare(placeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.id
    }

    func airportSuggestions(for query: String) -> [AirportInfo] { AirportLookup().suggestions(for: query) }

    func selectAirport(_ airport: AirportInfo, isDeparture: Bool) {
        let fieldValue = airport.code.isEmpty ? airport.name : airport.code
        if isDeparture { departureAirport = airport; c = fieldValue }
        else { arrivalAirport = airport; d = fieldValue }
    }

    func apply(extraction result: BookingExtractionResult, trip: Trip) {
        func value(_ key: String) -> String? { result.fields[key]?.value }
        if let dateValue = value("date") ?? value("pickupDate") ?? value("checkIn"),
           let parsed = ISO8601DateFormatter().date(from: dateValue) { date = parsed }
        if let endValue = value("dropoffDate") ?? value("checkOut"),
           let parsed = ISO8601DateFormatter().date(from: endValue) { secondaryDate = parsed; endTime = parsed }
        func applyTime(_ value: String?, to target: inout Date) {
            guard let value else { return }
            for format in ["HH:mm", "H:mm", "h:mm a"] {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = trip.timeZone; formatter.dateFormat = format
                if let parsed = formatter.date(from: value.uppercased()) { target = parsed; return }
            }
        }
        applyTime(value("departureTime") ?? value("pickupTime") ?? value("time"), to: &startTime)
        applyTime(value("arrivalTime") ?? value("dropoffTime"), to: &endTime)
        urlString = value("url") ?? ""
        switch kind {
        case .flight:
            a=value("airline") ?? ""; b=value("flightNumber") ?? ""; c=value("originAirportCode") ?? ""; d=value("destinationAirportCode") ?? ""; e=value("aircraft") ?? ""; f=value("cabin") ?? ""; g=value("bookingReference") ?? ""
            departureAirport=AirportLookup().bestMatch(for:c); arrivalAirport=AirportLookup().bestMatch(for:d)
        case .accommodation:
            a=value("name") ?? ""; b=value("roomType") ?? ""; c=value("address") ?? ""; f=value("placeName") ?? ""; g=value("bookingReference") ?? ""
            if let checkout=value("checkOut"), let parsed=ISO8601DateFormatter().date(from:checkout) { endTime=parsed }
        case .transfer:
            a=value("provider") ?? ""; b=value("origin") ?? ""; c=value("destination") ?? ""; d=value("bookingReference") ?? ""
        case .ferry:
            a=value("operator") ?? ""; b=value("origin") ?? ""; c=value("destination") ?? ""; d=value("bookingReference") ?? ""
        case .train:
            a=value("operator") ?? ""; b=value("trainNumber") ?? ""; c=value("origin") ?? ""; d=value("destination") ?? ""; e=value("carriage") ?? ""; f=value("seat") ?? ""; g=value("bookingReference") ?? ""
        case .rentalVehicle:
            rentalVehicleType=RentalVehicleType(rawValue:value("vehicleType") ?? "") ?? .other
            a=value("company") ?? ""; b=value("pickupLocation") ?? ""; c=value("dropoffLocation") ?? ""; d=value("vehicleDescription") ?? ""; e=value("bookingReference") ?? ""; f=value("renterName") ?? ""
        case .restaurant:
            a=value("name") ?? ""; b=value("address") ?? ""; c=value("reservationName") ?? ""; d=value("bookingReference") ?? ""
        case .activity:
            a=value("title") ?? ""; b=value("description") ?? ""; c=value("placeName") ?? value("address") ?? ""
            activityCategory=ItineraryCategory(rawValue: value("activityCategory") ?? "") ?? .activity
            g=value("bookingReference") ?? ""
        case .other: a=value("title") ?? ""
        }
    }
    var isValid: Bool {
        let linkOK = urlString.nilIfBlank == nil || validatedURL != nil
        guard linkOK else { return false }
        switch kind {
        case .flight: return (!c.nilIfBlank.orEmpty.isEmpty || !d.nilIfBlank.orEmpty.isEmpty)
            && hasValidFlightArrival(in: TripCalendar.thailandTimeZone)
        case .accommodation: return a.nilIfBlank != nil && endTime >= startTime
        case .restaurant, .activity, .other: return a.nilIfBlank != nil
        case .transfer, .ferry: return b.nilIfBlank != nil || c.nilIfBlank != nil
        case .train: return c.nilIfBlank != nil || d.nilIfBlank != nil
        case .rentalVehicle: return b.nilIfBlank != nil
        }
    }

    func hasValidFlightArrival(in timeZone: TimeZone) -> Bool {
        guard kind == .flight else { return true }
        let calendar = TripCalendar.calendar(in: timeZone)
        let departure = calendar.combining(day: date, time: startTime)
        let arrival = calendar.combining(day: secondaryDate, time: endTime)
        return arrival >= departure
    }

    func makeItem(kind: TripItemKind, id: UUID, trip: Trip) -> ManagedTripItem {
        let calendar=TripCalendar.calendar(in:trip.timeZone), day=calendar.startOfDay(for:date)
        let start=calendar.combining(day:day,time:startTime)
        let arrivalDay=calendar.startOfDay(for:secondaryDate)
        let end=calendar.combining(day:arrivalDay,time:endTime), url=validatedURL
        switch kind {
        case .flight:
            let arrivalDay = calendar.startOfDay(for: secondaryDate)
            return .flight(Flight(id:id,date:day,airline:a,flightNumber:b,originAirport:c,destinationAirport:d,
                departureTime:start,arrivalDate:arrivalDay,arrivalTime:calendar.combining(day:arrivalDay,time:endTime),
                departureAirport:departureAirport,arrivalAirport:arrivalAirport,bookingReference:g.nilIfBlank,
                aircraft:e.nilIfBlank,cabin:f.nilIfBlank,notes:notes.nilIfBlank,bookingURL:url,attachmentFilename:originalAttachment))
        case .accommodation: return .accommodation(Accommodation(id:id,name:a,type:.hotel,destinationID:destinationID,placeName:f.nilIfBlank,checkIn:startTime,checkOut:endTime,address:c,latitude:Double(d),longitude:Double(e),roomDescription:b,bookingReference:g.nilIfBlank,websiteURL:nil,bookingURL:url,phoneNumber:nil,notes:notes.nilIfBlank,attachmentFilename:originalAttachment))
        case .transfer: return .transfer(Transfer(id:id,date:day,startTime:start,endTime:end,type:transferType,provider:a,origin:b,destination:c,bookingReference:d.nilIfBlank,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment))
        case .ferry: return .ferry(Ferry(id:id,date:day,operatorName:a,departureLocation:b,arrivalLocation:c,departureTime:start,arrivalTime:end,bookingReference:d.nilIfBlank,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment))
        case .train: return .train(TrainTrip(id:id,date:day,operatorName:a,trainNumber:b,originStation:c,destinationStation:d,departureTime:start,arrivalTime:end,carriage:e.nilIfBlank,seat:f.nilIfBlank,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment,bookingReference:g.nilIfBlank))
        case .rentalVehicle:
            let dropoffDay = calendar.startOfDay(for: secondaryDate)
            return .rentalVehicle(RentalVehicleBooking(id:id,vehicleType:rentalVehicleType,company:a.nilIfBlank,pickupDate:day,pickupTime:start,pickupLocation:b,dropoffDate:dropoffDay,dropoffTime:calendar.combining(day:dropoffDay,time:endTime),dropoffLocation:c.nilIfBlank,vehicleDescription:d.nilIfBlank,bookingReference:e.nilIfBlank,renterName:f.nilIfBlank,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment))
        case .restaurant: return .restaurant(RestaurantReservation(id:id,date:day,time:start,name:a,address:b.nilIfBlank,latitude:Double(e),longitude:Double(f),reservationName:c.nilIfBlank,reservationReference:d.nilIfBlank,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment))
        case .activity: return .activity(Activity(id:id,destinationId:destinationID,date:day,startTime:start,endTime:end,title:a,category:activityCategory.rawValue,description:b.nilIfBlank,location:TripLocation(placeName:c.nilIfBlank,address:locationAddress.nilIfBlank,latitude:Double(d),longitude:Double(e)),latitude:Double(d),longitude:Double(e),websiteURL:nil,bookingURL:nil,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment,isFavorite:false,isCompleted:false,bookingReference:g.nilIfBlank))
        case .other: return .other(TripEvent(id:id,date:day,startTime:start,endTime:end,title:a,location:b.nilIfBlank,notes:notes.nilIfBlank,url:url,attachmentFilename:originalAttachment))
        }
    }
}

private extension Optional where Wrapped == String { var orEmpty:String { self ?? "" } }
