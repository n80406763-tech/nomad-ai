import UIKit
import MapboxMaps
import CoreLocation

/// Полный контроллер карты на MapLibre
class MapViewController: UIViewController {

    private var mapView: MapView!   // MapLibre MapView
    private var userLocationAnnotation: PointAnnotationManager?
    private var routeLayerID = "active-route-layer"
    private var routeSourceID = "active-route-source"
    private var isRouteDrawn = false
    private var currentPolyline: [CLLocationCoordinate2D] = []

    // Offline tile source (скачанный .mbtiles)
    private var useOfflineTiles: Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent("map.mbtiles").path)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
    }

    private func setupMap() {
        // Выбираем источник тайлов: офлайн или онлайн (OpenFreeMap)
        var styleURI: StyleURI
        if useOfflineTiles {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let tilesURL = docs.appendingPathComponent("map.mbtiles")
            // Используем локальный файл стиля с mbtiles
            let styleURL = Bundle.main.url(forResource: "offline_style", withExtension: "json")
                ?? URL(string: "https://tiles.openfreemap.org/styles/liberty")!
            styleURI = StyleURI(url: styleURL) ?? .streets
        } else {
            // Бесплатные онлайн тайлы OpenFreeMap (без API ключа)
            styleURI = StyleURI(url: URL(string: "https://tiles.openfreemap.org/styles/liberty")!) ?? .streets
        }

        let cameraOptions = CameraOptions(
            center: CLLocationCoordinate2D(latitude: 44.723, longitude: 37.768), // Новороссийск
            zoom: 10
        )
        let initOptions = MapInitOptions(cameraOptions: cameraOptions, styleURI: styleURI)

        mapView = MapView(frame: view.bounds, mapInitOptions: initOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.ornaments.compassView.isHidden = false
        mapView.ornaments.scaleBarView.isHidden = false

        // Следовать за пользователем
        mapView.location.options.puckType = .puck2D(Puck2DConfiguration.makeDefault(showBearing: true))

        view.addSubview(mapView)
        setupOverlayUI()
    }

    // MARK: - Overlay HUD
    private var speedLabel: UILabel!
    private var distanceLabel: UILabel!
    private var offlineIndicator: UILabel!

    private func setupOverlayUI() {
        // Карточка спидометра
        let hud = UIView()
        hud.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        hud.layer.cornerRadius = 16
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        speedLabel = UILabel()
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        speedLabel.textColor = .cyan
        speedLabel.text = "0"
        speedLabel.translatesAutoresizingMaskIntoConstraints = false

        let kmhLabel = UILabel()
        kmhLabel.font = .systemFont(ofSize: 12, weight: .medium)
        kmhLabel.textColor = .gray
        kmhLabel.text = "КМ/Ч"
        kmhLabel.translatesAutoresizingMaskIntoConstraints = false

        distanceLabel = UILabel()
        distanceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        distanceLabel.textColor = .white
        distanceLabel.text = ""
        distanceLabel.textAlignment = .center
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false

        offlineIndicator = UILabel()
        offlineIndicator.font = .systemFont(ofSize: 11, weight: .bold)
        offlineIndicator.textColor = useOfflineTiles ? .green : .orange
        offlineIndicator.text = useOfflineTiles ? "● ОФЛАЙН" : "● ОНЛАЙН"
        offlineIndicator.translatesAutoresizingMaskIntoConstraints = false

        hud.addSubview(speedLabel)
        hud.addSubview(kmhLabel)
        hud.addSubview(distanceLabel)
        hud.addSubview(offlineIndicator)

        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            hud.widthAnchor.constraint(equalToConstant: 100),
            hud.heightAnchor.constraint(equalToConstant: 110),

            speedLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            speedLabel.topAnchor.constraint(equalTo: hud.topAnchor, constant: 14),

            kmhLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            kmhLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 2),

            distanceLabel.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            distanceLabel.topAnchor.constraint(equalTo: kmhLabel.bottomAnchor, constant: 4),
            distanceLabel.leadingAnchor.constraint(equalTo: hud.leadingAnchor, constant: 4),
            distanceLabel.trailingAnchor.constraint(equalTo: hud.trailingAnchor, constant: -4),

            offlineIndicator.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            offlineIndicator.bottomAnchor.constraint(equalTo: hud.bottomAnchor, constant: -8)
        ])

        // Обновляем каждую секунду
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateHUD()
        }
    }

    private func updateHUD() {
        let spd = LocationManager.shared.speed
        speedLabel.text = "\(Int(spd))"

        if let loc = LocationManager.shared.location,
           let rem = RouteStore.shared.remainingDistance(from: loc) {
            distanceLabel.text = rem > 1 ? "\(Int(rem)) км" : "\(Int(rem * 1000)) м"
        }
    }

    // MARK: - Public API
    func updateUserLocation(_ location: CLLocation) {
        // MapLibre следит сам через puck, просто центрируем если первый раз
    }

    func drawRoute(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        guard coordinates != currentPolyline else { return }
        currentPolyline = coordinates

        mapView.mapboxMap.onNext(event: .mapLoaded) { [weak self] _ in
            guard let self = self else { return }
            self.removeRouteLayer()
            self.addRouteLayer(coordinates: coordinates)
        }

        // Если карта уже загружена
        if mapView.mapboxMap.isStyleLoaded {
            removeRouteLayer()
            addRouteLayer(coordinates: coordinates)
        }
    }

    func clearRoute() {
        removeRouteLayer()
        currentPolyline = []
    }

    private func addRouteLayer(coordinates: [CLLocationCoordinate2D]) {
        var feature = Feature(geometry: .lineString(LineString(coordinates)))
        var source = GeoJSONSource()
        source.data = .feature(feature)

        var layer = LineLayer(id: routeLayerID)
        layer.source = routeSourceID
        layer.lineColor = .constant(StyleColor(.cyan))
        layer.lineWidth = .constant(5)
        layer.lineCap = .constant(.round)
        layer.lineJoin = .constant(.round)
        layer.lineOpacity = .constant(0.9)

        try? mapView.mapboxMap.style.addSource(source, id: routeSourceID)
        try? mapView.mapboxMap.style.addLayer(layer)
        isRouteDrawn = true
    }

    private func removeRouteLayer() {
        try? mapView.mapboxMap.style.removeLayer(withId: routeLayerID)
        try? mapView.mapboxMap.style.removeSource(withId: routeSourceID)
        isRouteDrawn = false
    }
}
