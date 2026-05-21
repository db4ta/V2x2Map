//
//  V2xCommandManager.swift
//  v2x2map
//
//  Created for iOS 26.
//  Ermöglicht der App, COEX-Zustände aktiv an die ESP32 Hardware zu übermitteln.
//

import Foundation
import Network
import CoreBluetooth
import OSLog
import Combine // Importiert das ObservableObject-Protokoll

final class V2xCommandManager: ObservableObject, @unchecked Sendable {
    static let shared = V2xCommandManager()
    
    private let logger = Logger(subsystem: "com.db4ta.v2x2map", category: "V2xCommandManager")
    private let queue = DispatchQueue(label: "com.v2x2map.command.queue", qos: .utility)
    
    private let esp32IP = "192.168.4.1" // Standard ESP32 Access-Point Gateway IP
    private let controlPort: UInt16 = 8888  // ESP32 Steuerport für COEX-Vorgaben
    
    /// Aktiver BLEManager für direkte GATT-Writes
    weak var activeBLEManager: BLEManager?
    
    private init() {}
    
    enum CoexMode: UInt8 {
        case balanced = 0x00
        case preferWiFi = 0x01
        case preferBLE = 0x02
    }
    
    /// Sendet ein synchronisiertes Konfigurationsbyte an das RF-Frontend des ESP32-C5
    func sendCoexCommand(mode: UInt8) {
        // Option A: Über BLE (falls aktiv verbunden)
        if let bleManager = activeBLEManager {
            bleManager.writeCoexPriority(mode)
            logger.info("COEX-Modus über BLE-GATT gesendet: 0x\(String(format: "%02X", mode))")
            return
        }
        
        // Option B: Über UDP-Kanal (Wi-Fi AP Verbindung)
        let connection = NWConnection(
            host: NWEndpoint.Host(esp32IP),
            port: NWEndpoint.Port(rawValue: controlPort)!,
            using: .udp
        )
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                let data = Data([mode])
                connection.send(content: data, completion: .contentProcessed({ error in
                    if let error = error {
                        self?.logger.error("COEX-Kommando konnte nicht gesendet werden: \(error.localizedDescription)")
                    } else {
                        self?.logger.info("COEX-Modus über UDP gesendet: 0x\(String(format: "%02X", mode))")
                    }
                    connection.cancel()
                }))
            } else if case .failed(let error) = state {
                self?.logger.error("Verbindungsfehler beim COEX-Kanal: \(error.localizedDescription)")
                connection.cancel()
            }
        }
        
        connection.start(queue: queue)
    }
    
    @available(*, deprecated, message: "Nutze sendCoexCommand(mode:)")
    func sendCoexCommand(_ mode: CoexMode, viaBLEPeripheral peripheral: CBPeripheral? = nil, characteristic: CBCharacteristic? = nil) {
        sendCoexCommand(mode: mode.rawValue)
    }
}
