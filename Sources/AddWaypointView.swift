import SwiftUI
import CoreLocation

/// Добавление точки маршрута из локального индекса России.
struct AddWaypointView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var results: [OfflinePlaceResult] = []
    @State private var isSearching = false
    var onAdd: (String, CLLocationCoordinate2D) -> Void

    var body: some View {
        NavigationView {
            VStack {
                // Поиск
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Введите город или адрес...", text: $searchText)
                        .onSubmit { search() }
                    if isSearching { ProgressView().tint(.cyan) }
                }
                .padding(10)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding()

                // Результаты
                List(results) { result in
                    Button(action: {
                        onAdd(result.displayName, result.coordinate)
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.displayName)
                                .font(.body)
                                .lineLimit(2)
                            Text("\(result.lat, specifier: "%.4f"), \(result.lon, specifier: "%.4f")")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listStyle(.plain)

                // Добавить по координатам вручную
                Button(action: addMyLocation) {
                    Label("Добавить мою текущую позицию", systemImage: "location.fill")
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundColor(.cyan)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Добавить точку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: search) {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
    }

    func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        Task { @MainActor in
            let res = await OfflinePlaceSearchService.shared.search(query: searchText)
            self.results = res
            self.isSearching = false
        }
    }

    func addMyLocation() {
        if let loc = LocationManager.shared.location {
            onAdd("Моя позиция", loc.coordinate)
            dismiss()
        }
    }
}
