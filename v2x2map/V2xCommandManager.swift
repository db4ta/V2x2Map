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

@MainActor
public final class V2xCommandManager: Sendable {
    public static let shared = V2xCommandManager()
    
    private let logger = Logger(subsystem: "com.db4ta.v2x2map", category: "V2xCommandManager")
    private let queue = DispatchQueue(label: "com.v2x2map.command.queue", qos: .utility)
    
    private let esp32IP = "192.168.4.1" // Standard ESP32 Access-Point Gateway IP
    private let controlPort: UInt16 = 8888  // ESP32 Steuerport für COEX-Vorgaben
    
    private init() {}
    
    public enum CoexMode: UInt8 {
        case preferWiFi = 0x01
        case balanced = 0x02
    }
    
    /// Sendet ein synchronisiertes Konfigurationsbyte an das RF-Frontend des ESP32-C5
    public func sendCoexCommand(_ mode: CoexMode, viaBLEPeripheral peripheral: CBPeripheral? = nil, characteristic: CBCharacteristic? = nil) {
        // Option A: Über BLE (falls aktiv verbunden)
        if let peripheral = peripheral, let characteristic = characteristic, peripheral.state == .connected {
            let data = Data([mode.rawValue])
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            logger.info("COEX-Modus über BLE-GATT gesendet: \(mode == .preferWiFi ? "Prefer Wi-Fi" : "Balanced")")
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
                let data = Data([mode.rawValue])
                connection.send(content: data, completion: .contentProcessed({ error in
                    if let error = error {
                        self?.logger.error("COEX-Kommando konnte nicht gesendet werden: \(error.localizedDescription)")
                    } else {
                        self?.logger.info("COEX-Modus über UDP gesendet: \(mode == .preferWiFi ? "Prefer Wi-Fi" : "Balanced")")
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
}
