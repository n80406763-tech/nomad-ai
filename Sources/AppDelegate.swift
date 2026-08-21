import UIKit
import CoreLocation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    /// Система будит приложение, когда фоновая загрузка (RouteDownloadService) завершена
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        RouteDownloadService.shared.handleBackgroundEvents(identifier: identifier, completionHandler: completionHandler)
    }
}
