import SwiftUI

/// Добавление точки маршрута: поиск по названию (Nominatim/OSM, офлайн - ввод вручную)
struct AddWaypointView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var results: [NominatimResult] = []
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
            let res = await NominatimService.shared.search(query: searchText)
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

// MARK: - Nominatim (бесплатный геокодер OSM)
struct NominatimResult: Identifiable, Codable {
    let id: String
    let displayName: String
    let lat: Double
    let lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    enum CodingKeys: String, CodingKey {
        case id = "place_id"
        case displayName = "display_name"
        case lat, lon
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = String(try c.decode(Int.self, forKey: .id))
        displayName = try c.decode(String.self, forKey: .displayName)
        lat = Double(try c.decode(String.self, forKey: .lat)) ?? 0
        lon = Double(try c.decode(String.self, forKey: .lon)) ?? 0
    }
}

class NominatimService {
    static let shared = NominatimService()
    func search(query: String) async -> [NominatimResult] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://nominatim.openstreetmap.org/search?q=\(q)&format=json&limit=10&accept-language=ru"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.setValue("NomadAI/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let results = try? JSONDecoder().decode([NominatimResult].self, from: data) else { return [] }
        return results
    }
}

import CoreLocation
