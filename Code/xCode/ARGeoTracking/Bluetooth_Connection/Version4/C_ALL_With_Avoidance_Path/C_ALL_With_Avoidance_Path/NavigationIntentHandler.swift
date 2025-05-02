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
            
            // Geocode the address string to get coordinates
            let geocoder = CLGeocoder()
            geocoder.geocodeAddressString(destinationString) { placemarks, error in
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    // Send failure response
                    let response = NavigateToLocationIntentResponse(code: .failure, userActivity: nil)
                    completion(response)
                    return
                }
                
                if let location = placemarks?.first?.location {
                    // Store coordinates for direct use
                    UserDefaults.standard.set(location.coordinate.latitude, forKey: "SiriRequestedLatitude")
                    UserDefaults.standard.set(location.coordinate.longitude, forKey: "SiriRequestedLongitude")
                    
                    // Post a notification about the new destination
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("SiriSelectedDestination"),
                            object: nil,
                            userInfo: ["coordinate": location.coordinate]
                        )
                    }
                    
                    // Send success response
                    let response = NavigateToLocationIntentResponse(code: .success, userActivity: nil)
                    completion(response)
                } else {
                    // Send failure response if no location found
                    let response = NavigateToLocationIntentResponse(code: .failure, userActivity: nil)
                    completion(response)
                }
            }
        } else {
            // Send failure response if no destination provided
            let response = NavigateToLocationIntentResponse(code: .failure, userActivity: nil)
            completion(response)
        }
    }
    
    // Called to resolve the destination parameter
    func resolveDestination(for intent: NavigateToLocationIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        if let destination = intent.destination, !destination.isEmpty {
            completion(.success(with: destination))
        } else {
            // Ask for a destination if none provided
            completion(.needsValue())
        }
    }
    
    // Called to confirm the intent before handling
    func confirm(intent: NavigateToLocationIntent, completion: @escaping (NavigateToLocationIntentResponse) -> Void) {
        if let destination = intent.destination, !destination.isEmpty {
            // Do a quick check to see if the destination can be geocoded
            let geocoder = CLGeocoder()
            geocoder.geocodeAddressString(destination) { placemarks, error in
                if error != nil || placemarks?.first == nil {
                    // Can't geocode the destination
                    completion(NavigateToLocationIntentResponse(code: .failure, userActivity: nil))
                } else {
                    // Destination can be geocoded
                    completion(NavigateToLocationIntentResponse(code: .ready, userActivity: nil))
                }
            }
        } else {
            completion(NavigateToLocationIntentResponse(code: .failure, userActivity: nil))
        }
    }
} 