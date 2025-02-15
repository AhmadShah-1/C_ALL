import Foundation
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var bluetoothState: String = "Unknown"
    @Published var connectedDeviceName: String = "Unknown"
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var serialCharacteristic: CBCharacteristic?
    
    // New definitions:
    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    private let characteristicUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef1")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothState = "Powered On"
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
            retrieveConnectedPeripherals()
            if connectedPeripheral == nil {
                debugPrint("[DEBUG] No peripheral connected. Initiating scan.")
                startScanning()
            }
        case .poweredOff:
            bluetoothState = "Powered Off"
            discoveredPeripherals.removeAll()
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
        case .resetting:
            bluetoothState = "Resetting"
            discoveredPeripherals.removeAll()
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
        case .unauthorized:
            bluetoothState = "Unauthorized"
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
        case .unsupported:
            bluetoothState = "Unsupported"
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
        case .unknown:
            bluetoothState = "Unknown"
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
        @unknown default:
            bluetoothState = "Unknown"
            debugPrint("[DEBUG] Bluetooth state: \(bluetoothState)")
        }
    }
    
    func retrieveConnectedPeripherals() {
        debugPrint("[DEBUG] Checking for already connected peripherals...")
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if connected.count > 0 {
            let first = connected[0]
            debugPrint("[DEBUG] Using connected peripheral: \(first.name ?? "Unknown")")
            connectedPeripheral = first
            if !discoveredPeripherals.contains(first) {
                discoveredPeripherals.append(first)
            }
            first.delegate = self
            first.discoverServices([serviceUUID])
            isConnected = true
            connectedDeviceName = first.name ?? "Unknown"
        } else {
            // Convert stored strings back to UUIDs
            let storedIdentifiers = UserDefaults.standard.stringArray(forKey: "LastConnectedPeripheralIdentifiers") ?? []
            let uuids = storedIdentifiers.compactMap { UUID(uuidString: $0) }
            let paired = centralManager.retrievePeripherals(withIdentifiers: uuids)
            
            if paired.count > 0 {
                let first = paired[0]
                debugPrint("[DEBUG] Using paired peripheral: \(first.name ?? "Unknown")")
                connectedPeripheral = first
                if !discoveredPeripherals.contains(first) {
                    discoveredPeripherals.append(first)
                }
                first.delegate = self
                first.discoverServices([serviceUUID])
                isConnected = true
                connectedDeviceName = first.name ?? "Unknown"
            } else {
                debugPrint("[DEBUG] No connected or paired peripherals found.")
            }
        }
    }
    
    func startScanning() {
        debugPrint("[DEBUG] Initiating scan for peripherals...")
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func stopScanning() {
        centralManager.stopScan()
        debugPrint("[DEBUG] Scan stopped")
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            if let name = peripheral.name {
                discoveredPeripherals.append(peripheral)
                debugPrint("[DEBUG] Discovered peripheral - Name: \(name), Identifier: \(peripheral.identifier), RSSI: \(RSSI)")
            }
        }
    }
    
    func connectToPeripheral(_ peripheral: CBPeripheral) {
        debugPrint("[DEBUG] Connecting to peripheral: \(peripheral.name ?? "Unknown"), Identifier: \(peripheral.identifier)")
        
        // Convert UUID to string before storing
        let identifierString = peripheral.identifier.uuidString
        var storedIdentifiers = UserDefaults.standard.stringArray(forKey: "LastConnectedPeripheralIdentifiers") ?? []
        if !storedIdentifiers.contains(identifierString) {
            storedIdentifiers.append(identifierString)
            UserDefaults.standard.set(storedIdentifiers, forKey: "LastConnectedPeripheralIdentifiers")
        }
        
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        peripheral.delegate = self
        connectedPeripheral = peripheral
        connectedDeviceName = peripheral.name ?? "Unknown"
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        debugPrint("[DEBUG] Connected to peripheral: \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        debugPrint("[DEBUG] Discovering services...")
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        debugPrint("[DEBUG] Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        isConnected = false
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        debugPrint("[DEBUG] Disconnected from peripheral: \(error?.localizedDescription ?? "No error")")
        isConnected = false
        connectedDeviceName = "Unknown"
        if let peripheral = connectedPeripheral {
            debugPrint("[DEBUG] Reconnecting to peripheral: \(peripheral.name ?? "Unknown")")
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            debugPrint("[DEBUG] Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            debugPrint("[DEBUG] No services found")
            return
        }
        
        for service in services {
            debugPrint("[DEBUG] Discovered service: \(service.uuid)")
            if service.uuid == serviceUUID {
                debugPrint("[DEBUG] Found target service, discovering characteristics...")
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            debugPrint("[DEBUG] Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            debugPrint("[DEBUG] No characteristics found")
            return
        }
        
        for characteristic in characteristics {
            debugPrint("[DEBUG] Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == characteristicUUID {
                serialCharacteristic = characteristic
                debugPrint("[DEBUG] Found target characteristic with properties: \(characteristic.properties.rawValue)")
                
                // Enable notifications if the characteristic supports it
                if characteristic.properties.contains(.notify) {
                    debugPrint("[DEBUG] Enabling notifications for characteristic")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    func sendNumber(_ number: Int) {
        guard let peripheral = connectedPeripheral, let characteristic = serialCharacteristic else {
            debugPrint("[DEBUG] Cannot send number: No connection or characteristic available")
            return
        }
        
        let numberString = String(number)
        guard let data = numberString.data(using: .utf8) else {
            debugPrint("[DEBUG] Failed to convert number to data")
            return
        }
        
        debugPrint("[DEBUG] Sending number: \(number)")
        debugPrint("[DEBUG] Characteristic properties: \(characteristic.properties.rawValue)")
        
        // Always use write with response since that's what our characteristic supports
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        debugPrint("[DEBUG] Sent number using write with response")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            debugPrint("[DEBUG] Error writing value: \(error.localizedDescription)")
        } else {
            debugPrint("[DEBUG] Successfully wrote value to characteristic")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            debugPrint("[DEBUG] Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        debugPrint("[DEBUG] Notification state updated for characteristic: \(characteristic.uuid)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            debugPrint("[DEBUG] Error receiving value: \(error.localizedDescription)")
            return
        }
        
        if let value = characteristic.value, let str = String(data: value, encoding: .utf8) {
            debugPrint("[DEBUG] Received value: \(str)")
        }
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            debugPrint("[DEBUG] Manually disconnecting from peripheral: \(peripheral.name ?? "Unknown")")
            centralManager.cancelPeripheralConnection(peripheral)
            connectedPeripheral = nil
            serialCharacteristic = nil
            isConnected = false
            connectedDeviceName = "Unknown"
        }
    }
} 