import AppKit
import CoreLocation
import Foundation

/// Finds the city the Mac is in, for the Weather module's automatic mode. Runs only while that mode is active:
/// asks macOS for permission, reads a city-level position (about 1 km), looks up the city name with Apple's
/// geocoder and refreshes every 30 minutes and after wake.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case idle, locating, denied, failed
    }

    @Published private(set) var place: WeatherLocation?
    @Published private(set) var status: Status = .idle

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var active = false
    private var retries = 0
    private var retryWork: DispatchWorkItem?
    private static let refreshInterval: TimeInterval = 30 * 60
    /// Moves smaller than this keep the same place, so the forecast isn't reloaded for GPS noise.
    private static let minimumMove: CLLocationDistance = 3000
    /// macOS often answers "position unknown" right after the request; retry soon instead of waiting for the next refresh.
    private static let retryDelay: TimeInterval = 10
    private static let maxRetries = 6

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func setActive(_ wanted: Bool) {
        guard wanted != active else { return }
        active = wanted
        if wanted { start() } else { stop() }
    }

    private func start() {
        status = .locating
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.locate() }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                         queue: .main) { [weak self] _ in self?.locate() }
        locate()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        geocoder.cancelGeocode()
        retryWork?.cancel()
        retries = 0
        place = nil
        status = .idle
    }

    private func locate() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        default:
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard active else { return }
        locate()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, let location = locations.last else { return }
        retries = 0
        if let place, CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: location) < Self.minimumMove {
            status = .idle
            return
        }
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            DispatchQueue.main.async {
                guard let self, self.active else { return }
                let mark = marks?.first
                // About 1 km precision is plenty for a forecast and keeps the stored place stable.
                self.place = WeatherLocation(name: mark?.locality ?? mark?.subAdministrativeArea ?? mark?.name ?? "Posizione attuale",
                                             region: mark?.administrativeArea, country: mark?.country,
                                             latitude: (location.coordinate.latitude * 100).rounded() / 100,
                                             longitude: (location.coordinate.longitude * 100).rounded() / 100)
                self.status = .idle
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard active else { return }
        if (error as? CLError)?.code == .denied {
            status = .denied
        } else if place == nil {
            status = .failed
        }
        guard retries < Self.maxRetries else { return }
        retries += 1
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.locate() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay, execute: work)
    }
}
