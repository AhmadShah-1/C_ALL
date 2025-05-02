import UIKit
import Intents

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Request Siri authorization
        INPreferences.requestSiriAuthorization { status in
            switch status {
            case .authorized:
                print("Siri authorization granted")
            case .denied, .restricted:
                print("Siri authorization denied or restricted")
            case .notDetermined:
                print("Siri authorization not determined yet")
            @unknown default:
                print("Unknown Siri authorization status")
            }
        }
        return true
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