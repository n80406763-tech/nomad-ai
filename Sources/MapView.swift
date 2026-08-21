import SwiftUI
import CoreLocation

struct MapView: UIViewControllerRepresentable {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var routeStore = RouteStore.shared
    @ObservedObject var appState = AppState.shared

    /// Если задан — показываем этот маршрут вместо активного (используется в предпросмотре вариантов маршрута)
    var previewPolyline: [CLLocationCoordinate2D]? = nil
    /// Показывать плавающий HUD (скорость/дистанция) — скрываем в режиме предпросмотра
    var showsHUD: Bool = true

    func makeUIViewController(context: Context) -> MapViewController {
        let vc = MapViewController()
        vc.loadViewIfNeeded()
        vc.hudHidden = !showsHUD
        return vc
    }

    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        if let loc = locationManager.location {
            uiViewController.updateUserLocation(loc)
        }
        if let preview = previewPolyline {
            uiViewController.drawRoute(preview, fitCamera: true)
        } else if let route = routeStore.activeRoute {
            uiViewController.drawRoute(route.polyline, fitCamera: false)
        } else {
            uiViewController.clearRoute()
        }

        if context.coordinator.lastRecenterToken != appState.recenterToken {
            context.coordinator.lastRecenterToken = appState.recenterToken
            uiViewController.centerOnUser(force: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastRecenterToken = AppState.shared.recenterToken
    }
}
