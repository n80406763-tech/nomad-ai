import UIKit
import CoreLocation

final class MapViewController: UIViewController {
    private let mapView = OSMVectorMapView()
    private var currentPolyline: [CLLocationCoordinate2D] = []

    private var hud = UIView()
    private var speedLabel = UILabel()
    private var distanceLabel = UILabel()
    private var modeLabel = UILabel()

    /// Скрыть HUD со скоростью/дистанцией (для предпросмотра маршрутов)
    var hudHidden: Bool = false {
        didSet { hud.isHidden = hudHidden }
    }

    override func loadView() {
        view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        setupHUD()
        hud.isHidden = hudHidden
    }

    private func setupMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupHUD() {
        let hud = UIView()
        hud.translatesAutoresizingMaskIntoConstraints = false
        hud.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        hud.layer.cornerRadius = 16
        view.addSubview(hud)
        self.hud = hud

        speedLabel = makeLabel(size: 32, weight: .bold, color: .systemTeal)
        speedLabel.text = "0"
        let kmhLabel = makeLabel(size: 11, weight: .medium, color: .secondaryLabel)
        kmhLabel.text = "КМ/Ч"
        distanceLabel = makeLabel(size: 12, weight: .semibold, color: .label)
        modeLabel = makeLabel(size: 10, weight: .bold, color: .systemOrange)
        modeLabel.text = "Нужен доступ к GPS"

        [speedLabel, kmhLabel, distanceLabel, modeLabel].forEach(hud.addSubview)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            hud.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            hud.heightAnchor.constraint(equalToConstant: 112),
            speedLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            speedLabel.topAnchor.constraint(equalTo: hud.topAnchor, constant: 10),
            kmhLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            kmhLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor),
            distanceLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            distanceLabel.topAnchor.constraint(equalTo: kmhLabel.bottomAnchor, constant: 5),
            modeLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            modeLabel.bottomAnchor.constraint(equalTo: hud.bottomAnchor, constant: -9)
        ])
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateHUD()
        }
    }

    private func makeLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func updateHUD() {
        let locationManager = LocationManager.shared
        speedLabel.text = "\(Int(locationManager.speed))"
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let location = locationManager.location {
                let accuracy = Int(location.horizontalAccuracy)
                if locationManager.isSignalStale {
                    modeLabel.text = "GPS потерян"
                    modeLabel.textColor = .systemRed
                } else {
                    modeLabel.text = accuracy < 20 ? "GPS точно" : "GPS ±\(accuracy) м"
                    modeLabel.textColor = accuracy < 20 ? .systemGreen : .systemOrange
                }
            } else {
                modeLabel.text = "Ищу GPS"
                modeLabel.textColor = .systemOrange
            }
        case .denied, .restricted:
            modeLabel.text = "GPS запрещён"
            modeLabel.textColor = .systemRed
        default:
            modeLabel.text = "Нужен доступ к GPS"
            modeLabel.textColor = .systemOrange
        }
        if let location = locationManager.location,
           let remaining = RouteStore.shared.remainingDistance(from: location) {
            distanceLabel.text = remaining > 1 ? "\(Int(remaining)) км" : "\(Int(remaining * 1000)) м"
        } else {
            distanceLabel.text = "Нет маршрута"
        }
    }

    func updateUserLocation(_ location: CLLocation) {
        mapView.setUserLocation(location)
    }

    /// Мгновенно переносит камеру к текущему местоположению — используется при нажатии «Начать поездку»
    func centerOnUser(force: Bool) {
        guard let location = LocationManager.shared.location else { return }
        mapView.center(on: location.coordinate)
    }

    func drawRoute(_ coordinates: [CLLocationCoordinate2D], fitCamera: Bool = true) {
        guard coordinates.count >= 2 else { return }
        if coordinates.elementsEqual(currentPolyline, by: {
            abs($0.latitude - $1.latitude) < 0.000_001 && abs($0.longitude - $1.longitude) < 0.000_001
        }) { return }
        currentPolyline = coordinates
        mapView.setRoute(coordinates, fitCamera: fitCamera)
    }

    func clearRoute() {
        currentPolyline = []
        mapView.clearRoute()
    }
}
