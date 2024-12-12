import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func startUpdating() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        print("LocationManager: Started updating location.")
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        print("LocationManager: Stopped updating location.")
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("LocationManager auth changed: \(status.rawValue)")
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            self.location = locations.last
            print("LocationManager updated location to \(String(describing: self.location?.coordinate))")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error.localizedDescription)")
    }
}
