import CoreLocation

protocol BackgroundLocationManagerDelegate: AnyObject {
    func didUpdateLocation(latitude: Double, longitude: Double)
}

final class BackgroundLocationManager: NSObject {
    static let shared = BackgroundLocationManager()

    weak var delegate: BackgroundLocationManagerDelegate?

    private let clManager = CLLocationManager()

    private override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter = kCLDistanceFilterNone
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
    }

    func requestLocationAuthorization() {
        clManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        print("✅ [BackgroundLocationManager] Iniciando atualizações de localização.")
        clManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        clManager.stopUpdatingLocation()
    }
}

extension BackgroundLocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("🚨🚨 [GPS NATIVO] O satélite respondeu! Recebi \(locations.count) coordenadas.")

        guard let location = locations.last else {
            print("⚠️ [GPS NATIVO] Array de localizações veio vazio.")
            return
        }

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        print("📍 [GPS NATIVO] Coordenada capturada: Lat: \(lat), Lng: \(lng)")

        delegate?.didUpdateLocation(latitude: lat, longitude: lng)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [GPS NATIVO] Erro na antena: \(error.localizedDescription)")
    }
}
