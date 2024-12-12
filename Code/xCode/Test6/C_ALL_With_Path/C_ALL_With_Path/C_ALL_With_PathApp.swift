import SwiftUI
import ARKit

@main
struct C_ALL_With_PathApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !ARWorldTrackingConfiguration.isSupported {
            print("ARWorldTrackingConfiguration is not supported on this device.")
        }
        return true
    }
}
