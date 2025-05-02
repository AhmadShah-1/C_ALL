//
//  C_ALL_With_Avoidance_PathApp.swift
//  C_ALL_With_Avoidance_Path
//
//  Created by SSW - Design Team  on 1/28/25.
//

import SwiftUI
import ARKit
import CoreLocation
import Intents

@main
struct C_ALL_With_Avoidance_PathApp: App {
    @StateObject private var bluetoothService = BluetoothService()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothService)
                .onAppear {
                    checkForSiriRequest()
                }
        }
    }
    
    /// Checks if there's a pending navigation request from Siri and processes it.
    func checkForSiriRequest() {
        if UserDefaults.standard.bool(forKey: "HasSiriDestination") {
            // First check if we have direct coordinates
            let latitude = UserDefaults.standard.double(forKey: "SiriRequestedLatitude")
            let longitude = UserDefaults.standard.double(forKey: "SiriRequestedLongitude")
            
            if latitude != 0 && longitude != 0 {
                // We have coordinates, use them directly
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                NotificationCenter.default.post(
                    name: Notification.Name("SiriSelectedDestination"),
                    object: nil,
                    userInfo: ["coordinate": coordinate]
                )
            } else if let address = UserDefaults.standard.string(forKey: "SiriRequestedDestination") {
                // We have an address string, need to geocode
                let geocoder = CLGeocoder()
                geocoder.geocodeAddressString(address) { placemarks, error in
                    if let error = error {
                        print("Geocoding error: \(error.localizedDescription)")
                        return
                    }
                    
                    if let location = placemarks?.first?.location {
                        // Post notification with the coordinate
                        NotificationCenter.default.post(
                            name: Notification.Name("SiriSelectedDestination"),
                            object: nil,
                            userInfo: ["coordinate": location.coordinate]
                        )
                    }
                }
            }
            
            // Clear the flag
            UserDefaults.standard.set(false, forKey: "HasSiriDestination")
        }
    }
    
    /// Donates a navigation intent to Siri for future shortcuts
    static func donateNavigationIntent(to destination: CLLocationCoordinate2D, with address: String) {
        let intent = NavigateToLocationIntent()
        
        // Set the destination as a string (updated to match the new string-based parameter)
        intent.destination = address
        
        // Donate the intent to Siri
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("Error donating intent: \(error.localizedDescription)")
            } else {
                print("Successfully donated navigation intent")
            }
        }
    }
}
