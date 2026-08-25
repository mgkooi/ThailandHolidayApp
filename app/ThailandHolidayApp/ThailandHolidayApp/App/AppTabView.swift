import SwiftUI

struct AppTabView: View {
    @Environment(AppNavigationState.self) private var navigationState

    var body: some View {
        @Bindable var navigationState = navigationState
        TabView(selection: $navigationState.selectedTab) {
            TodayView(selectedDate: UITestConfiguration.selectedDate)
                .tabItem {
                    Label("Vandaag", systemImage: "sun.max")
                }
                .tag(AppTab.today)

            TripView()
                .tabItem {
                    Label("Reis", systemImage: "airplane")
                }
                .tag(AppTab.trip)

            DiscoverView()
                .tabItem {
                    Label("Ontdekken", systemImage: "sparkles")
                }
                .tag(AppTab.discover)

            MapView()
                .tabItem {
                    Label("Kaart", systemImage: "map")
                }
                .tag(AppTab.map)

            MoreView()
                .tabItem {
                    Label("Meer", systemImage: "ellipsis")
                }
                .tag(AppTab.more)
        }
    }
}

#Preview {
    AppTabView()
}
