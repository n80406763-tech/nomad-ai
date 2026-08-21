import UIKit
import CoreLocation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Отключаем телеметрию MapLibre, чтобы избежать запроса к Local Network и крашей на старте
        UserDefaults.standard.set(false, forKey: "MGLMapboxMetricsEnabledSettingShownInApp")
        UserDefaults.standard.set(false, forKey: "MGLMapboxMetricsEnabled")
        UserDefaults.standard.set(false, forKey: "MGLIdeogramFontFamilyName")
        return true
    }
}
