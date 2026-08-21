import Foundation
import Combine

/// Общее состояние приложения: выбранная вкладка и сигналы между экранами
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedTab = 0
    @Published var recenterToken = UUID()
    @Published var shouldShowPlanner: Bool

    private init() {
        shouldShowPlanner = RouteStore.shared.activeRoute == nil
    }

    /// Переключиться на карту и сразу отцентрировать на текущей позиции (как в реальном навигаторе)
    func startTrip() {
        shouldShowPlanner = false
        selectedTab = 1
        recenterToken = UUID()
    }

    func resetToPlanner() {
        shouldShowPlanner = true
        selectedTab = 0
    }
}
