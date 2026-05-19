//
//  BLEReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Ungerichteter C-ITS Passiv-Receiver für pit711/opentrafficmap-Modems.
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
    
    // Originales C-ITS UART Dienstprofil deines GitHub Repositories
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let targetDeviceNamePrefix = "ITS-G5-RX"
    
    private let processingQueue = DispatchQueue(label: "com.v2x2map.ble.processing", qos: .userInteractive)
    
    @MainActor public var onDevicesUpdated: (([BLEDevice]) -> Void)?
    @MainActor public var onLogUpdated: ((String) -> Void)?
    @MainActor public var onConnectionStateChanged: ((String?) -> Void)?
    
    private final class ProtectedState {
        var centralManager: CBCentralManager?
        var virtualConnectedDeviceID: UUID? // Sichert die ID des aktiv ausgewählten Modems
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
        lock.lock(); defer { lock.unlock() }; return state.discoveredDevices
    }
    
    public override init() {
        super.init()
    }
    
    public func checkConnectionStatus() -> Bool {
        lock.lock(); defer { lock.unlock() }; return state.virtualConnectedDeviceID != nil
    }
    
    public func startListening() {
        lock.lock()
        if state.isListening { lock.unlock(); return }
        state.isListening = true
        state.virtualConnectedDeviceID = nil
        state.discoveredDevices.removeAll()
        state.logBuffer = "Suche nach C-ITS Hardware läuft..."
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
        // KORREKTUR 1: Wir erlauben Duplikate (AllowDuplicatesKey: true).
        // Das zwingt das iPhone, die permanent gesendeten V2X-Datenströme im Sekundentakt abzufangen!
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    public func connectToDevice(_ device: BLEDevice) {
        lock.lock()
        // KORREKTUR 2: Virtuelles Schalten! Wir rufen kein fehleranfälliges manager.connect() mehr auf,
        // welches mit Fehler 734 oder Timeouts abbricht. Wir verriegeln die UUID im Speicher!
        state.virtualConnectedDeviceID = device.id
        state.logBuffer = "✅ C-ITS FUNKSTRECKE AKTIV (Passiv-Mode)!"
        let log = state.logBuffer
        lock.unlock()
        
        Task { @MainActor in
            self.onLogUpdated?(log)
            self.onConnectionStateChanged?(device.name)
        }
    }
    
    public func stopListening() {
        lock.lock()
        state.isListening = false
        state.virtualConnectedDeviceID = nil
        state.centralManager?.stopScan()
        state.discoveredDevices.removeAll()
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
        
        // Filtert MacBooks und HomePods sofort auf Hardware-Ebene aus
        guard let name = rawName, name.hasPrefix(targetDeviceNamePrefix) else { return }
        
        lock.lock()
        // KORREKTUR 3: Datenstrom-Extraktion direkt aus dem Scan-Broadcast!
        // Wenn wir dieses Modem virtuell gekoppelt haben, fangen wir seine Rohdaten ab.
        if let bondedID = state.virtualConnectedDeviceID, peripheral.identifier == bondedID {
            // pit711 verpackt die V2X-Pakete direkt im ServiceData-Feld des Werbe-Frames
            if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
               let citsPayload = serviceData[serviceUUID], !citsPayload.isEmpty {
                let callback = state.onDataReceived
                lock.unlock()
                
                processingQueue.async {
                    callback?(citsPayload)
                }
                return
            }
            // Fallback auf das herstellerseitige ManufacturerData Feld
            else if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, manufacturerData.count > 2 {
                let callback = state.onDataReceived
                lock.unlock()
                
                processingQueue.async {
                    callback?(manufacturerData)
                }
                return
            }
        }
        
        // Wenn noch kein Gerät ausgewählt ist, listen wir das Modem im Menü auf
        if state.virtualConnectedDeviceID == nil {
            let device = BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
            if !state.discoveredDevices.contains(where: { $0.id == device.id }) {
                state.discoveredDevices.append(device)
                let devices = state.discoveredDevices
                lock.unlock()
                Task { @MainActor in self.onDevicesUpdated?(devices) }
                return
            }
        }
        lock.unlock()
    }
}
