import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MyTripsView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreate = false
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
                            Button(role: .destructive) { tripToDelete = trip } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                            Button { export(trip) } label: { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.borderless).accessibilityLabel("Deel reis")
                        }
                    }
                    .contextMenu {
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
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } })) {
                Button("Verwijder reis", role: .destructive) {
                    if let id = tripToDelete?.id { _ = store.deleteTrip(id: id) }
                    tripToDelete = nil
                }
                Button("Annuleer", role: .cancel) { tripToDelete = nil }
            }
            .sheet(item: $sharePayload) { ShareSheet(items: [$0.url]) }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.item]) { result in handleImport(result) }
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
            let accessed = source.startAccessingSecurityScopedResource(); defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let local = FileManager.default.temporaryDirectory.appendingPathComponent("Imported-\(UUID().uuidString).trip", isDirectory: true)
            try FileManager.default.copyItem(at: source, to: local)
            importPreview = try TripArchiveService().preview(url: local)
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
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Reis") {
                    TextField("Naam", text: $name)
                    TextField("Land (optioneel)", text: $country)
                    DatePicker("Startdatum", selection: $startDate, displayedComponents: .date)
                    DatePicker("Einddatum", selection: $endDate, in: startDate..., displayedComponents: .date)
                    TextField("Notities (optioneel)", text: $notes, axis: .vertical)
                }
                Section { Text("Deze datums zijn metadata en beperken reisitems niet.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Nieuwe reis")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") {
                        let trip = Trip.empty(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              country: country.trimmingCharacters(in: .whitespacesAndNewlines),
                                              startDate: startDate, endDate: endDate)
                        if store.addTrip(trip) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
