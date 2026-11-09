// Overview: Application entry point.
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let applicationWindow = UIWindow(frame: UIScreen.main.bounds)
        applicationWindow.rootViewController = RootViewController()
        applicationWindow.makeKeyAndVisible()

        window = applicationWindow
        return true
    }
}
