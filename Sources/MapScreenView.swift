import SwiftUI
import CoreLocation

struct MapScreenView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var routeStore = RouteStore.shared
    @ObservedObject private var appState = AppState.shared
    @State private var showRouteBuilder = false
    @State private var showPOIPanel = false
    @State private var showGPSDiagnostics = false
    @State private var showOffRouteBanner = false
    @State private var offRouteDistance: Double = 0

    var body: some View {
        ZStack {
            MapView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let route = routeStore.activeRoute {
                        Label(route.name, systemImage: "location.north.line.fill")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                if shouldShowGPSNotice {
                    Button { showGPSDiagnostics = true } label: {
                        Label(gpsNoticeText, systemImage: "location.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
                    Button { showGPSDiagnostics = true } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .accessibilityLabel("Открыть диагностику GPS")
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showRouteBuilder) { RouteBuilderView() }
        .sheet(isPresented: $showPOIPanel) { PoiSearchView() }
        .sheet(isPresented: $showGPSDiagnostics) { GPSDiagnosticsView() }
        .onAppear {
            locationManager.requestPermission()
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

    private var shouldShowGPSNotice: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return locationManager.location == nil || locationManager.accuracy > 65
        default:
            return true
        }
    }

    private var gpsNoticeText: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "GPS отключён — открыть настройки"
        case .notDetermined:
            return "Запрашиваем доступ к GPS…"
        case .authorizedAlways, .authorizedWhenInUse:
            if let location = locationManager.location {
                return "GPS слабый: ±\(Int(location.horizontalAccuracy)) м — диагностика"
            }
            return "Ищу GPS — открыть диагностику"
        @unknown default:
            return "Проверить GPS"
        }
    }
}