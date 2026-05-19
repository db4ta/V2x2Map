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
    
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "BLEReceiver")
    private let lock = NSLock()
    
    // Standard-UUIDs für serielle BLE-Übertragung (ESP32-Standard / Nordic UART)
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private final class ProtectedState {
        var centralManager: CBCentralManager?
        var connectedPeripheral: CBPeripheral?
        var rxCharacteristic: CBCharacteristic?
        var isListening = false
        var onDataReceived: (@Sendable (Data) -> Void)?
    }
    private let state = ProtectedState()
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onDataReceived }
        set { lock.lock(); defer { lock.unlock() }; state.onDataReceived = newValue }
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
        
        if state.centralManager == nil {
            state.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.v2x2map.ble.central", qos: .userInteractive))
        } else {
            scanForESP32()
        }
        lock.unlock()
        logger.info("Bluetooth LE Scan-Modus aktiviert.")
    }
    
    private func scanForESP32() {
        guard let manager = state.centralManager, manager.state == .poweredOn else { return }
        logger.info("Suche nach ESP32 V2X-Sendern über BLE...")
        manager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    public func stopListening() {
        lock.lock()
        defer { lock.unlock() }
        state.isListening = false
        state.centralManager?.stopScan()
        
        if let peripheral = state.connectedPeripheral {
            state.centralManager?.cancelPeripheralConnection(peripheral)
        }
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
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
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        logger.info("ESP32 V2X BLE Hardware gefunden. Verbinde...")
        lock.lock()
        central.stopScan()
        state.connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        lock.unlock()
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Mit ESP32 gekoppelt (BLE). Suche Datenkanäle...")
        peripheral.discoverServices([serviceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.warning("Drahtlose Verbindung zum ESP32 abgebrochen.")
        lock.lock()
        state.connectedPeripheral = nil
        state.rxCharacteristic = nil
        let listening = state.isListening
        lock.unlock()
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
            logger.info("C-ITS BLE-Kanal gefunden. Abonniere Live-Bytes...")
            lock.lock()
            state.rxCharacteristic = characteristic
            lock.unlock()
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
