//
//  CreatingLidarModelApp.swift
//  CreatingLidarModel
//
//  Created by SSW - Design Team  on 11/14/24.
//

import SwiftUI
import SwiftData
import ARKit

@main
struct CreatingLidarModelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Maybe Remove
    /*
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
     
     

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
    */
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Perform any necessary setup or initialization here
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {

            print("does not support AR")
        }
        return true
    }
    
    // Include other AppDelegate methods as needed
}
