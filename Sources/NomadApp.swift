import SwiftUI

@main
struct NomadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                MainTabView()
                DiagnosticsBanner()
            }
            .preferredColorScheme(.dark)
        }
    }
}
