import SwiftUI

struct TripContextToolbar: ToolbarContent {
    @Environment(TripStore.self) private var store
    @State private var showsTrips = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(store.trips) { trip in
                    Button {
                        _ = store.selectTrip(id: trip.id)
                    } label: {
                        if store.selectedTripId == trip.id {
                            Label(trip.name, systemImage: "checkmark")
                        } else { Text(trip.name) }
                    }
                }
                Divider()
                Button { showsTrips = true } label: { Label("Mijn reizen", systemImage: "suitcase.rolling") }
            } label: {
                HStack(spacing: 5) {
                    Text(store.trip?.name ?? "Nieuwe reis").lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }.font(.headline)
            }
            .accessibilityLabel("Actieve reis: \(store.trip?.name ?? "geen reis")")
            .sheet(isPresented: $showsTrips) { MyTripsView() }
        }
    }
}
