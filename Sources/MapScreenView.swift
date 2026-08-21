import SwiftUI
import CoreLocation

struct MapScreenView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var routeStore = RouteStore.shared
    @ObservedObject private var appState = AppState.shared
    @State private var showRouteBuilder = false
    @State private var showPOIPanel = false
    @State private var showOffRouteBanner = false
    @State private var offRouteDistance: Double = 0

    var body: some View {
        ZStack {
            MapView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let route = routeStore.activeRoute {
                        Label(route.name, systemImage: "location.north.line.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Button { showRouteBuilder = true } label: {
                        Image(systemName: "route")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    Button { showPOIPanel = true } label: {
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                }

                if showOffRouteBanner {
                    Label("Вы съехали с маршрута на \(Int(offRouteDistance)) м", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                }

                Spacer()

                HStack {
                    Spacer()
                    Button {
                        appState.recenterToken = UUID()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                }
                .padding(.bottom, 22)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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