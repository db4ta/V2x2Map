//
//  BLEReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Drahtloser BLE GATT Serial-Receiver für ESP32 V2X-Datenströme
//

import Foundation
import CoreBluetooth
import OSLog

public struct BLEDevice: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

public final class BLEReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "BLEReceiver")
    private let lock = NSLock()
    
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    // KORREKTUR: Suchpräfix auf standardisierten C-ITS Gerätenamen umgestellt
    private let targetDeviceNamePrefix = "ITS-G5-RX"
    
    @MainActor public var onDevicesUpdated: (([BLEDevice]) -> Void)?
    @MainActor public var onLogUpdated: ((String) -> Void)?
    @MainActor public var onConnectionStateChanged: ((String?) -> Void)?
    
    private final class ProtectedState {
        var centralManager: CBCentralManager?
        var connectedPeripheral: CBPeripheral?
        var rxCharacteristic: CBCharacteristic?
        var isListening = false
        var onDataReceived: (@Sendable (Data) -> Void)?
        var discoveredDevices: [BLEDevice] = []
        var logBuffer: String = "Inaktiv. Warte auf Aktivierung..."
    }
    private let state = ProtectedState()
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onDataReceived }
        set { lock.lock(); defer { lock.unlock() }; state.onDataReceived = newValue }
    }
    
    public var currentDevices: [BLEDevice] {
        lock.lock()
        defer { lock.unlock() }
        return state.discoveredDevices
    }
    
    public override init() {
        super.init()
    }
    
    public func checkConnectionStatus() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.connectedPeripheral != nil && state.rxCharacteristic != nil
    }
    
    public func startListening() {
        lock.lock()
        if state.isListening { lock.unlock(); return }
        state.isListening = true
        state.discoveredDevices.removeAll()
        state.logBuffer = "Suche nach C-ITS Sendern (\(targetDeviceNamePrefix)) läuft..."
        
        let devices = state.discoveredDevices
        let log = state.logBuffer
        lock.unlock()
        
        Task { @MainActor in
            self.onDevicesUpdated?(devices)
            self.onLogUpdated?(log)
        }
        
        if state.centralManager == nil {
            state.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.v2x2map.ble.central", qos: .userInteractive))
        } else {
            scanForESP32()
        }
        logger.info("Bluetooth LE Scan-Modus aktiviert.")
    }
    
    private func scanForESP32() {
        guard let manager = state.centralManager, manager.state == .poweredOn else { return }
        logger.info("Suche nach V2X-Sendern über ungefilterten BLE-Scan...")
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    public func connectToDevice(_ device: BLEDevice) {
        lock.lock()
        guard let manager = state.centralManager else { lock.unlock(); return }
        manager.stopScan()
        
        state.connectedPeripheral = device.peripheral
        device.peripheral.delegate = self
        state.logBuffer = "Verbinde mit C-ITS Hardware: \(device.name)..."
        let log = state.logBuffer
        lock.unlock()
        
        Task { @MainActor in
            self.onLogUpdated?(log)
        }
        
        manager.connect(device.peripheral, options: nil)
    }
    
    public func stopListening() {
        lock.lock()
        state.isListening = false
        state.centralManager?.stopScan()
        
        if let peripheral = state.connectedPeripheral {
            state.centralManager?.cancelPeripheralConnection(peripheral)
        }
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
        state.discoveredDevices.removeAll()
        state.logBuffer = "Bluetooth-Verbindung manuell getrennt."
        
        let devices = state.discoveredDevices
        let log = state.logBuffer
        lock.unlock()
        
        Task { @MainActor in
            self.onDevicesUpdated?(devices)
            self.onLogUpdated?(log)
            self.onConnectionStateChanged?(nil)
        }
        logger.info("Bluetooth-Verbindung getrennt.")
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            lock.lock()
            let listening = state.isListening
            lock.unlock()
            if listening { scanForESP32() }
        } else {
            logger.warning("Bluetooth am iPhone ist ausgeschaltet oder nicht autorisiert.")
            lock.lock()
            state.logBuffer = "Fehler: Bluetooth am iPhone ist deaktiviert."
            let log = state.logBuffer
            lock.unlock()
            Task { @MainActor in self.onLogUpdated?(log) }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unbekanntes V2X-Gerät"
        
        // Intelligentisiertes Matching auf Namen oder Service-UUIDs
        let hasMatchingName = name.hasPrefix(targetDeviceNamePrefix)
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasMatchingService = advertisedServices.contains(serviceUUID)
        
        guard hasMatchingName || hasMatchingService else { return }
        
        lock.lock()
        let device = BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        if !state.discoveredDevices.contains(where: { $0.id == device.id }) {
            state.discoveredDevices.append(device)
            state.logBuffer = "C-ITS Modem entdeckt: \(name) (\(RSSI) dBm)"
            let devices = state.discoveredDevices
            let log = state.logBuffer
            lock.unlock()
            
            Task { @MainActor in
                self.onDevicesUpdated?(devices)
                self.onLogUpdated?(log)
            }
        } else {
            lock.unlock()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lock.lock()
        state.logBuffer = "Gekoppelt mit \(peripheral.name ?? "V2X-Modem"). Handle MTU-Größe aus..."
        let log = state.logBuffer
        lock.unlock()
        
        let optimalMTU = peripheral.maximumWriteValueLength(for: .withoutResponse)
        
        Task { @MainActor in
            self.onLogUpdated?("\(log) (MTU: \(optimalMTU) Bytes). Suche C-ITS Services...")
            self.onConnectionStateChanged?(peripheral.name ?? "ITS-G5-RX")
        }
        peripheral.discoverServices([serviceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.warning("Drahtlose Verbindung zum C-ITS Modem abgebrochen.")
        lock.lock()
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
        state.logBuffer = "Verbindung verloren. Starte automatischen Umgebungsscan..."
        let log = state.logBuffer
        let listening = state.isListening
        lock.unlock()
        
        Task { @MainActor in
            self.onLogUpdated?(log)
            self.onConnectionStateChanged?(nil)
        }
        if listening { scanForESP32() }
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([rxCharacteristicUUID], for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == rxCharacteristicUUID {
            lock.lock()
            state.rxCharacteristic = characteristic
            state.logBuffer = "C-ITS Live-Kanal abonniert! Warte auf ASN.1 Pakete..."
            let log = state.logBuffer
            lock.unlock()
            
            Task { @MainActor in
                self.onLogUpdated?(log)
            }
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == rxCharacteristicUUID, let data = characteristic.value, !data.isEmpty else { return }
        lock.lock()
        let callback = state.onDataReceived
        lock.unlock()
        callback?(data)
    }
}
