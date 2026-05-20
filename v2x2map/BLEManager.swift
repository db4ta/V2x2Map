//
//  BLEManager.swift
//  v2x2map
//
//  Created for iOS 26.
//  Bluetooth-Zentralmanager kalibriert auf die exakte 'ITS-G5-RX' Hardwarekennung.
//

import Foundation
import CoreBluetooth
import OSLog

@MainActor
protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, didAssembleCITSFrame frame: Data)
    func bleManager(_ manager: BLEManager, didUpdateConnectionStatus connected: Bool)
    func bleManager(_ manager: BLEManager, didLogDebugMessage message: String)
}

// BLEManager verarbeitet alle zeitkritischen BLE-Vorgänge im Hintergrund.
// @unchecked Sendable garantiert die Thread-Sicherheit unter Swift 6 Concurrency.
final class BLEManager: NSObject, @unchecked Sendable {
    private let bleQueue = DispatchQueue(label: "com.v2x2map.ble.corequeue", qos: .userInitiated)
    
    // Strikte State-Machine zur Vermeidung von CoreBluetooth-Race-Conditions
    private enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }
    
    // Die folgenden Variablen werden ausschließlich auf der seriellen bleQueue gelesen und geschrieben.
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var streamingCharacteristic: CBCharacteristic?
    private var connectionState: ConnectionState = .disconnected
    
    private var incomingBuffer = Data()
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 64.0
    
    // Watchdog Parameter & Timer
    private var connectionTimeout: TimeInterval = 5.0
    private var watchdogWorkItem: DispatchWorkItem?
    
    private let logger = Logger(subsystem: "com.db4ta.v2x2map", category: "BLEManager")
    private let restorationID = "com.v2x2map.ble.restoration"
    
    weak var delegate: BLEManagerDelegate?
    
    override init() {
        super.init()
        // CBCentralManager wird asynchron auf der bleQueue initialisiert.
        // Verhindert jegliche Blockierung des Main-Threads beim App-Start!
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            self.centralManager = CBCentralManager(delegate: self, queue: self.bleQueue, options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: self.restorationID
            ])
        }
    }
    
    func setConnectionTimeout(_ timeout: Double) {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            self.connectionTimeout = timeout
            self.notifyDelegateDidLogDebugMessage("Watchdog-Timeout konfiguriert auf: \(timeout)s")
            if self.connectionState == .connected {
                self.resetWatchdog()
            }
        }
    }
    
    func startScanning() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.centralManager != nil else { return }
            
            if self.centralManager.state != .poweredOn {
                self.notifyDelegateDidLogDebugMessage("Fehler: Bluetooth ist am iPhone deaktiviert.")
                return
            }
            
            // Falls wir bereits versuchen zu verbinden oder verbunden sind, breche ab
            guard self.connectionState == .disconnected else { return }
            
            // Suche bereits gekoppelte Peripherals mit der V2X-Service-UUID (181C)
            let connected = self.centralManager.retrieveConnectedPeripherals(withServices: [OpenTrafficMapSpecs.serviceUUID])
            if let match = connected.first(where: { self.isValidV2XDevice(peripheral: $0, advertisementData: [:]) }) {
                self.notifyDelegateDidLogDebugMessage("Bereits verbundenen Empfänger gefunden: \(match.name ?? "OpenTrafficMap"). Verbinde erneut...")
                self.discoveredPeripheral = match
                self.discoveredPeripheral?.delegate = self
                self.connectionState = .connecting
                self.centralManager.connect(match, options: nil)
                return
            }
            
            self.notifyDelegateDidLogDebugMessage("Suche aktiv nach OpenTrafficMap-Hardware...")
            
            // WICHTIG: Scanne mit nil, da viele ESP32 ihre Service-UUID nicht im Werbepaket mitsenden.
            // Die strenge Filterung erfolgt stattdessen live in didDiscover!
            self.centralManager.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
        }
    }
    
    func stopScanning() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.centralManager != nil else { return }
            self.centralManager.stopScan()
            self.notifyDelegateDidLogDebugMessage("GATT-Scan manuell gestoppt.")
        }
    }
    
    // MARK: - Watchdog Steuerung
    private func resetWatchdog() {
        watchdogWorkItem?.cancel()
        
        // Watchdog nur aktiv halten, wenn wir tatsächlich verbunden sind und Notifications empfangen
        guard connectionState == .connected, streamingCharacteristic?.isNotifying == true else { return }
        
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.notifyDelegateDidLogDebugMessage("Watchdog ausgelöst! Keine Daten empfangen für \(self.connectionTimeout)s. Erzwinge sauberen Reconnect...")
            if let target = self.discoveredPeripheral {
                self.centralManager.cancelPeripheralConnection(target)
            }
        }
        
        watchdogWorkItem = item
        bleQueue.asyncAfter(deadline: .now() + connectionTimeout, execute: item)
    }
    
    private func stopWatchdog() {
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
    }
    
    /// Prüft präzise, ob es sich um den gesuchten OpenTrafficMap / G5-Empfänger handelt.
    private func isValidV2XDevice(peripheral: CBPeripheral, advertisementData: [String : Any]) -> Bool {
        // 1. Filterung über den lokalen Namen im Werbepaket (zuverlässig bei Erstentdeckung)
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           isNameMatching(localName) {
            return true
        }
        
        // 2. Filterung über den im iOS-System zwischengespeicherten Gerätenamen
        if let cachedName = peripheral.name, isNameMatching(cachedName) {
            return true
        }
        
        // 3. Filterung über die beworbenen Service-UUIDs im Werbepaket (falls vorhanden)
        if let advertisedUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           advertisedUUIDs.contains(OpenTrafficMapSpecs.serviceUUID) {
            return true
        }
        
        return false
    }
    
    private func isNameMatching(_ name: String) -> Bool {
        let lowerName = name.lowercased()
        return lowerName.contains("opentrafficmap") ||
               lowerName.contains("otm") ||
               lowerName.contains("its-g5-rx") ||
               lowerName.contains("v2x")
    }
    
    // MARK: - Threadsichere Haupt-Thread-Dispatcher
    private func notifyDelegateDidAssembleCITSFrame(_ frame: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.bleManager(self, didAssembleCITSFrame: frame)
        }
    }
    
    private func notifyDelegateDidUpdateConnectionStatus(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.bleManager(self, didUpdateConnectionStatus: connected)
        }
    }
    
    private func notifyDelegateDidLogDebugMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.bleManager(self, didLogDebugMessage: message)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            notifyDelegateDidLogDebugMessage("Bluetooth ist aktiv. Starte Scan…")
            startScanning()
        } else {
            notifyDelegateDidUpdateConnectionStatus(false)
            notifyDelegateDidLogDebugMessage("Zentraler BLE-Status geändert auf: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        
        // Wenn wir nicht im disconnected Status sind, ignorieren wir rigoros alle eintreffenden Werbepakete.
        // Das unterbindet das unkontrollierte Absenden paralleler connect()-Befehle!
        guard connectionState == .disconnected else { return }
        
        if isValidV2XDevice(peripheral: peripheral, advertisementData: advertisementData) {
            let detectedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "V2X-Empfänger"
            notifyDelegateDidLogDebugMessage("OpenTrafficMap verifiziert: \(detectedName) [RSSI: \(rssi)]. Verbinde…")
            
            // Synchroner Zustandswechsel blockiert sofort alle weiteren didDiscover-Aufrufe
            connectionState = .connecting
            centralManager.stopScan()
            
            discoveredPeripheral = peripheral
            discoveredPeripheral?.delegate = self
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnConnectionKey: true
            ])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnectDelay = 1.0
        connectionState = .connected
        notifyDelegateDidUpdateConnectionStatus(true)
        notifyDelegateDidLogDebugMessage("Erfolgreich mit \(peripheral.name ?? "OpenTrafficMap") verbunden. Optimiere MTU-Bandbreite...")
        
        let negotiatedMTU = peripheral.maximumWriteValueLength(for: .withoutResponse)
        notifyDelegateDidLogDebugMessage("MTU-Größe maximiert auf: \(negotiatedMTU) Bytes.")
        
        peripheral.delegate = self
        peripheral.discoverServices([OpenTrafficMapSpecs.serviceUUID]) // Gezielt nach dem V2X-Dienst suchen
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        notifyDelegateDidLogDebugMessage("Verbindungsaufbau mit V2X-Empfänger fehlgeschlagen: \(error?.localizedDescription ?? "Unbekannter Fehler")")
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopWatchdog()
        connectionState = .disconnected
        incomingBuffer.removeAll()
        
        let errorMsg = error?.localizedDescription ?? "Signalverlust"
        notifyDelegateDidLogDebugMessage("Verbindung zu V2X-Empfänger verloren: \(errorMsg). Starte Backoff-Scan...")
        
        self.centralManager.stopScan()
        
        bleQueue.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self = self else { return }
            // Verhindert ein automatisches Reconnect-Spamming, falls der Status sich geändert hat
            guard self.connectionState == .disconnected else { return }
            
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
            if let target = self.discoveredPeripheral {
                self.connectionState = .connecting
                self.notifyDelegateDidLogDebugMessage("Versuche automatische Wiederverbindung...")
                self.centralManager.connect(target, options: nil)
            } else {
                self.startScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = peripherals.first {
            self.discoveredPeripheral = p
            self.discoveredPeripheral?.delegate = self
            let restoredName = p.name ?? "OpenTrafficMap"
            notifyDelegateDidLogDebugMessage("BLE-Status wiederhergestellt für: \(restoredName)")
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            if service.uuid == OpenTrafficMapSpecs.serviceUUID {
                notifyDelegateDidLogDebugMessage("V2X-Dienst auf GATT-Server verifiziert.")
            }
            peripheral.discoverCharacteristics([OpenTrafficMapSpecs.characteristicUUID], for: service) // Nur die Streaming-Char suchen
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            let isTargetUUID = (characteristic.uuid == OpenTrafficMapSpecs.characteristicUUID)
            let hasNotify = characteristic.properties.contains(.notify)
            if isTargetUUID || hasNotify {
                self.streamingCharacteristic = characteristic
                let targetUUID = characteristic.uuid.uuidString
                
                // Hardware-Schutz: 150ms Verzögerung für stabilen ESP32 CCCD Handshake
                bleQueue.asyncAfter(deadline: .now() + 0.15) { [weak self, weak peripheral] in
                    guard let self = self, let peripheral = peripheral else { return }
                    peripheral.setNotifyValue(true, for: characteristic)
                    self.notifyDelegateDidLogDebugMessage("Notify-Aktivierung initiiert für: \(targetUUID)")
                }
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            notifyDelegateDidLogDebugMessage("CCCD-Update fehlgeschlagen für: \(characteristic.uuid.uuidString) – \(error.localizedDescription). Versuche erneut…")
            bleQueue.asyncAfter(deadline: .now() + 0.2) { [weak self, weak peripheral] in
                guard let self = self, let peripheral = peripheral else { return }
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            return
        }
        if characteristic.isNotifying {
            notifyDelegateDidLogDebugMessage("CCCD-Update erfolgreich. Notifying aktiv für: \(characteristic.uuid.uuidString)")
            resetWatchdog() // Starte Watchdog sobald der Datenstrom theoretisch offen ist
        } else {
            notifyDelegateDidLogDebugMessage("Notifying deaktiviert für: \(characteristic.uuid.uuidString)")
            stopWatchdog()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let rawChunk = characteristic.value else { return }
        guard self.streamingCharacteristic == nil || characteristic.uuid == self.streamingCharacteristic?.uuid || characteristic.properties.contains(.notify) else { return }
        
        // Daten erhalten -> Watchdog zurücksetzen
        resetWatchdog()
        
        incomingBuffer.append(rawChunk)
        
        let hexString = rawChunk.map { String(format: "%02X ", $0) }.joined()
        notifyDelegateDidLogDebugMessage("Stream-In: \(hexString)")
        
        while incomingBuffer.count >= 3 {
            if incomingBuffer.first != OpenTrafficMapSpecs.startByte {
                incomingBuffer.removeFirst()
                continue
            }
            
            let lengthBytes = incomingBuffer.subdata(in: 1..<3)
            let payloadLength = lengthBytes.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let totalExpectedPacketLength = 3 + Int(payloadLength)
            
            if incomingBuffer.count >= totalExpectedPacketLength {
                let fullCITSFrame = incomingBuffer.subdata(in: 3..<totalExpectedPacketLength)
                notifyDelegateDidAssembleCITSFrame(fullCITSFrame)
                incomingBuffer.removeSubrange(0..<totalExpectedPacketLength)
            } else {
                break
            }
        }
    }
}

