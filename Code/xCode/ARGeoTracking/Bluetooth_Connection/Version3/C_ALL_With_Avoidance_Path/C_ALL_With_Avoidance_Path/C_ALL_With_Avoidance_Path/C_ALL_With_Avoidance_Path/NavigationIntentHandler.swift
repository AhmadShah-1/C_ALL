import Intents
import CoreLocation
import IntentsUI

// Note: NavigateToLocationIntent and related classes will be auto-generated
// from NavigationIntents.intentdefinition

class NavigationIntentHandler: NSObject, NavigateToLocationIntentHandling {
    func handle(intent: NavigateToLocationIntent, completion: @escaping (NavigateToLocationIntentResponse) -> Void) {
        // Store the destination string in UserDefaults
        if let destinationString = intent.destination {
            UserDefaults.standard.set(destinationString, forKey: "SiriRequestedDestination")
            UserDefaults.standard.set(true, forKey: "HasSiriDestination")
            
            print("Destination from Siri: \(destinationString)")
            
            // You can optionally convert the string to coordinates here if needed
            // But for now we're just storing the string destination
        }
        
        // Send success response
        let response = NavigateToLocationIntentResponse(code: .ready, userActivity: nil)
        completion(response)
    }
    
    // Called to resolve the destination parameter
    func resolveDestination(for intent: NavigateToLocationIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        if let destination = intent.destination, !destination.isEmpty {
            completion(.success(with: destination))
        } else {
            completion(.needsValue())
        }
    }
    
    // Called to confirm the intent before handling
    func confirm(intent: NavigateToLocationIntent, completion: @escaping (NavigateToLocationIntentResponse) -> Void) {
        if let destination = intent.destination, !destination.isEmpty {
            completion(NavigateToLocationIntentResponse(code: .ready, userActivity: nil))
        } else {
            completion(NavigateToLocationIntentResponse(code: .failure, userActivity: nil))
        }
    }
} 