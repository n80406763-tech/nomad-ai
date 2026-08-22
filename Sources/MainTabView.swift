import SwiftUI

struct MainTabView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Group {
            if appState.shouldShowPlanner {
                TripPlannerView()
            } else {
                MapScreenView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            UITabBar.appearance().isHidden = true
            UITabBar.appearance().backgroundImage = UIImage()
            UITabBar.appearance().shadowImage = UIImage()
        }
    }
}
