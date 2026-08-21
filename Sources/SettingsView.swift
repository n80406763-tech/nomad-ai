import SwiftUI

/// Экран настроек: скачивание карт, карты регионов
struct SettingsView: View {
    var body: some View {
        List {
            Section(header: sectionHeader(title: "Офлайн карты", icon: "map.fill")) {
                HStack(spacing: 12) {
                    Image(systemName: OfflineMapPack.isBundled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(OfflineMapPack.isBundled ? .green : .orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Россия")
                            .font(.body.weight(.medium))
                        Text(OfflineMapPack.isBundled ? "OpenStreetMap, \(OfflineMapPack.bundledSizeText), z0-z10" : "Пакет карты не найден в IPA")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

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
                    Text("v1.2.1").foregroundColor(.gray).font(.caption)
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
    }

    func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.gray)
    }
}
