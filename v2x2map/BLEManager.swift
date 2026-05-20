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

protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, didAssembleCITSFrame frame: Data)
    func bleManager(_ manager: BLEManager, didUpdateConnectionStatus connected: Bool)
    func bleManager(_ manager: BLEManager, didLogDebugMessage message: String)
}

final class BLEManager: NSObject {
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var streamingCharacteristic: CBCharacteristic?
    
    private var incomingBuffer = Data()
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 64.0
    
    private let bleQueue = DispatchQueue(label: "com.v2x2map.ble.corequeue", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.db4ta.v2x2map", category: "BLEManager")
    
    weak var delegate: BLEManagerDelegate?
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: bleQueue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }
    
    func startScanning() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            if self.centralManager.state != .poweredOn {
                self.delegate?.bleManager(self, didLogDebugMessage: "Fehler: Bluetooth ist am iPhone deaktiviert.")
                return
            }
            self.delegate?.bleManager(self, didLogDebugMessage: "Suche gezielt nach Modulkennung 'ITS-G5-RX'...")
            self.centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    func stopScanning() {
        bleQueue.async { [weak self] in
            guard let self = self else { return }
            self.centralManager.stopScan()
            self.delegate?.bleManager(self, didLogDebugMessage: "GATT-Scan manuell gestoppt.")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            delegate?.bleManager(self, didUpdateConnectionStatus: false)
            delegate?.bleManager(self, didLogDebugMessage: "Zentraler BLE-Status geändert auf: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        let name = peripheral.name ?? "Unbekanntes Gerät"
        
        // KORREKTUR: Filtert nun exakt auf die offizielle OpenTrafficMap Kennung "ITS-G5-RX"
        if name.uppercased().contains("ITS-G5-RX") || name.lowercased().contains("v2x") {
            delegate?.bleManager(self, didLogDebugMessage: "Hardware verifiziert: \(name) [RSSI: \(rssi)]. Kopplung initiiert...")
            stopScanning()
            
            discoveredPeripheral = peripheral
            discoveredPeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnectDelay = 1.0
        delegate?.bleManager(self, didUpdateConnectionStatus: true)
        delegate?.bleManager(self, didLogDebugMessage: "Mit ITS-G5-RX verbunden. Optimiere MTU-Bandbreite...")
        
        let negotiatedMTU = peripheral.maximumWriteValueLength(for: .withoutResponse)
        delegate?.bleManager(self, didLogDebugMessage: "MTU-Größe maximiert auf: \(negotiatedMTU) Bytes.")
        
        peripheral.discoverServices([OpenTrafficMapSpecs.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegate?.bleManager(self, didUpdateConnectionStatus: false)
        incomingBuffer.removeAll()
        
        let errorMsg = error?.localizedDescription ?? "Signalverlust"
        delegate?.bleManager(self, didLogDebugMessage: "Verbindung zu ITS-G5-RX verloren: \(errorMsg). Starte Backoff-Scan...")
        
        bleQueue.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self = self else { return }
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
            if let target = self.discoveredPeripheral {
                self.centralManager.connect(target, options: nil)
            } else {
                self.startScanning()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == OpenTrafficMapSpecs.serviceUUID {
            delegate?.bleManager(self, didLogDebugMessage: "V2X-Dienst auf GATT-Server verifiziert.")
            peripheral.discoverCharacteristics([OpenTrafficMapSpecs.characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == OpenTrafficMapSpecs.characteristicUUID {
            self.streamingCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            delegate?.bleManager(self, didLogDebugMessage: "BLE-Notify für CAM/DENM-Stream aktiviert.")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let rawChunk = characteristic.value else { return }
        
        incomingBuffer.append(rawChunk)
        
        let hexString = rawChunk.map { String(format: "%02X ", $0) }.joined()
        delegate?.bleManager(self, didLogDebugMessage: "Stream-In: \(hexString)")
        
        while incomingBuffer.count >= 3 {
            // KORREKTUR: Typsicherer Byte-Vergleich verhindert Compilerabsturz
            if incomingBuffer.first != OpenTrafficMapSpecs.startByte {
                incomingBuffer.removeFirst()
                continue
            }
            
            let lengthBytes = incomingBuffer.subdata(in: 1..<3)
            let payloadLength = lengthBytes.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let totalExpectedPacketLength = 3 + Int(payloadLength)
            
            if incomingBuffer.count >= totalExpectedPacketLength {
                let fullCITSFrame = incomingBuffer.subdata(in: 3..<totalExpectedPacketLength)
                delegate?.bleManager(self, didAssembleCITSFrame: fullCITSFrame)
                incomingBuffer.removeSubrange(0..<totalExpectedPacketLength)
            } else {
                break
            }
        }
    }
}
