import CoreLocation

/// iOS won't take Live Activity updates from an app whose only reason to run in the
/// background is playing audio ("only playing background media so is forbidden to update
/// activity"), so the silent audio alone leaves the card frozen. Background location is
/// the other thing that counts, the same way navigation apps keep their cards current.
/// The location itself isn't used.
@MainActor
final class BackgroundLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
        manager.activityType = .automotiveNavigation
        // Pausing at a red light would pause the card too.
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        isRunning = true
        switch manager.authorizationStatus {
        case .notDetermined:
            // "Always" lets the Start Lyrics shortcut begin updates while the app is in the
            // background. iOS asks for While Using first and offers Always later.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            begin()
        default:
            Diagnostics.log("location not allowed; the card can't update in the background")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        Diagnostics.log("background location stopped")
    }

    private func begin() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        Diagnostics.log("background location running (\(manager.authorizationStatus == .authorizedAlways ? "always" : "while using"))")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = self.manager.authorizationStatus
            guard self.isRunning else { return }
            switch status {
            case .authorizedAlways: self.begin()
            case .authorizedWhenInUse:
                self.begin()
                self.manager.requestAlwaysAuthorization()
            case .denied, .restricted:
                Diagnostics.log("location denied; the card can't update in the background")
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Diagnostics.log("location error: \(error.localizedDescription)")
    }
}
