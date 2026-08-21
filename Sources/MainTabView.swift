import SwiftUI

struct MainTabView: View {
    var body: some View {
        MapScreenView()
            .ignoresSafeArea()
            .onAppear {
                UITabBar.appearance().isHidden = true
                UITabBar.appearance().backgroundImage = UIImage()
                UITabBar.appearance().shadowImage = UIImage()
            }
    }
}
