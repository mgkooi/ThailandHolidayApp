import SwiftUI

struct MyTripsView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreate = false
    @State private var tripToDelete: Trip?

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
                        }
                    }
                }
            }
            .navigationTitle("Mijn reizen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showsCreate = true } label: { Label("Nieuwe reis", systemImage: "plus") }
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
        }
    }

    private var deleteTitle: String {
        "Weet je zeker dat je \"\(tripToDelete?.name ?? "deze reis")\" wilt verwijderen?"
    }
    private func dateRange(_ trip: Trip) -> String {
        let formatter = AppFormatters.shortDate(in: trip.timeZone)
        return "\(formatter.string(from: trip.effectiveStartDate)) – \(formatter.string(from: trip.effectiveEndDate))"
    }
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
