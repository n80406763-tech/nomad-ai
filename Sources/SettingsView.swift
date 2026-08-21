import SwiftUI

/// Экран настроек: скачивание карт, карты регионов
struct SettingsView: View {
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var downloadedMaps: Set<String> = []
    @State private var showDownloadAlert = false
    @State private var alertMessage = ""

    let regions: [(name: String, subtitle: String, sizeMB: Int, id: String)] = [
        ("Краснодарский край", "Новороссийск и вся область", 120, "krasnodar"),
        ("Ростовская область", "Ростов-на-Дону, Тихорецк", 85, "rostov"),
        ("Воронежская область", "Воронеж, М4", 70, "voronezh"),
        ("Липецкая область", "Трасса М4", 45, "lipetsk"),
        ("Тульская область", "Тула, трасса М4", 55, "tula"),
        ("Московская область", "Москва и Подмосковье", 200, "moscow"),
        ("Весь маршрут Нврс-Мск", "Все регионы за раз (~575 МБ)", 575, "full_route")
    ]

    var body: some View {
        List {
            // Секция карт
            Section(header: sectionHeader(title: "Офлайн карты", icon: "map.fill")) {
                ForEach(regions, id: \.id) { region in
                    RegionDownloadRow(
                        region: region,
                        isDownloaded: downloadedMaps.contains(region.id),
                        isDownloading: isDownloading,
                        onDownload: { downloadRegion(region.id) }
                    )
                }
            }

            // Секция GPS
            Section(header: sectionHeader(title: "GPS и Навигация", icon: "location.fill")) {
                HStack {
                    Image(systemName: "location.circle.fill").foregroundColor(.cyan)
                    Text("Фоновое отслеживание")
                    Spacer()
                    Text("Включено").foregroundColor(.green).font(.caption)
                }
                HStack {
                    Image(systemName: "satellite.fill").foregroundColor(.cyan)
                    Text("Точность")
                    Spacer()
                    Text("Навигация").foregroundColor(.gray).font(.caption)
                }
                HStack {
                    Image(systemName: "gauge.high").foregroundColor(.cyan)
                    Text("Макс. погрешность фильтра")
                    Spacer()
                    Text("65 м").foregroundColor(.gray).font(.caption)
                }
            }

            // Информация о приложении
            Section(header: sectionHeader(title: "О приложении", icon: "info.circle.fill")) {
                HStack {
                    Text("Nomad AI").foregroundColor(.white)
                    Spacer()
                    Text("v1.0.0").foregroundColor(.gray).font(.caption)
                }
                HStack {
                    Text("Карты").foregroundColor(.white)
                    Spacer()
                    Text("OpenStreetMap").foregroundColor(.gray).font(.caption)
                }
                HStack {
                    Text("Маршрутизация").foregroundColor(.white)
                    Spacer()
                    Text("OSRM (бесплатно)").foregroundColor(.gray).font(.caption)
                }
                HStack {
                    Text("GPS").foregroundColor(.white)
                    Spacer()
                    Text("CoreLocation").foregroundColor(.gray).font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Настройки")
        .onAppear { loadDownloadedMaps() }
        .alert("Загрузка карт", isPresented: $showDownloadAlert) {
            Button("OK") {}
        } message: { Text(alertMessage) }
    }

    func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.gray)
    }

    func downloadRegion(_ id: String) {
        // В реальной реализации здесь будет скачивание .mbtiles с нашего CDN
        // Сейчас — симуляция
        alertMessage = "Функция скачивания карт будет доступна в следующем обновлении. Карты OpenStreetMap для регионов Новороссийск-Москва весят ~575 МБ."
        showDownloadAlert = true
    }

    func loadDownloadedMaps() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadedMaps = Set(regions.compactMap { r in
            FileManager.default.fileExists(atPath: docs.appendingPathComponent("\(r.id).mbtiles").path) ? r.id : nil
        })
    }
}

struct RegionDownloadRow: View {
    let region: (name: String, subtitle: String, sizeMB: Int, id: String)
    let isDownloaded: Bool
    let isDownloading: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundColor(isDownloaded ? .green : .cyan)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(region.name).font(.body.weight(.medium))
                Text(region.subtitle).font(.caption).foregroundColor(.gray)
            }

            Spacer()

            if isDownloaded {
                Text("✓ Готово").font(.caption.bold()).foregroundColor(.green)
            } else {
                Button(action: onDownload) {
                    Text("\(region.sizeMB) МБ")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.15))
                        .foregroundColor(.cyan)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
