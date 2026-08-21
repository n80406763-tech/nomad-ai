import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView { MapScreenView() }
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Карта")
                }
                .tag(0)

            NavigationView { RoutesListView() }
                .tabItem {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("Маршруты")
                }
                .tag(1)

            NavigationView { PoiSearchView() }
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Поиск")
                }
                .tag(2)

            NavigationView { AssistantView() }
                .tabItem {
                    Image(systemName: "waveform.and.mic")
                    Text("Ассистент")
                }
                .tag(3)

            NavigationView { SettingsView() }
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Настройки")
                }
                .tag(4)
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
