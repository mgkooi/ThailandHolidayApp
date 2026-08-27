import PhotosUI
import SwiftUI

struct CoverEditorView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    let kind: TripItemKind
    @State private var photoItem: PhotosPickerItem?
    @State private var showsSearch = false
    @State private var showsCamera = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Omslag") {
                    if let media = item?.presentationMedia {
                        TripMediaImage(media: media)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 260)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if let attribution = media.attribution?.nilIfBlank ?? media.sourceName?.nilIfBlank {
                            Text(attribution).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("Geen omslag", systemImage: kind.symbolName,
                            description: Text("Documenten worden nooit automatisch als omslag gebruikt."))
                    }
                }
                Section {
                    Button { showsSearch = true } label: { Label("Zoek afbeelding", systemImage: "magnifyingglass") }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(hasCover ? "Vervang via fotobibliotheek" : "Kies uit fotobibliotheek",
                              systemImage: "photo.on.rectangle")
                    }
                    if CameraImagePicker.isAvailable {
                        Button { showsCamera = true } label: { Label("Maak foto", systemImage: "camera") }
                    }
                    if hasCover {
                        Button("Verwijder omslag", role: .destructive) { save(data: nil, metadata: nil) }
                    }
                }
                Section("Documenten") {
                    Text("Bestaande screenshots, vouchers, tickets en andere reisdocumenten blijven apart bewaard.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let item { Text("\(item.mediaItems.count) document(en)") }
                }
            }
            .navigationTitle("Omslag")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Sluit") { dismiss() } } }
            .onChange(of: photoItem) { _, value in
                guard let value else { return }
                Task {
                    do { save(data: try await value.loadTransferable(type: Data.self), metadata: TripMedia(sourceName: "Fotobibliotheek")) }
                    catch { errorMessage = "De foto kon niet worden geladen." }
                }
            }
            .sheet(isPresented: $showsSearch) {
                MediaSearchView(initialQuery: searchQuery, subject: searchSubject,
                                googlePlaceID: googlePlaceID) { selected in
                    save(data: selected.data, metadata: selected.metadata)
                }
            }
            .sheet(isPresented: $showsCamera) {
                CameraImagePicker { data in save(data: data, metadata: TripMedia(sourceName: "Camera")) }
            }
            .alert("Omslag niet gewijzigd", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "Probeer opnieuw.") }
        }
    }

    private var item: ManagedTripItem? { store.managedItem(id: itemID, kind: kind) }
    private var hasCover: Bool { item?.presentationMedia.map { _ in true } ?? false }

    private var searchQuery: String {
        guard let trip = store.trip, let item else { return "Thailand" }
        let builder = MediaQueryBuilder()
        return switch item {
        case .accommodation(let value): builder.accommodation(name: value.name, place: value.placeName,
            country: trip.country, address: value.address)
        case .flight(let value): builder.flight(carrierName: value.airline, aircraft: value.aircraft)
        case .activity(let value): builder.activity(name: value.title, place: value.location?.placeName,
            country: trip.country)
        default: trip.country
        }
    }

    private var searchSubject: MediaSearchSubject { kind == .flight ? .flight : .place }
    private var googlePlaceID: String? {
        switch item {
        case .accommodation(let value): value.googlePlaceID ?? value.presentationMedia?.googlePlaceID
        case .activity(let value): value.location?.googlePlaceID ?? value.presentationMedia?.googlePlaceID
        default: nil
        }
    }

    private func save(data: Data?, metadata: TripMedia?) {
        guard let item, store.setPresentationMedia(for: item, imageData: data, metadata: metadata) else {
            errorMessage = store.errorMessage ?? "De omslag kon niet worden opgeslagen."
            return
        }
    }
}
