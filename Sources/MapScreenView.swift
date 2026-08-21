import SwiftUI
import CoreLocation

struct MapScreenView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var routeStore = RouteStore.shared
    @State private var showRouteBuilder = false
    @State private var showPOIPanel = false
    @State private var showOffRouteBanner = false
    @State private var offRouteDistance: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            MapView()
                .ignoresSafeArea()

            if showOffRouteBanner {
                Label("Вы съехали с маршрута на \(Int(offRouteDistance)) м", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { showRouteBuilder = true } label: {
                    Label("Маршрут", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { showPOIPanel = true } label: {
                    Label("Места", systemImage: "fuelpump.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .navigationTitle("Nomad AI")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRouteBuilder) { RouteBuilderView() }
        .sheet(isPresented: $showPOIPanel) { PoiSearchView() }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
            if locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse {
                locationManager.startTracking()
            }
        }
        .onReceive(locationManager.$location) { location in
            guard let location else { return }
            guard routeStore.activeRoute != nil,
                  let distance = routeStore.distanceFromActiveRoute(location: location) else {
                showOffRouteBanner = false
                return
            }
            offRouteDistance = distance
            withAnimation { showOffRouteBanner = distance > 200 }
        }
    }
}