import SwiftUI
import CoreLocation

/// Экран поиска POI (заправки, отели и т.д.) в радиусе от текущего положения или вдоль маршрута
struct PoiSearchView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @State private var selectedCategory: POICategory = .fuel
    @State private var radiusKm: Double = 50
    @State private var results: [POIItem] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var noResults = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Категории (горизонтальный скролл)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(POICategory.allCases, id: \.self) { cat in
                            CategoryChip(category: cat, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                                search()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                // Радиус
                HStack {
                    Text("Радиус поиска:")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Slider(value: $radiusKm, in: 5...300, step: 5)
                        .tint(.cyan)
                    Text("\(Int(radiusKm)) км")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.cyan)
                        .frame(width: 50)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Строка поиска
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Название, бренд...", text: $searchText)
                        .onSubmit { search() }
                    if isLoading { ProgressView().tint(.cyan) }
                    else {
                        Button(action: search) {
                            Text("Найти")
                                .font(.subheadline.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.cyan)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(10)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider()

                // Результаты
                if noResults {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash").font(.system(size: 44)).foregroundColor(.gray.opacity(0.5))
                        Text("Ничего не найдено").foregroundColor(.gray)
                        Text("Попробуйте увеличить радиус").font(.caption).foregroundColor(.gray.opacity(0.7))
                    }
                    Spacer()
                } else {
                    List(results) { poi in
                        POIRow(poi: poi)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Поиск")
        .onAppear { search() }
    }

    func search() {
        guard let loc = locationManager.location else { return }
        isLoading = true
        noResults = false
        Task {
            results = await OverpassService.shared.searchPOI(
                category: selectedCategory,
                center: loc.coordinate,
                radiusKm: radiusKm,
                keyword: searchText.isEmpty ? nil : searchText
            )
            isLoading = false
            noResults = results.isEmpty
        }
    }
}

struct CategoryChip: View {
    let category: POICategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                Text(category.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.cyan : Color(UIColor.secondarySystemBackground))
            .foregroundColor(isSelected ? .black : .white)
            .cornerRadius(20)
        }
    }
}

struct POIRow: View {
    let poi: POIItem
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: poi.category.icon)
                .font(.title2)
                .foregroundColor(.cyan)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(poi.name.isEmpty ? poi.category.rawValue : poi.name)
                    .font(.body.weight(.medium))
                if let addr = poi.address {
                    Text(addr).font(.caption).foregroundColor(.gray).lineLimit(2)
                }
                if let brand = poi.brand {
                    Text(brand).font(.caption.bold()).foregroundColor(.cyan)
                }
            }
            Spacer()
            // Расстояние от пользователя
            if let loc = LocationManager.shared.location {
                let d = CLLocation(latitude: poi.latitude, longitude: poi.longitude).distance(from: loc)
                Text(d < 1000 ? "\(Int(d)) м" : "\(Int(d/1000)) км")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 6)
    }
}
