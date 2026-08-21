import Foundation
import Combine

/// Общее состояние приложения: выбранная вкладка и сигналы между экранами
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedTab = 0
    @Published var recenterToken = UUID()

    /// Переключиться на карту и сразу отцентрировать на текущей позиции (как в реальном навигаторе)
    func startTrip() {
        selectedTab = 1 // вкладка "Карта"
        recenterToken = UUID()
    }
}
