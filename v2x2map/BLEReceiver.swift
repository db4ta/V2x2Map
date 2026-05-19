//
//  BLEReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Drahtloser BLE GATT Serial-Receiver für ESP32 V2X-Datenströme (pit711-kompatibel)
//

import Foundation
import CoreBluetooth
import OSLog

public struct BLEDevice: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral
    
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool { lhs.id == rhs.id }
}

public final class BLEReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "BLEReceiver")
    private let lock = NSLock()
    
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private let targetDeviceNamePrefix = "ITS-G5-RX"
    
    // Dedizierte Low-Latency Background Queue zur Entlastung des BLE Handshake-Threads
    private let processingQueue = DispatchQueue(label: "com.v2x2map.ble.processing", qos: .userInteractive)
    
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
        var streamBuffer = Data()
    }
    private let state = ProtectedState()
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onDataReceived }
        set { lock.lock(); defer { lock.unlock() }; state.onDataReceived = newValue }
    }
    
    public var currentDevices: [BLEDevice] {
        lock.lock(); defer { lock.unlock() }; return state.discoveredDevices
    }
    
    public override init() {
        super.init()
    }
    
    public func checkConnectionStatus() -> Bool {
        lock.lock(); defer { lock.unlock() }; return state.connectedPeripheral != nil && state.rxCharacteristic != nil
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
    }
    
    private func scanForESP32() {
        guard let manager = state.centralManager, manager.state == .poweredOn else { return }
        logger.info("Starte fokussierten Hardware-Scan auf C-ITS Service-UUID...")
        
        // Zwingt iOS in den hardwaregefilterten Scan-Modus, um die Fehlerflut im bluetoothd zu stoppen
        manager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    public func connectToDevice(_ device: BLEDevice) {
        lock.lock()
        guard let manager = state.centralManager else { lock.unlock(); return }
        manager.stopScan()
        
        state.connectedPeripheral = device.peripheral
        device.peripheral.delegate = self
        state.logBuffer = "Verbinde mit C-ITS Modem: \(device.name)..."
        let log = state.logBuffer
        lock.unlock()
        
        Task { @MainActor in self.onLogUpdated?(log) }
        
        manager.connect(device.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
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
        state.streamBuffer.removeAll()
        state.logBuffer = "Bluetooth-Verbindung getrennt."
        let devices = state.discoveredDevices
        let log = state.logBuffer
        lock.unlock()
        
        Task { @MainActor in
            self.onDevicesUpdated?(devices)
            self.onLogUpdated?(log)
            self.onConnectionStateChanged?(nil)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            lock.lock(); let listening = state.isListening; lock.unlock()
            if listening { scanForESP32() }
        } else {
            lock.lock(); state.logBuffer = "Fehler: Bluetooth deaktiviert."; let log = state.logBuffer; lock.unlock()
            Task { @MainActor in self.onLogUpdated?(log) }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let rawName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        
        // KORREKTUR: Zuweisung des C-ITS-Präfixes bei unvollständigen Namen im Bluetooth-Buffer
        let name = rawName ?? "ITS-G5-RX (UUID Match)"
        
        lock.lock()
        let device = BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        if let index = state.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            state.discoveredDevices[index] = device
        } else {
            state.discoveredDevices.append(device)
        }
        let devices = state.discoveredDevices
        lock.unlock()
        
        Task { @MainActor in self.onDevicesUpdated?(devices) }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lock.lock()
        state.logBuffer = "Gekoppelt mit \(peripheral.name ?? "Modem"). Verhandle MTU-Größe..."
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
        lock.lock()
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
        state.streamBuffer.removeAll()
        
        let errorDescription: String
        if let nsError = error as NSError? {
            errorDescription = "iOS-Code \(nsError.code): \(nsError.localizedDescription)"
        } else {
            errorDescription = "Regulärer Disconnect vom V2X-Modem."
        }
        
        state.logBuffer = "⚠️ Verbindung unterbrochen: \(errorDescription)"
        let log = state.logBuffer
        let listening = state.isListening
        lock.unlock()
        
        Task { @MainActor in
            self.onLogUpdated?(log)
            self.onConnectionStateChanged?(nil)
        }
        
        if listening {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.scanForESP32()
            }
        }
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
            state.logBuffer = "V2X-Datenkanal aktiv. Abonniere Stream..."
            let log = state.logBuffer
            lock.unlock()
            
            Task { @MainActor in self.onLogUpdated?(log) }
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == rxCharacteristicUUID, let data = characteristic.value, !data.isEmpty else { return }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.lock.lock()
            self.state.streamBuffer.append(data)
            
            while self.state.streamBuffer.count >= 3 {
                // Typensicherer Check des ersten Bytes (Start-Byte 0x02) via Array-Eigenschaft
                if self.state.streamBuffer.first != 0x02 {
                    self.state.streamBuffer.removeFirst()
                    continue
                }
                
                // KORREKTUR: Umwandlung der Bytes 1 und 2 über ein natives UInt8-Array.
                // Löst die 'BinaryInteger'-Konvertierungssackgasse im neuen iOS 26 Compiler fehlerfrei auf.
                let lengthBytes = [UInt8](self.state.streamBuffer.subdata(in: 1..<3))
                let length = (Int(lengthBytes[0]) << 8) | Int(lengthBytes[1])
                
                guard self.state.streamBuffer.count >= (3 + length) else {
                    break
                }
                
                let payload = self.state.streamBuffer.subdata(in: 3..<(3 + length))
                self.state.streamBuffer.removeSubrange(0..<(3 + length))
                
                let callback = self.state.onDataReceived
                self.lock.unlock()
                
                if !payload.isEmpty {
                    callback?(payload)
                }
                
                self.lock.lock()
            }
            self.lock.unlock()
        }
    }
}
