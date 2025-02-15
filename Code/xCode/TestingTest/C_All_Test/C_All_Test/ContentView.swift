//
//  ContentView.swift
//  C_All_Test
//
//  Created by SSW - Design Team  on 2/13/25.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var numberToSend: String = ""
    @State private var showDeviceSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status and Control
                HStack {
                    Image(systemName: bluetoothManager.isConnected ? "bluetooth.connected" : "bluetooth")
                        .foregroundColor(bluetoothManager.isConnected ? .green : .blue)
                        .imageScale(.large)
                    
                    Text(bluetoothManager.isConnected ? 
                         "Connected to: \(bluetoothManager.connectedDeviceName)" : 
                         "Not Connected")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // Connect/Disconnect Button
                Button(action: {
                    if bluetoothManager.isConnected {
                        bluetoothManager.disconnect()
                    } else {
                        showDeviceSheet = true
                    }
                }) {
                    HStack {
                        Image(systemName: bluetoothManager.isConnected ? "xmark.circle.fill" : "plus.circle.fill")
                        Text(bluetoothManager.isConnected ? "Disconnect" : "Connect to Device")
                    }
                    .foregroundColor(bluetoothManager.isConnected ? .red : .blue)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                
                Divider()
                    .padding(.vertical)
                
                // Number Input Section
                VStack(spacing: 15) {
                    TextField("Enter number to send", text: $numberToSend)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .padding(.horizontal)
                    
                    Button(action: {
                        if let number = Int(numberToSend) {
                            bluetoothManager.sendNumber(number)
                            numberToSend = ""
                        }
                    }) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send Number")
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(bluetoothManager.isConnected ? Color.blue : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!bluetoothManager.isConnected)
                }
            }
            .padding()
            .navigationTitle("Bluetooth Control")
            .sheet(isPresented: $showDeviceSheet) {
                DeviceSelectionView(bluetoothManager: bluetoothManager, isPresented: $showDeviceSheet)
            }
        }
    }
}

struct DeviceSelectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(bluetoothManager.discoveredPeripherals, id: \.identifier) { peripheral in
                    Button(action: {
                        bluetoothManager.connectToPeripheral(peripheral)
                        isPresented = false
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(peripheral.name ?? "Unknown Device")
                                    .font(.headline)
                                Text(peripheral.identifier.uuidString)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Available Devices")
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button(action: {
                    bluetoothManager.startScanning()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
