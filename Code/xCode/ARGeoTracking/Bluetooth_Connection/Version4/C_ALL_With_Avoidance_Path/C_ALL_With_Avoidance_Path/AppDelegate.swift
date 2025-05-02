import UIKit
import Intents

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Request Siri permissions
        requestSiriPermission()
        return true
    }
    
    private func requestSiriPermission() {
        INPreferences.requestSiriAuthorization { status in
            switch status {
            case .authorized:
                print("Siri permission granted")
            case .denied, .restricted, .notDetermined:
                print("Siri permission not granted: \(status.rawValue)")
            @unknown default:
                print("Unknown Siri authorization status")
            }
        }
    }
    
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        // Handle incoming intents
        if let navigationIntent = intent as? NavigateToLocationIntent {
            let handler = NavigationIntentHandler()
            handler.handle(intent: navigationIntent) { response in
                completionHandler(response)
            }
        }
    }
} 