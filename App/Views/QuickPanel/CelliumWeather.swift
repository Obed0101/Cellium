import Foundation
@preconcurrency import CoreLocation
import Network

struct WeatherSnapshot: Equatable, Sendable {
    let timestamp: Date
    let locationLabel: String?
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let relativeHumidity: Double
    let weatherCode: Int
    let windSpeedKmh: Double

    var symbolName: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1...3: return "cloud.sun.fill"
        case 45...48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85...86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    func conditionLabel(for language: CelliumLanguage) -> String {
        switch language {
        case .spanish:
            switch weatherCode {
            case 0: return "Despejado"
            case 1...3: return "Parcialmente nublado"
            case 45...48: return "Niebla"
            case 51...67, 80...82: return "Lluvia"
            case 71...77, 85...86: return "Nieve"
            case 95...99: return "Tormenta"
            default: return "Nublado"
            }
        case .english:
            switch weatherCode {
            case 0: return "Clear"
            case 1...3: return "Partly cloudy"
            case 45...48: return "Fog"
            case 51...67, 80...82: return "Rain"
            case 71...77, 85...86: return "Snow"
            case 95...99: return "Storm"
            default: return "Cloudy"
            }
        }
    }
}

enum WeatherLocationMode: String, CaseIterable, Identifiable {
    case automaticOnce
    case manual

    var id: String { rawValue }
}

@MainActor
final class WeatherCoordinator: NSObject, @preconcurrency CLLocationManagerDelegate {
    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperatureCelsius: Double
            let apparentTemperatureCelsius: Double
            let relativeHumidity: Double
            let weatherCode: Int
            let windSpeedKmh: Double

            enum CodingKeys: String, CodingKey {
                case time
                case temperatureCelsius = "temperature_2m"
                case apparentTemperatureCelsius = "apparent_temperature"
                case relativeHumidity = "relative_humidity_2m"
                case weatherCode = "weather_code"
                case windSpeedKmh = "wind_speed_10m"
            }
        }

        let current: Current
        let timezone: String?
    }

    private let defaults = UserDefaults.standard
    private let locationManager = CLLocationManager()
    private let pathMonitor = NWPathMonitor()
    private var weatherTask: Task<Void, Never>?
    private var hasStarted = false
    private var isNetworkAvailable = false
    private let refreshInterval: TimeInterval = 15 * 60

    private(set) var snapshot: WeatherSnapshot?
    private(set) var errorMessage: String?
    private(set) var isRequestingLocation = false
    private(set) var mode: WeatherLocationMode
    private(set) var manualLabel: String
    private(set) var manualLatitude: String
    private(set) var manualLongitude: String

    var onChange: (() -> Void)?

    override init() {
        self.mode = WeatherLocationMode(
            rawValue: UserDefaults.standard.string(forKey: "cellium.weather.locationMode") ?? ""
        ) ?? .automaticOnce
        self.manualLabel = UserDefaults.standard.string(forKey: "cellium.weather.manualLabel") ?? ""
        self.manualLatitude = UserDefaults.standard.string(forKey: "cellium.weather.manualLatitude") ?? ""
        self.manualLongitude = UserDefaults.standard.string(forKey: "cellium.weather.manualLongitude") ?? ""
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isNetworkAvailable = path.status == .satisfied
                if self?.isNetworkAvailable == true {
                    self?.refreshStoredLocation()
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "cellium.weather.network"))
    }

    deinit {
        pathMonitor.cancel()
        weatherTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshStoredLocation()
    }

    func setMode(_ mode: WeatherLocationMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: "cellium.weather.locationMode")
        snapshot = nil
        errorMessage = nil
        if mode == .manual {
            locationManager.stopUpdatingLocation()
            refreshStoredLocation()
        } else {
            requestLocationIfNeeded(force: false)
        }
        onChange?()
    }

    func saveManualLocation(label: String, latitude: String, longitude: String) {
        guard let latitudeValue = Double(latitude),
              let longitudeValue = Double(longitude),
              (-90...90).contains(latitudeValue),
              (-180...180).contains(longitudeValue) else {
            errorMessage = "Introduce coordenadas válidas."
            onChange?()
            return
        }

        manualLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        manualLatitude = String(format: "%.5f", latitudeValue)
        manualLongitude = String(format: "%.5f", longitudeValue)
        defaults.set(manualLabel, forKey: "cellium.weather.manualLabel")
        defaults.set(manualLatitude, forKey: "cellium.weather.manualLatitude")
        defaults.set(manualLongitude, forKey: "cellium.weather.manualLongitude")
        mode = .manual
        defaults.set(mode.rawValue, forKey: "cellium.weather.locationMode")
        refreshStoredLocation()
    }

    func requestLocationAgain() {
        defaults.set(false, forKey: "cellium.weather.locationRequested")
        requestLocationIfNeeded(force: true)
    }

    func refresh() {
        refreshStoredLocation()
    }

    private func refreshStoredLocation() {
        if let snapshot,
           Date().timeIntervalSince(snapshot.timestamp) < refreshInterval {
            return
        }
        guard isNetworkAvailable else {
            errorMessage = "Sin conexión para consultar el clima."
            onChange?()
            return
        }

        if mode == .manual,
           let latitude = Double(manualLatitude),
           let longitude = Double(manualLongitude) {
            fetchWeather(
                latitude: latitude,
                longitude: longitude,
                label: manualLabel.isEmpty ? nil : manualLabel
            )
            return
        }

        if let coordinate = savedCoordinate() {
            fetchWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                label: defaults.string(forKey: "cellium.weather.locationLabel")
            )
            return
        }

        requestLocationIfNeeded(force: false)
    }

    private func requestLocationIfNeeded(force: Bool) {
        guard mode == .automaticOnce else { return }
        guard force || !defaults.bool(forKey: "cellium.weather.locationRequested") else {
            errorMessage = "Configura una ubicación para ver el clima."
            onChange?()
            return
        }

        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            defaults.set(true, forKey: "cellium.weather.locationRequested")
            isRequestingLocation = true
            locationManager.requestLocation()
            onChange?()
        case .notDetermined:
            defaults.set(true, forKey: "cellium.weather.locationRequested")
            isRequestingLocation = true
            locationManager.requestWhenInUseAuthorization()
            onChange?()
        case .denied, .restricted:
            errorMessage = "Ubicación no disponible. Puedes definirla manualmente."
            onChange?()
        @unknown default:
            errorMessage = "Ubicación no disponible."
            onChange?()
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double, label: String?) {
        weatherTask?.cancel()
        weatherTask = Task { [weak self] in
            guard let self else { return }
            do {
                var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
                components?.queryItems = [
                    URLQueryItem(name: "latitude", value: String(latitude)),
                    URLQueryItem(name: "longitude", value: String(longitude)),
                    URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
                    URLQueryItem(name: "timezone", value: "auto")
                ]
                guard let url = components?.url else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                self.snapshot = WeatherSnapshot(
                    timestamp: Date(),
                    locationLabel: label ?? decoded.timezone,
                    temperatureCelsius: decoded.current.temperatureCelsius,
                    apparentTemperatureCelsius: decoded.current.apparentTemperatureCelsius,
                    relativeHumidity: decoded.current.relativeHumidity,
                    weatherCode: decoded.current.weatherCode,
                    windSpeedKmh: decoded.current.windSpeedKmh
                )
                self.errorMessage = nil
                self.isRequestingLocation = false
                self.onChange?()
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = "Clima temporalmente no disponible."
                self.isRequestingLocation = false
                self.onChange?()
            }
        }
    }

    private func savedCoordinate() -> CLLocationCoordinate2D? {
        guard let latitude = defaults.object(forKey: "cellium.weather.latitude") as? Double,
              let longitude = defaults.object(forKey: "cellium.weather.longitude") as? Double else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            requestLocationIfNeeded(force: true)
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            isRequestingLocation = false
            errorMessage = "Ubicación no disponible. Puedes definirla manualmente."
            onChange?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        isRequestingLocation = false
        defaults.set(location.coordinate.latitude, forKey: "cellium.weather.latitude")
        defaults.set(location.coordinate.longitude, forKey: "cellium.weather.longitude")
        defaults.set("Ubicación actual", forKey: "cellium.weather.locationLabel")
        fetchWeather(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            label: "Ubicación actual"
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
        isRequestingLocation = false
        errorMessage = "No se pudo obtener la ubicación. Puedes definirla manualmente."
        onChange?()
    }
}
