import SwiftUI

struct MoreView: View {
    @State private var showsTrips = false
    var body: some View {
        NavigationStack {
            List {
                Button { showsTrips = true } label: { Label("Mijn reizen", systemImage: "suitcase.rolling") }
            }.navigationTitle("Meer")
                .toolbar { TripContextToolbar() }
                .sheet(isPresented: $showsTrips) { MyTripsView() }
        }
    }
}

#Preview {
    MoreView()
}
