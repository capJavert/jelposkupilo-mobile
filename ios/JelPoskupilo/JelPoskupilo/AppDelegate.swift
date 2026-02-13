import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let incomingURL = userActivity.webpageURL,
              let host = incomingURL.host?.lowercased(),
              host == "jelposkupilo.eu" else {
            return false
        }

        guard let baseString = Bundle.main.object(forInfoDictionaryKey: "BaseURL") as? String,
              let baseURL = URL(string: baseString),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return false
        }

        components.path = incomingURL.path
        components.query = incomingURL.query
        components.fragment = incomingURL.fragment

        guard let targetURL = components.url else {
            return false
        }

        if let webVC = window?.rootViewController as? WebViewController {
            webVC.loadURL(targetURL)
        }

        return true
    }

}
