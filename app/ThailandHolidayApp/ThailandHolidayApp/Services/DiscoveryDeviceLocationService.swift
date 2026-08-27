import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class DiscoveryDeviceLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<SearchLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async -> SearchLocation? {
        guard CLLocationManager.locationServicesEnabled(), continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            case .notDetermined: manager.requestWhenInUseAuthorization()
            default: finish(nil)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.finish(nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else { finish(nil); return }
        finish(SearchLocation(name: "je huidige locatie", latitude: value.coordinate.latitude,
                              longitude: value.coordinate.longitude))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(nil) }
    private func finish(_ value: SearchLocation?) { continuation?.resume(returning: value); continuation = nil }
}
