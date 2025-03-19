//
//  C_ALL_Avoidance_Path_BluetoothApp.swift
//  C_ALL_Avoidance_Path_Bluetooth
//
//  Created by SSW - Design Team  on 2/13/25.
//

import SwiftUI
import ARKit
import CoreBluetooth

@main
struct C_ALL_Avoidance_Path_BluetoothApp: App {
    @StateObject private var bluetoothService = BluetoothService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothService)
        }
    }
}
