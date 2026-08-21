import SwiftUI

/// Список сохранённых маршрутов
struct RoutesListView: View {
    @ObservedObject var routeStore = RouteStore.shared
    @State private var showBuilder = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

            if routeStore.routes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 64))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Нет сохранённых маршрутов")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text("Нажмите «+», чтобы создать первый\nмаршрут, например: Новороссийск → Москва")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button(action: { showBuilder = true }) {
                        Label("Создать маршрут", systemImage: "plus.circle.fill")
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.cyan)
                            .foregroundColor(.black)
                            .font(.headline)
                            .cornerRadius(14)
                    }
                }
            } else {
                List {
                    ForEach(routeStore.routes) { route in
                        RouteCard(route: route)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onDelete { idx in
                        idx.forEach { routeStore.delete(routeStore.routes[$0]) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Маршруты")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showBuilder = true }) {
                    Image(systemName: "plus")
                        .foregroundColor(.cyan)
                }
            }
        }
        .sheet(isPresented: $showBuilder) { RouteBuilderView() }
    }
}

struct RouteCard: View {
    let route: SavedRoute
    @ObservedObject var routeStore = RouteStore.shared

    var isActive: Bool { routeStore.activeRoute?.id == route.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isActive ? "location.fill" : "location")
                    .foregroundColor(isActive ? .cyan : .gray)
                Text(route.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if isActive {
                    Text("АКТИВЕН")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan)
                        .foregroundColor(.black)
                        .cornerRadius(6)
                }
            }

            // Список точек маршрута
            ForEach(route.waypoints) { wp in
                HStack(spacing: 6) {
                    Image(systemName: "mappin").font(.caption).foregroundColor(.cyan)
                    Text(wp.name).font(.subheadline).foregroundColor(.gray)
                }
            }

            HStack(spacing: 20) {
                Label("\(route.totalDistanceKm, specifier: "%.0f") км", systemImage: "road.lanes")
                    .font(.caption)
                    .foregroundColor(.gray)
                Label(route.createdAt.formatted(.dateTime.day().month().year()), systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // Кнопки
            HStack(spacing: 10) {
                Button(action: {
                    if isActive { routeStore.deactivate() }
                    else { routeStore.activate(route) }
                }) {
                    Text(isActive ? "Деактивировать" : "Активировать")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isActive ? Color.red.opacity(0.2) : Color.cyan)
                        .foregroundColor(isActive ? .red : .black)
                        .cornerRadius(10)
                }

                Button(action: { routeStore.delete(route) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isActive ? Color.cyan : Color.clear, lineWidth: 1.5)
                )
        )
    }
}
