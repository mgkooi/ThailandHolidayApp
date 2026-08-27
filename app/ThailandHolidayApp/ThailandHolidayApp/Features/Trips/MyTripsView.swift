import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MyTripsView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreate = false
    @State private var tripToEdit: Trip?
    @State private var tripToDelete: Trip?
    @State private var sharePayload: SharePayload?
    @State private var showsImporter = false
    @State private var importPreview: TripImportPreview?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.trips) { trip in
                    Button {
                        if store.selectTrip(id: trip.id) { dismiss() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: store.selectedTripId == trip.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.selectedTripId == trip.id ? Color.travelTeal : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(trip.name).font(.headline).foregroundStyle(.primary)
                                if !trip.country.isEmpty { Text(trip.country).font(.subheadline).foregroundStyle(.secondary) }
                                Text(dateRange(trip)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { tripToEdit = trip } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).accessibilityLabel("Bewerk reis")
                            Button(role: .destructive) { tripToDelete = trip } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                            Button { export(trip) } label: { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.borderless).accessibilityLabel("Deel reis")
                        }
                    }
                    .contextMenu {
                        Button { tripToEdit = trip } label: { Label("Bewerk reis", systemImage: "pencil") }
                        Button { export(trip) } label: { Label("Deel reis", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Mijn reizen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showsCreate = true } label: { Label("Nieuwe reis", systemImage: "plus") }
                        Button { showsImporter = true } label: { Label("Importeer reis", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showsCreate) { TripMetadataEditor() }
            .sheet(item: $tripToEdit) { TripMetadataEditor(trip: $0) }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } })) {
                Button("Verwijder reis", role: .destructive) {
                    if let id = tripToDelete?.id { _ = store.deleteTrip(id: id) }
                    tripToDelete = nil
                }
                Button("Annuleer", role: .cancel) { tripToDelete = nil }
            }
            .sheet(item: $sharePayload) { ShareSheet(items: [$0.url]) }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.tripArchive, .folder, .json]) { result in
                handleImport(result)
            }
            .sheet(item: $importPreview) { preview in TripImportPreviewView(preview: preview) { strategy in
                importTrip(preview, strategy: strategy)
            } }
            .alert("Importeren mislukt", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "Probeer het opnieuw.") }
        }
    }

    private func export(_ trip: Trip) {
        do {
            guard let attachments = store.attachmentStore else { throw TripStoreError.documentsDirectoryUnavailable }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TripExports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            sharePayload = SharePayload(url: try TripArchiveService().export(
                trip: trip, nearbySuggestions: store.nearbySuggestions, favorites: store.favorites,
                attachmentStore: attachments, destinationDirectory: directory))
        } catch { importError = error.localizedDescription }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let source = try result.get()
            let service = TripArchiveService()
            let local = try service.stageImport(from: source)
            importPreview = try service.preview(url: local)
        } catch { importError = error.localizedDescription }
    }

    private func importTrip(_ preview: TripImportPreview, strategy: TripImportStrategy) {
        do {
            guard let attachments = store.attachmentStore else { throw TripStoreError.documentsDirectoryUnavailable }
            let trip = try TripArchiveService().importedTrip(from: preview, attachmentStore: attachments)
            guard store.importTrip(trip, strategy: strategy,
                nearbySuggestions: preview.manifest.nearbySuggestions ?? [],
                favorites: preview.manifest.favorites ?? []) else { throw TripStoreError.noTripLoaded }
            importPreview = nil
        } catch { importError = error.localizedDescription }
    }

    private var deleteTitle: String {
        "Weet je zeker dat je \"\(tripToDelete?.name ?? "deze reis")\" wilt verwijderen?"
    }
    private func dateRange(_ trip: Trip) -> String {
        let formatter = AppFormatters.shortDate(in: trip.timeZone)
        return "\(formatter.string(from: trip.effectiveStartDate)) – \(formatter.string(from: trip.effectiveEndDate))"
    }
}

private struct TripImportPreviewView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let preview: TripImportPreview
    let importAction: (TripImportStrategy) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section(preview.manifest.trip.name) {
                    Label("\(preview.dayCount) reisdagen", systemImage: "calendar")
                    Label("\(preview.manifest.trip.flights.count) vluchten", systemImage: "airplane")
                    Label("\(preview.manifest.trip.accommodations.count) accommodaties", systemImage: "bed.double")
                    Label("\(preview.manifest.trip.activities.count) activiteiten", systemImage: "figure.walk")
                    Label("\(preview.manifest.trip.restaurants.count) restaurants", systemImage: "fork.knife")
                    Label("\(preview.imageCount) afbeeldingen", systemImage: "photo")
                }
                Section {
                    if store.trips.contains(where: { $0.id == preview.manifest.trip.id }) {
                        Button("Importeer als nieuwe reis/kopie") { importAction(.copy) }
                        Button("Bestaande reis vervangen", role: .destructive) { importAction(.replace) }
                    } else { Button("Importeren") { importAction(.copy) } }
                    Button("Annuleren", role: .cancel) { dismiss() }
                }
            }.navigationTitle("Reis importeren")
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct TripMetadataEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var country = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var travelers = 1

    private let trip: Trip?

    init(trip: Trip? = nil) {
        self.trip = trip
        _name = State(initialValue: trip?.name ?? "")
        _country = State(initialValue: trip?.country ?? "")
        _startDate = State(initialValue: trip?.startDate ?? Date())
        _endDate = State(initialValue: trip?.endDate ?? Date())
        _travelers = State(initialValue: trip?.travelers ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reis") {
                    TextField("Naam", text: $name)
                    TextField("Land (optioneel)", text: $country)
                    DatePicker("Startdatum", selection: $startDate, displayedComponents: .date)
                    DatePicker("Einddatum", selection: $endDate, in: startDate..., displayedComponents: .date)
                    Stepper("Reizigers: \(travelers)", value: $travelers, in: 1...20)
                }
                Section { Text("Deze datums zijn metadata en beperken reisitems niet.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle(trip == nil ? "Nieuwe reis" : "Bewerk reis")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
                        let saved = if let trip {
                            store.updateTripMetadata(trip.updatingMetadata(name: cleanName, country: cleanCountry,
                                                                           startDate: startDate, endDate: endDate,
                                                                           travelers: travelers))
                        } else {
                            store.addTrip(Trip.empty(name: cleanName, country: cleanCountry,
                                                     startDate: startDate, endDate: endDate))
                        }
                        if saved { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
