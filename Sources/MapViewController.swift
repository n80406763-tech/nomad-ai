import UIKit
import MapLibre
import CoreLocation

/// Полный контроллер карты на MapLibre (MLNMapView API)
class MapViewController: UIViewController, MLNMapViewDelegate {

    private var mapView: MLNMapView!
    private var routePolyline: MLNPolyline?
    private var userAnnotation: MLNPointAnnotation?
    private var currentPolyline: [CLLocationCoordinate2D] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        setupHUD()
    }

    private func setupMap() {
        // Стиль карты — бесплатный OpenFreeMap (без API ключа)
        let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
        mapView = MLNMapView(frame: view.bounds, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.compassView.isHidden = false
        mapView.logoView.isHidden = true

        // Начальная точка — Новороссийск
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 44.7236, longitude: 37.7680),
            zoomLevel: 10,
            animated: false
        )
        view.addSubview(mapView)
    }

    // MARK: - HUD (Спидометр)
    private var speedLabel: UILabel!
    private var distanceLabel: UILabel!
    private var modeLabel: UILabel!

    private func setupHUD() {
        let hud = UIView()
        hud.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.88)
        hud.layer.cornerRadius = 16
        hud.layer.borderWidth = 1
        hud.layer.borderColor = UIColor.cyan.withAlphaComponent(0.3).cgColor
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        speedLabel = makeLabel(size: 36, weight: .bold, color: .cyan)
        speedLabel.text = "0"

        let kmhLabel = makeLabel(size: 11, weight: .medium, color: .gray)
        kmhLabel.text = "КМ/Ч"

        distanceLabel = makeLabel(size: 12, weight: .semibold, color: .white)
        distanceLabel.text = ""
        distanceLabel.textAlignment = .center

        modeLabel = makeLabel(size: 10, weight: .bold, color: .orange)
        modeLabel.text = "● GPS"

        [speedLabel, kmhLabel, distanceLabel, modeLabel].forEach { hud.addSubview($0!) }

        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            hud.widthAnchor.constraint(equalToConstant: 96),
            hud.heightAnchor.constraint(equalToConstant: 108),

            speedLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            speedLabel.topAnchor.constraint(equalTo: hud.topAnchor, constant: 12),

            kmhLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            kmhLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 2),

            distanceLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            distanceLabel.topAnchor.constraint(equalTo: kmhLabel.bottomAnchor, constant: 4),
            distanceLabel.leadingAnchor.constraint(equalTo: hud.leadingAnchor, constant: 4),
            distanceLabel.trailingAnchor.constraint(equalTo: hud.trailingAnchor, constant: -4),

            modeLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            modeLabel.bottomAnchor.constraint(equalTo: hud.bottomAnchor, constant: -8)
        ])

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateHUD()
        }
    }

    private func makeLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func updateHUD() {
        let spd = LocationManager.shared.speed
        speedLabel.text = "\(Int(spd))"

        if let loc = LocationManager.shared.location {
            let acc = loc.horizontalAccuracy
            modeLabel.text = acc < 20 ? "● GPS ✓" : "● GPS ~\(Int(acc))м"
            modeLabel.textColor = acc < 20 ? .green : .orange
        }

        if let loc = LocationManager.shared.location,
           let rem = RouteStore.shared.remainingDistance(from: loc) {
            distanceLabel.text = rem > 1 ? "\(Int(rem)) км" : "\(Int(rem * 1000)) м"
        }
    }

    // MARK: - Public API
    func updateUserLocation(_ location: CLLocation) {
        // MLNMapView следит сам через showsUserLocation
    }

    func drawRoute(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty, coordinates.count != currentPolyline.count else { return }
        currentPolyline = coordinates
        clearRoute()

        var coords = coordinates
        let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
        mapView.addAnnotation(polyline)
        routePolyline = polyline
    }

    func clearRoute() {
        if let old = routePolyline {
            mapView.removeAnnotation(old)
            routePolyline = nil
        }
    }

    // MARK: - MLNMapViewDelegate
    func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
        return annotation is MLNPolyline ? .cyan : .blue
    }

    func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
        return 5.0
    }

    func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
        return 0.9
    }
}
