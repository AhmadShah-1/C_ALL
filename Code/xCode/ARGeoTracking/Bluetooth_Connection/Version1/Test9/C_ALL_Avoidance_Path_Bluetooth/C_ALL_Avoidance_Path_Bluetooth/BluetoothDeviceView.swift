import SwiftUI

struct BluetoothDeviceView: View {
    @EnvironmentObject private var bluetoothService: BluetoothService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Status")) {
                    Text(bluetoothService.connectionStatus)
                        .foregroundColor(statusColor)
                }
                
                Section(header: Text("Available Devices")) {
                    if bluetoothService.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    
                    ForEach(bluetoothService.discoveredPeripherals, id: \.identifier) { peripheral in
                        Button(action: {
                            bluetoothService.connect(to: peripheral)
                            dismiss()
                        }) {
                            HStack {
                                Text(peripheral.name ?? "Unknown Device")
                                Spacer()
                                if bluetoothService.connectedPeripheral?.identifier == peripheral.identifier {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bluetooth Devices")
            .navigationBarItems(
                trailing: Button(action: {
                    if bluetoothService.isScanning {
                        bluetoothService.stopScanning()
                    } else {
                        bluetoothService.startScanning()
                    }
                }) {
                    Text(bluetoothService.isScanning ? "Stop" : "Scan")
                }
            )
        }
        .onAppear {
            bluetoothService.startScanning()
        }
        .onDisappear {
            bluetoothService.stopScanning()
        }
    }
    
    private var statusColor: Color {
        switch bluetoothService.connectionStatus {
        case "Connected to Unknown Device", "Ready to send compass data":
            return .green
        case "Disconnected":
            return .red
        default:
            return .orange
        }
    }
}

struct BluetoothDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        BluetoothDeviceView()
            .environmentObject(BluetoothService())
    }
} 