import Foundation
import CoreBluetooth

class BluetoothService: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var connectionStatus: String = "Disconnected"
    
    private var centralManager: CBCentralManager!
    private var targetCharacteristic: CBCharacteristic?
    private var avoidanceCharacteristic: CBCharacteristic?
    
    // Service and characteristic UUIDs - match these with your Raspberry Pi
    private let compassServiceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    private let targetCharacteristicUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef1")
    private let avoidanceCharacteristicUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef2")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        discoveredPeripherals.removeAll()
        // Scan for all devices instead of filtering by service
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        print("[DEBUG] Started scanning for peripherals...")
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
        print("[DEBUG] Stopped scanning")
    }
    
    func connect(to peripheral: CBPeripheral) {
        print("[DEBUG] Connecting to peripheral: \(peripheral.name ?? "Unknown")")
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        peripheral.delegate = self
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            print("[DEBUG] Disconnecting from peripheral: \(peripheral.name ?? "Unknown")")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func sendTargetAngle(_ angle: Double) {
        guard let peripheral = connectedPeripheral,
              let characteristic = targetCharacteristic else {
            print("[DEBUG] Cannot send target angle: No connected peripheral or characteristic")
            return
        }
        
        let angleInt = Int(round(angle))
        let angleString = String(angleInt)
        guard let data = angleString.data(using: .utf8) else { return }
        
        print("[DEBUG] Sending target angle: \(angleInt)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    func sendAvoidanceAngle(_ angle: Double) {
        guard let peripheral = connectedPeripheral,
              let characteristic = avoidanceCharacteristic else {
            print("[DEBUG] Cannot send avoidance angle: No connected peripheral or characteristic")
            return
        }
        
        let angleInt = Int(round(angle))
        let angleString = String(angleInt)
        guard let data = angleString.data(using: .utf8) else { return }
        
        print("[DEBUG] Sending avoidance angle: \(angleInt)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[DEBUG] Bluetooth is powered on")
            // Start scanning automatically when Bluetooth is powered on
            startScanning()
        case .poweredOff:
            print("[DEBUG] Bluetooth is powered off")
            connectionStatus = "Bluetooth is powered off"
        case .unsupported:
            print("[DEBUG] Bluetooth is unsupported")
            connectionStatus = "Bluetooth is unsupported"
        default:
            print("[DEBUG] Bluetooth state unknown")
            connectionStatus = "Bluetooth state unknown"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            if let name = peripheral.name {
                print("[DEBUG] Discovered peripheral - Name: \(name), RSSI: \(RSSI)")
                discoveredPeripherals.append(peripheral)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[DEBUG] Connected to peripheral: \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral
        connectionStatus = "Connected to \(peripheral.name ?? "Unknown Device")"
        peripheral.discoverServices([compassServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[DEBUG] Disconnected from peripheral: \(error?.localizedDescription ?? "No error")")
        connectedPeripheral = nil
        targetCharacteristic = nil
        avoidanceCharacteristic = nil
        connectionStatus = "Disconnected"
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[DEBUG] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = "Failed to connect"
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[DEBUG] Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("[DEBUG] No services found")
            return
        }
        
        for service in services {
            print("[DEBUG] Discovered service: \(service.uuid)")
            if service.uuid == compassServiceUUID {
                print("[DEBUG] Found target service, discovering characteristics...")
                peripheral.discoverCharacteristics([targetCharacteristicUUID, avoidanceCharacteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("[DEBUG] Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("[DEBUG] No characteristics found")
            return
        }
        
        for characteristic in characteristics {
            print("[DEBUG] Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == targetCharacteristicUUID {
                self.targetCharacteristic = characteristic
                print("[DEBUG] Found target compass characteristic")
            } else if characteristic.uuid == avoidanceCharacteristicUUID {
                self.avoidanceCharacteristic = characteristic
                print("[DEBUG] Found avoidance compass characteristic")
            }
        }
        
        if targetCharacteristic != nil && avoidanceCharacteristic != nil {
            connectionStatus = "Ready to send compass data"
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[DEBUG] Error writing value: \(error.localizedDescription)")
        } else {
            print("[DEBUG] Successfully wrote value to characteristic")
        }
    }
} 