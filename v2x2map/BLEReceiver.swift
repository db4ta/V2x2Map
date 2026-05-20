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
struct OpenTrafficMapSpecs {
    /// Die Service-UUID des C-ITS G5 Empfängers (ITS-G5 / 5 GHz Sniffer)
    static let serviceUUID = CBUUID(string: "181C")
    /// Die Characteristic-UUID für das hochfrequente CAM/DENM Byte-Streaming
    static let characteristicUUID = CBUUID(string: "2A67")
    
    /// Paket-Synchronisations-Byte (STX) laut OpenTrafficMap-Firmwarespezifikation
    static let startByte: UInt8 = 0x02
}

/// Struktur für fertig assembliert und decodierte C-ITS Telemetriedaten zur Visualisierung auf der Karte.
struct CITSNode: Identifiable, Hashable {
    let id: UInt32
    let coordinate: CLLocationCoordinate2D
    let speedKmH: Double
    let timestamp: Date
    let stationType: Int // 1: Auto, 2: Ampel, 3: Fahrrad etc.
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CITSNode, rhs: CITSNode) -> Bool {
        return lhs.id == rhs.id
    }
}
