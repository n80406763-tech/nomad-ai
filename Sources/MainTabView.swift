import SwiftUI

struct MainTabView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Group {
            if appState.shouldShowPlanner {
                TripPlannerView()
            } else {
                MapScreenView()
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            UITabBar.appearance().isHidden = true
            UITabBar.appearance().backgroundImage = UIImage()
            UITabBar.appearance().shadowImage = UIImage()
        }
    }
}
