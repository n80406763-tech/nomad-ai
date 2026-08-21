import SwiftUI
import MapLibre
import CoreLocation

/// Главный экран карты (вкладка 1)
struct MapScreenView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var routeStore = RouteStore.shared
    @State private var showRouteBuilder = false
    @State private var showOffRouteBanner = false
    @State private var offRouteDistance: Double = 0
    @State private var showPOIPanel = false
    @State private var selectedPOICategory: POICategory = .fuel
    @State private var nearbyPOIs: [POIItem] = []

    var body: some View {
        ZStack {
            // Карта занимает весь экран
            MapView()
                .edgesIgnoringSafeArea(.all)

            // Баннер "Вы съехали с маршрута"
            if showOffRouteBanner {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Вы съехали с маршрута на \(Int(offRouteDistance)) м")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.top, 60)
                    Spacer()
                }
            }

            // Нижняя панель кнопок
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    // Кнопка построить маршрут
                    Button(action: { showRouteBuilder = true }) {
                        Label("Маршрут", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.cyan)
                            .foregroundColor(.black)
                            .cornerRadius(20)
                    }

                    // Кнопка POI поиска
                    Button(action: { showPOIPanel = true }) {
                        Label("Заправки / Отели", systemImage: "fuelpump.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Nomad AI")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRouteBuilder) { RouteBuilderView() }
        .sheet(isPresented: $showPOIPanel) { PoiSearchView() }
        .onReceive(locationManager.$location) { loc in
            guard let loc = loc else { return }
            checkOffRoute(location: loc)
        }
    }

    private func checkOffRoute(location: CLLocation) {
        guard routeStore.activeRoute != nil else {
            showOffRouteBanner = false
            return
        }
        if let dist = routeStore.distanceFromActiveRoute(location: location) {
            offRouteDistance = dist
            withAnimation { showOffRouteBanner = dist > 200 }
        }
    }
}
