//
//  BLEReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Umfassende Protokolldefinition und Datenstrukturen für den V2X/C-ITS Empfang.
//

import Foundation
import CoreLocation
import CoreBluetooth

/// Repräsentiert die standardisierten UUIDs der OpenTrafficMap-Hardwarearchitektur.
public struct OpenTrafficMapSpecs {
    /// Die Service-UUID des C-ITS G5 Empfängers (ITS-G5 / 5 GHz Sniffer)
    public static let serviceUUID = CBUUID(string: "181C")
    /// Die Characteristic-UUID für das hochfrequente CAM/DENM Byte-Streaming
    public static let characteristicUUID = CBUUID(string: "2A67")
    /// Eigene COEX-Steuerungs-Charakteristik (2A68) - Write
    public static let coexCharacteristicUUID = CBUUID(string: "2A68")
    
    /// Paket-Synchronisations-Byte (STX) laut OpenTrafficMap-Firmwarespezifikation
    public static let startByte: UInt8 = 0x7E
}

/// Struktur für fertig assembliert und decodierte C-ITS Telemetriedaten zur Visualisierung auf der Karte.
public struct CITSNode: Identifiable, Hashable, @unchecked Sendable {
    public let id: UInt32
    public let coordinate: CLLocationCoordinate2D
    public let speedKmH: Double
    public let timestamp: Date
    public let stationType: Int // 1: Auto, 2: Ampel, 3: Fahrrad etc.
    
    public init(id: UInt32, coordinate: CLLocationCoordinate2D, speedKmH: Double, timestamp: Date, stationType: Int) {
        self.id = id
        self.coordinate = coordinate
        self.speedKmH = speedKmH
        self.timestamp = timestamp
        self.stationType = stationType
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: CITSNode, rhs: CITSNode) -> Bool {
        return lhs.id == rhs.id
    }
}
