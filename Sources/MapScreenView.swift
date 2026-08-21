import SwiftUI
import UIKit
import MapLibre
import CoreLocation

struct SafeMapView: View {
    @ObservedObject private var diagnostics = DiagnosticsStore.shared
    @ObservedObject private var locationManager = LocationManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "map.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundColor(.cyan)

                VStack(spacing: 8) {
                    Text("Карта временно отключена")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Нативный модуль MapLibre закрывает приложение во время запуска. Остальные функции работают, поэтому карта заблокирована до замены модуля.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Label(locationStatus, systemImage: locationIcon)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(locationManager.authorizationStatus == .denied ? .orange : .secondary)

                    Button {
                        locationManager.requestPermission()
                    } label: {
                        Label("Разрешить GPS", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted)

                    if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                        Button("Открыть настройки GPS") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    diagnostics.report(
                        title: "MapLibre отключён",
                        details: "Проверка карты не запускается, потому что предыдущая инициализация MapLibre/Metal завершала процесс. Для восстановления карты нужен отдельный модуль или другая версия MapLibre."
                    )
                } label: {
                    Label("Почему карта недоступна", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 32)
        }
        .navigationTitle("Карта")
    }

    private var locationStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return locationManager.location == nil ? "GPS разрешён, ожидается сигнал" : "GPS работает"
        case .denied: return "GPS запрещён в настройках"
        case .restricted: return "GPS ограничен системой"
        case .notDetermined: return "GPS ещё не запрашивался"
        @unknown default: return "Статус GPS неизвестен"
        }
    }

    private var locationIcon: String {
        locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse
            ? "location.fill" : "location.slash"
    }
}

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
