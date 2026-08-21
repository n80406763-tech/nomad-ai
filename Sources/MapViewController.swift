import UIKit
import MapKit
import CoreLocation

final class MapViewController: UIViewController, MKMapViewDelegate {
    private var mapView = MKMapView()
    private var routePolyline: MKPolyline?
    private var userAnnotation: MKPointAnnotation?
    private var currentPolyline: [CLLocationCoordinate2D] = []
    private var hasCenteredOnUser = false
    private var tileOverlay: MKTileOverlay?

    private var hud = UIView()
    private var speedLabel = UILabel()
    private var distanceLabel = UILabel()
    private var modeLabel = UILabel()

    /// Скрыть HUD со скоростью/дистанцией (для предпросмотра маршрутов)
    var hudHidden: Bool = false {
        didSet { hud.isHidden = hudHidden }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        setupHUD()
        hud.isHidden = hudHidden
    }

    private func setupMap() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.mapType = .standard
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.7236, longitude: 37.7680),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        ), animated: false)

        let overlay = MKTileOverlay(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        overlay.canReplaceMapContent = true
        overlay.minimumZ = 3
        overlay.maximumZ = 19
        tileOverlay = overlay
        mapView.addOverlay(overlay)

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
        modeLabel.text = "GPS ожидает"

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
        if let location = locationManager.location {
            let accuracy = Int(location.horizontalAccuracy)
            modeLabel.text = accuracy < 20 ? "GPS точно" : "GPS ±\(accuracy) м"
            modeLabel.textColor = accuracy < 20 ? .systemGreen : .systemOrange
        } else {
            modeLabel.text = "GPS ожидает"
        }
        if let location = locationManager.location,
           let remaining = RouteStore.shared.remainingDistance(from: location) {
            distanceLabel.text = remaining > 1 ? "\(Int(remaining)) км" : "\(Int(remaining * 1000)) м"
        } else {
            distanceLabel.text = "Нет маршрута"
        }
    }

    func updateUserLocation(_ location: CLLocation) {
        if let annotation = userAnnotation {
            annotation.coordinate = location.coordinate
        } else {
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = "Вы здесь"
            mapView.addAnnotation(annotation)
            userAnnotation = annotation
        }
        if !hasCenteredOnUser {
            hasCenteredOnUser = true
            mapView.setRegion(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ), animated: true)
        }
    }

    /// Мгновенно переносит камеру к текущему местоположению — используется при нажатии «Начать поездку»
    func centerOnUser(force: Bool) {
        guard let location = LocationManager.shared.location else { return }
        hasCenteredOnUser = true
        mapView.setRegion(MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ), animated: true)
    }

    func drawRoute(_ coordinates: [CLLocationCoordinate2D], fitCamera: Bool = true) {
        guard coordinates.count >= 2 else { return }
        if coordinates.elementsEqual(currentPolyline, by: { $0.latitude == $1.latitude && $0.longitude == $1.longitude }) { return }
        clearRoute()
        currentPolyline = coordinates
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        routePolyline = polyline
        if fitCamera {
            mapView.setVisibleMapRect(polyline.boundingMapRect.insetBy(dx: -5000, dy: -5000), animated: true)
        }
    }

    func clearRoute() {
        if let routePolyline { mapView.removeOverlay(routePolyline) }
        routePolyline = nil
        currentPolyline = []
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tile = overlay as? MKTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tile)
        }
        guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = .systemTeal
        renderer.lineWidth = 5
        renderer.alpha = 0.9
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation === userAnnotation else { return nil }
        let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "user")
        view.markerTintColor = .systemTeal
        view.glyphImage = UIImage(systemName: "car.fill")
        return view
    }
}
