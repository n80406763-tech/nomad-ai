import SwiftUI
import CoreLocation

struct GPSDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locationManager = LocationManager.shared

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Состояние")) {
                    diagnosticRow("Службы геолокации", CLLocationManager.locationServicesEnabled() ? "включены" : "выключены")
                    diagnosticRow("Разрешение", locationManager.authorizationDescription)
                    diagnosticRow("Точность iPhone", locationManager.accuracyAuthorizationDescription)
                    diagnosticRow("Последний сигнал", locationManager.latestLocationDescription)
                    diagnosticRow("Последняя ошибка", locationManager.lastErrorMessage ?? "нет")
                }

                Section {
                    Button(action: retryLocation) {
                        Label(actionTitle, systemImage: actionIcon)
                    }
                    if !locationManager.diagnosticEvents.isEmpty {
                        Button("Очистить журнал", role: .destructive) {
                            locationManager.clearDiagnostics()
                        }
                    }
                }

                Section(header: Text("Журнал Core Location")) {
                    if locationManager.diagnosticEvents.isEmpty {
                        Text("Ожидаем события GPS…")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(locationManager.diagnosticEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.message)
                                    .font(.footnote)
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Диагностика GPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
        }
    }

    private var actionTitle: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Открыть настройки GPS"
        default:
            return "Повторить проверку GPS"
        }
    }

    private var actionIcon: String {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "gearshape.fill"
        default:
            return "location.fill"
        }
    }

    private func retryLocation() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            locationManager.openLocationSettings()
        default:
            locationManager.requestPermission()
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}