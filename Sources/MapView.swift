import SwiftUI

struct MapView: UIViewControllerRepresentable {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var routeStore = RouteStore.shared

    func makeUIViewController(context: Context) -> MapViewController {
        let vc = MapViewController()
        vc.loadViewIfNeeded()
        return vc
    }

    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        if let loc = locationManager.location {
            uiViewController.updateUserLocation(loc)
        }
        if let route = routeStore.activeRoute {
            uiViewController.drawRoute(route.polyline)
        } else {
            uiViewController.clearRoute()
        }
    }
}
