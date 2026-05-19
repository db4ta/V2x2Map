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

public final class BLEReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    // MARK: - Public types
    public struct DiscoveredDevice: Identifiable, Hashable {
        public let id: UUID
        public let name: String
        public let rssi: Int
    }

    // MARK: - Constants
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "BLEReceiver")
    private let lock = NSLock()

    // Standard-UUIDs für serielle BLE-Übertragung (ESP32-Standard / Nordic UART)
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // Erwartetes Namenspräfix des ESP32-C5 V2X-Firmware-GATT-Servers
    private let targetDeviceNamePrefix = "ESP32"

    // MARK: - Protected state
    private final class ProtectedState {
        var centralManager: CBCentralManager?
        var connectedPeripheral: CBPeripheral?
        var rxCharacteristic: CBCharacteristic?
        var isListening = false
        var isScanning = false
        var onDataReceived: (@Sendable (Data) -> Void)?
        var connectionTimeoutTimer: DispatchSourceTimer?
        var selectedPeripheralID: UUID?
    }
    private let state = ProtectedState()

    // Entdeckte Peripherals werden außerhalb von ProtectedState gehalten, aber ebenfalls gelockt
    private var discoveredPeripherals: [UUID: (peripheral: CBPeripheral, name: String, rssi: Int)] = [:]

    // MARK: - Public API
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onDataReceived }
        set { lock.lock(); defer { lock.unlock() }; state.onDataReceived = newValue }
    }

    public var devices: [DiscoveredDevice] {
        lock.lock(); defer { lock.unlock() }
        return discoveredPeripherals.values
            .map { DiscoveredDevice(id: $0.peripheral.identifier, name: $0.name, rssi: $0.rssi) }
            .sorted { $0.rssi > $1.rssi }
    }

    public override init() {
        super.init()
    }

    // Rückwärtskompatibel: Startet nur den Scan
    public func startListening() { startScan() }

    public func checkConnectionStatus() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.connectedPeripheral != nil && state.rxCharacteristic != nil
    }

    public func startScan() {
        lock.lock()
        if state.isScanning { lock.unlock(); return }
        state.isScanning = true
        state.isListening = true

        discoveredPeripherals.removeAll()

        if state.centralManager == nil {
            state.centralManager = CBCentralManager(
                delegate: self,
                queue: DispatchQueue(label: "com.v2x2map.ble.central", qos: .userInteractive)
            )
        } else {
            scanForESP32()
        }
        lock.unlock()
        logger.info("Bluetooth LE Scan-Modus aktiviert.")
    }

    public func stopScan() {
        lock.lock(); defer { lock.unlock() }
        state.isScanning = false
        state.centralManager?.stopScan()
        logger.info("BLE-Scan gestoppt.")
    }

    public func connect(to id: UUID) {
        lock.lock()
        guard let entry = discoveredPeripherals[id], let manager = state.centralManager, manager.state == .poweredOn else {
            lock.unlock()
            logger.error("Verbindung fehlgeschlagen: Gerät nicht (mehr) verfügbar oder Bluetooth aus.")
            return
        }
        // Stoppe vorherige Versuche / Timer
        cancelConnectionTimeoutLocked()
        state.selectedPeripheralID = id
        let peripheral = entry.peripheral
        state.connectedPeripheral = peripheral
        peripheral.delegate = self
        manager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        startConnectionTimeoutLocked(seconds: 10)
        lock.unlock()
        logger.info("Verbindungsaufbau zu \(entry.name) angefordert…")
    }

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        cancelConnectionTimeoutLocked()
        if let peripheral = state.connectedPeripheral {
            state.centralManager?.cancelPeripheralConnection(peripheral)
        }
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
        state.selectedPeripheralID = nil
        logger.info("Bluetooth-Verbindung getrennt.")
    }

    // MARK: - Internal helpers
    private func scanForESP32() {
        guard let manager = state.centralManager, manager.state == .poweredOn else { return }
        logger.info("Starte ungefilterten BLE-Scan für maximale Erkennungsrate…")
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func startConnectionTimeoutLocked(seconds: Int) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(seconds))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let peripheral = self.state.connectedPeripheral
            self.lock.unlock()
            self.logger.error("Timeout beim Verbindungsaufbau.")
            if let peripheral {
                self.state.centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
        state.connectionTimeoutTimer = timer
        timer.resume()
    }

    private func cancelConnectionTimeoutLocked() {
        state.connectionTimeoutTimer?.cancel()
        state.connectionTimeoutTimer = nil
    }

    // MARK: - CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            lock.lock(); let shouldScan = state.isScanning; lock.unlock()
            if shouldScan { scanForESP32() }
        case .unauthorized:
            logger.error("Fehlende Berechtigung! Info.plist prüfen (NSBluetoothAlwaysUsageDescription).")
        case .poweredOff:
            logger.warning("Bluetooth am iPhone ist ausgeschaltet.")
        default:
            logger.warning("Zentraler Bluetooth-Manager wechselte in Status: \(String(describing: central.state))")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Extrahiere lokalen Namen aus dem Broadcast-Paket oder dem CoreBluetooth-Cache
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unbekannt"

        logger.info("Gefunden: \(localName, privacy: .public) RSSI=\(RSSI.intValue)")

        // Alle Geräte aufnehmen und nach RSSI sortiert bereitstellen
        lock.lock()
        discoveredPeripherals[peripheral.identifier] = (peripheral, localName, RSSI.intValue)
        let autoReconnectWanted = (state.selectedPeripheralID == peripheral.identifier)
        lock.unlock()

        // Falls wir durch Disconnect noch einmal entdeckt werden und dieses Gerät ausgewählt ist, erneut verbinden
        if autoReconnectWanted, state.connectedPeripheral == nil {
            connect(to: peripheral.identifier)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lock.lock()
        cancelConnectionTimeoutLocked()
        lock.unlock()
        logger.info("Erfolgreich gekoppelt mit \(peripheral.name ?? "ESP32"). Suche Services…")
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lock.lock()
        cancelConnectionTimeoutLocked()
        let shouldScan = state.isScanning
        lock.unlock()
        logger.error("Verbindungsaufbau fehlgeschlagen: \(String(describing: error?.localizedDescription))")
        if shouldScan { scanForESP32() }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.warning("Drahtlose Verbindung zum ESP32 abgebrochen.")
        lock.lock()
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
        let shouldScan = state.isScanning
        lock.unlock()
        if shouldScan { scanForESP32() }
    }

    // MARK: - CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("Fehler beim Erkennen von Diensten: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            logger.info("Service gefunden. Suche RX-Charakteristik…")
            peripheral.discoverCharacteristics([rxCharacteristicUUID], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logger.error("Fehler beim Erkennen von Merkmalen: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == rxCharacteristicUUID {
            logger.info("C-ITS BLE-Kanal erfolgreich abonniert. Empfange Live-Bytes…")
            lock.lock(); state.rxCharacteristic = characteristic; lock.unlock()
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Datenübertragungsfehler: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid == rxCharacteristicUUID, let data = characteristic.value, !data.isEmpty else { return }
        lock.lock(); let callback = state.onDataReceived; lock.unlock()
        callback?(data)
    }
}

