import SwiftUI

@main
struct ThailandHolidayAppApp: App {
    @State private var tripStore: TripStore
    @State private var weatherService = TripWeatherService()
    @State private var startupCoordinator = AppStartupCoordinator()
    @State private var navigationState = AppNavigationState()
    @State private var discoverySession: DiscoverySession
    @State private var feedbackState = AppFeedbackState()
    @State private var discoveryLocationService = DiscoveryDeviceLocationService()

    init() {
        UITestConfiguration.resetDocumentsIfRequested()
        _tripStore = State(initialValue: TripStore(documentsDirectory: UITestConfiguration.documentsDirectory))
        let geocoder: any LocationGeocoding = UITestConfiguration.isEnabled
            ? UITestLocationGeocodingService() : LocationGeocodingService()
        let discovery: any LocalDiscoverySearching = UITestConfiguration.isEnabled
            ? UITestDiscoveryService() : PreferredDiscoveryService()
        _discoverySession = State(initialValue: DiscoverySession(searcher: discovery, geocoder: geocoder))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if startupCoordinator.isReady {
                    AppTabView()
                        .transition(.opacity)
                } else {
                    LoadingView(coordinator: startupCoordinator) {
                        Task { await startupCoordinator.retry(tripStore: tripStore) }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: startupCoordinator.isReady)
            .environment(tripStore)
            .environment(weatherService)
            .environment(navigationState)
            .environment(discoverySession)
            .environment(feedbackState)
            .environment(discoveryLocationService)
            .environment(\.locationGeocoder, locationGeocoder)
            .environment(\.mapSearchProvider, mapSearchProvider)
            .overlay(alignment: .top) {
                if let message = feedbackState.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color.travelGreen, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("saveConfirmation")
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            feedbackState.clear()
                        }
                }
            }
            .animation(.easeInOut, value: feedbackState.message)
            .task { await startupCoordinator.start(tripStore: tripStore) }
        }
    }

    private var locationGeocoder: any LocationGeocoding {
        UITestConfiguration.isEnabled ? UITestLocationGeocodingService() : LocationGeocodingService()
    }
    private var mapSearchProvider: any MapSearchProviding {
        UITestConfiguration.isEnabled ? UITestMapSearchService() : MapSearchService()
    }
}
