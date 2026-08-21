import SwiftUI

struct MainTabView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            TripPlannerView()
                .tabItem {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    Text("Поездка")
                }
                .tag(0)

            NavigationView { MapScreenView() }
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Карта")
                }
                .tag(1)

            NavigationView { RoutesListView() }
                .tabItem {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("Маршруты")
                }
                .tag(2)

            NavigationView { PoiSearchView() }
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Поиск")
                }
                .tag(3)

            NavigationView { AssistantView() }
                .tabItem {
                    Image(systemName: "waveform.and.mic")
                    Text("Ассистент")
                }
                .tag(4)

            NavigationView { SettingsView() }
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Настройки")
                }
                .tag(5)
        }
        .navigationViewStyle(.stack)
        .accentColor(.cyan)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
