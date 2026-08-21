import SwiftUI
import CoreLocation

/// Экран построения маршрута с промежуточными точками
struct RouteBuilderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var routeStore = RouteStore.shared
    @StateObject private var vm = RouteBuilderVM()

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // Список точек
                    List {
                        Section(header: Text("Точки маршрута").foregroundColor(.gray)) {
                            ForEach($vm.waypoints) { $wp in
                                WaypointRow(waypoint: $wp, onDelete: {
                                    vm.waypoints.removeAll { $0.id == wp.id }
                                })
                            }
                            .onMove { vm.waypoints.move(fromOffsets: $0, toOffset: $1) }

                            Button(action: { vm.showAddPoint = true }) {
                                Label("Добавить точку", systemImage: "plus.circle")
                                    .foregroundColor(.cyan)
                            }
                        }

                        if let result = vm.routeResult {
                            Section(header: Text("Маршрут").foregroundColor(.gray)) {
                                HStack {
                                    Image(systemName: "road.lanes").foregroundColor(.cyan)
                                    Text("\(result.distanceKm, specifier: "%.0f") км")
                                }
                                HStack {
                                    Image(systemName: "clock").foregroundColor(.cyan)
                                    Text(formatDuration(result.durationMin))
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)

                    // Кнопки
                    VStack(spacing: 10) {
                        if vm.isBuilding {
                            ProgressView("Строю маршрут...")
                                .tint(.cyan)
                        } else {
                            Button(action: vm.buildRoute) {
                                Label("Построить маршрут", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.cyan)
                                    .foregroundColor(.black)
                                    .font(.headline)
                                    .cornerRadius(14)
                            }
                            .disabled(vm.waypoints.count < 2)
                            .opacity(vm.waypoints.count < 2 ? 0.5 : 1)
                        }

                        if vm.routeResult != nil {
                            Button(action: {
                                vm.saveRoute()
                                dismiss()
                            }) {
                                Label("Сохранить и активировать", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .font(.headline)
                                    .cornerRadius(14)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Новый маршрут")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $vm.showAddPoint) {
                AddWaypointView { name, coord in
                    vm.waypoints.append(Waypoint(name: name, latitude: coord.latitude, longitude: coord.longitude))
                }
            }
            .alert("Ошибка", isPresented: $vm.showError) {
                Button("OK") {}
            } message: { Text(vm.errorMessage) }
        }
    }

    func formatDuration(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
    }
}

struct WaypointRow: View {
    @Binding var waypoint: Waypoint
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill").foregroundColor(.cyan)
            Text(waypoint.name)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.7))
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class RouteBuilderVM: ObservableObject {
    @Published var waypoints: [Waypoint] = [
        Waypoint(name: "Новороссийск", latitude: 44.7236, longitude: 37.7680),
        Waypoint(name: "Москва", latitude: 55.7558, longitude: 37.6173)
    ]
    @Published var routeResult: RoutingService.RouteResult?
    @Published var isBuilding = false
    @Published var showAddPoint = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var routeName = "Маршрут \(Date().formatted(.dateTime.day().month()))"

    func buildRoute() {
        Task {
            isBuilding = true
            let coords = waypoints.map { $0.coordinate }
            do {
                routeResult = try await RoutingService.shared.buildRoute(waypoints: coords)
            } catch {
                // Офлайн fallback
                routeResult = RoutingService.shared.buildOfflineRoute(waypoints: coords)
                errorMessage = "Нет интернета. Маршрут построен по прямой."
                showError = true
            }
            isBuilding = false
        }
    }

    func saveRoute() {
        guard let result = routeResult else { return }
        let route = SavedRoute(
            name: routeName,
            waypoints: waypoints,
            polyline: result.polyline,
            totalDistanceKm: result.distanceKm
        )
        RouteStore.shared.save(route)
        RouteStore.shared.activate(route)
    }
}
