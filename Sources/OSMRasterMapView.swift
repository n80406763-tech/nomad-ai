import UIKit
import CoreLocation

private struct OSMVisualTile: Hashable {
    let zoom: Int
    let rawX: Int
    let y: Int
}

final class OSMRasterMapView: UIView {
    private let tileSize: CGFloat = 256
    private var mapCenter = CLLocationCoordinate2D(latitude: 44.7236, longitude: 37.7680)
    private var zoom = 11
    private var panStartCenter: CLLocationCoordinate2D?
    private var route: [CLLocationCoordinate2D] = []
    private var userLocation: CLLocation?
    private var tileViews: [OSMVisualTile: UIImageView] = [:]

    private let routeLayer = CAShapeLayer()
    private let userLayer = CAShapeLayer()
    private let attributionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = UIColor(red: 0.89, green: 0.91, blue: 0.88, alpha: 1)

        routeLayer.fillColor = UIColor.clear.cgColor
        routeLayer.strokeColor = UIColor.systemTeal.cgColor
        routeLayer.lineWidth = 6
        routeLayer.lineCap = .round
        routeLayer.lineJoin = .round
        layer.addSublayer(routeLayer)

        userLayer.fillColor = UIColor.systemBlue.cgColor
        userLayer.strokeColor = UIColor.white.cgColor
        userLayer.lineWidth = 3
        layer.addSublayer(userLayer)

        attributionLabel.text = "© OpenStreetMap contributors"
        attributionLabel.font = .systemFont(ofSize: 10, weight: .medium)
        attributionLabel.textColor = .white
        attributionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        attributionLabel.textAlignment = .center
        attributionLabel.layer.cornerRadius = 4
        attributionLabel.clipsToBounds = true
        addSubview(attributionLabel)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomIn))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attributionLabel.frame = CGRect(x: 8, y: bounds.height - 28, width: 178, height: 20)
        refreshTiles()
        refreshRoute()
        refreshUserMarker()
    }

    func setRoute(_ coordinates: [CLLocationCoordinate2D], fitCamera: Bool) {
        guard !sameCoordinates(route, coordinates) else { return }
        route = coordinates
        if fitCamera { fitRoute() }
        setNeedsLayout()
    }

    func clearRoute() {
        route = []
        routeLayer.path = nil
    }

    func setUserLocation(_ location: CLLocation) {
        let wasUnknown = userLocation == nil
        userLocation = location
        if wasUnknown {
            mapCenter = location.coordinate
            zoom = max(zoom, 13)
        }
        setNeedsLayout()
    }

    func center(on coordinate: CLLocationCoordinate2D) {
        mapCenter = coordinate
        zoom = max(zoom, 13)
        setNeedsLayout()
    }

    private func refreshTiles() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let tileCount = 1 << zoom
        let viewportOrigin = viewportOriginAtCurrentZoom()
        let minTileX = Int(floor(viewportOrigin.x / tileSize))
        let maxTileX = Int(floor((viewportOrigin.x + bounds.width) / tileSize))
        let minTileY = max(0, Int(floor(viewportOrigin.y / tileSize)))
        let maxTileY = min(tileCount - 1, Int(floor((viewportOrigin.y + bounds.height) / tileSize)))
        var visibleTiles = Set<OSMVisualTile>()

        guard minTileY <= maxTileY else { return }
        for rawX in minTileX...maxTileX {
            let normalizedX = ((rawX % tileCount) + tileCount) % tileCount
            for tileY in minTileY...maxTileY {
                let visualTile = OSMVisualTile(zoom: zoom, rawX: rawX, y: tileY)
                visibleTiles.insert(visualTile)
                let frame = CGRect(
                    x: CGFloat(rawX) * tileSize - viewportOrigin.x,
                    y: CGFloat(tileY) * tileSize - viewportOrigin.y,
                    width: tileSize,
                    height: tileSize
                )

                if let imageView = tileViews[visualTile] {
                    imageView.frame = frame
                    continue
                }

                let imageView = UIImageView(frame: frame)
                imageView.contentMode = .scaleToFill
                imageView.image = Self.placeholderTile
                insertSubview(imageView, at: 0)
                tileViews[visualTile] = imageView

                let tileKey = OSMTileKey(zoom: zoom, x: normalizedX, y: tileY)
                OSMTileStore.shared.image(for: tileKey) { [weak self, weak imageView] image in
                    guard let self, let imageView,
                          let visibleView = self.tileViews[visualTile], visibleView === imageView else { return }
                    imageView.image = image ?? Self.placeholderTile
                }
            }
        }

        let obsoleteTiles = tileViews.keys.filter { !visibleTiles.contains($0) }
        for tile in obsoleteTiles {
            tileViews[tile]?.removeFromSuperview()
            tileViews[tile] = nil
        }
    }

    private func refreshRoute() {
        guard route.count > 1 else {
            routeLayer.path = nil
            return
        }

        let origin = viewportOriginAtCurrentZoom()
        let path = UIBezierPath()
        for (index, coordinate) in route.enumerated() {
            let point = mapPoint(for: coordinate)
            let screenPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            if index == 0 { path.move(to: screenPoint) } else { path.addLine(to: screenPoint) }
        }
        routeLayer.frame = bounds
        routeLayer.path = path.cgPath
    }

    private func refreshUserMarker() {
        guard let userLocation else {
            userLayer.path = nil
            return
        }

        let mapPoint = mapPoint(for: userLocation.coordinate)
        let origin = viewportOriginAtCurrentZoom()
        let point = CGPoint(x: mapPoint.x - origin.x, y: mapPoint.y - origin.y)
        let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        userLayer.frame = bounds
        userLayer.path = marker.cgPath
    }

    private func fitRoute() {
        guard route.count > 1, bounds.width > 0, bounds.height > 0 else { return }

        let minLatitude = route.map(\.latitude).min() ?? mapCenter.latitude
        let maxLatitude = route.map(\.latitude).max() ?? mapCenter.latitude
        let minLongitude = route.map(\.longitude).min() ?? mapCenter.longitude
        let maxLongitude = route.map(\.longitude).max() ?? mapCenter.longitude
        mapCenter = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        for candidateZoom in stride(from: 15, through: 2, by: -1) {
            let points = route.map { mapPoint(for: $0, zoom: candidateZoom) }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { continue }
            if maxX - minX <= bounds.width * 0.72, maxY - minY <= bounds.height * 0.62 {
                zoom = candidateZoom
                return
            }
        }
        zoom = 2
    }

    private func viewportOriginAtCurrentZoom() -> CGPoint {
        let centerPoint = mapPoint(for: mapCenter)
        return CGPoint(x: centerPoint.x - bounds.width / 2, y: centerPoint.y - bounds.height / 2)
    }

    private func mapPoint(for coordinate: CLLocationCoordinate2D, zoom: Int? = nil) -> CGPoint {
        let level = zoom ?? self.zoom
        let worldSize = Double(tileSize) * pow(2, Double(level))
        let latitude = min(max(coordinate.latitude, -85.05112878), 85.05112878)
        let latitudeRadians = latitude * .pi / 180
        let x = (coordinate.longitude + 180) / 360 * worldSize
        let y = (1 - log(tan(latitudeRadians) + 1 / cos(latitudeRadians)) / .pi) / 2 * worldSize
        return CGPoint(x: x, y: y)
    }

    private func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
        let worldSize = Double(tileSize) * pow(2, Double(zoom))
        let longitude = Double(point.x) / worldSize * 360 - 180
        let latitudeRadians = atan(sinh(.pi * (1 - 2 * Double(point.y) / worldSize)))
        return CLLocationCoordinate2D(latitude: latitudeRadians * 180 / .pi, longitude: longitude)
    }

    private func sameCoordinates(_ lhs: [CLLocationCoordinate2D], _ rhs: [CLLocationCoordinate2D]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            abs($0.latitude - $1.latitude) < 0.000_001 && abs($0.longitude - $1.longitude) < 0.000_001
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            panStartCenter = mapCenter
        case .changed:
            guard let panStartCenter else { return }
            let point = mapPoint(for: panStartCenter)
            mapCenter = coordinate(for: CGPoint(x: point.x - translation.x, y: point.y - translation.y))
            setNeedsLayout()
        default:
            panStartCenter = nil
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        if recognizer.scale > 1.1 {
            zoom = min(18, zoom + 1)
        } else if recognizer.scale < 0.9 {
            zoom = max(2, zoom - 1)
        }
        setNeedsLayout()
    }

    @objc private func zoomIn() {
        zoom = min(18, zoom + 1)
        setNeedsLayout()
    }

    private static let placeholderTile: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        return renderer.image { context in
            UIColor(red: 0.88, green: 0.90, blue: 0.86, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor(red: 0.76, green: 0.80, blue: 0.74, alpha: 1).setStroke()
            context.cgContext.setLineWidth(1)
            stride(from: 0, through: 256, by: 32).forEach { value in
                context.cgContext.move(to: CGPoint(x: value, y: 0))
                context.cgContext.addLine(to: CGPoint(x: value, y: 256))
                context.cgContext.move(to: CGPoint(x: 0, y: value))
                context.cgContext.addLine(to: CGPoint(x: 256, y: value))
            }
            context.cgContext.strokePath()
        }
    }()
}