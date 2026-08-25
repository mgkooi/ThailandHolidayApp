import Foundation
import Observation

enum AppTab: Hashable { case today, trip, discover, map, more }

@MainActor @Observable
final class AppNavigationState {
    var selectedTab: AppTab = .today
    var mapFocus: SearchLocation?
    var mapFocusDate: Date?
    var discoverLocation: SearchLocation?
    var discoverCategory: DiscoveryCategory = .restaurant
    var discoverResultID: String?

    func openDiscover(location: SearchLocation? = nil, category: DiscoveryCategory = .restaurant,
                      selectedResultID: String? = nil) {
        discoverLocation = location
        discoverCategory = category
        discoverResultID = selectedResultID
        selectedTab = .discover
    }
    func openMap(focus: SearchLocation, date: Date) {
        mapFocus = focus; mapFocusDate = date; selectedTab = .map
    }
}
