//
//  ASN1Decoder.swift
//  v2x2map
//
//  Created for iOS 26.
//  ETSI C-ITS Protokoll-Parser für CAM und DENM Telegramme
//

import Foundation
import CoreLocation

public final class ASN1Decoder: @unchecked Sendable {
    
    public enum DecoderError: Error {
        case insufficientData
        case unknownMessageID
    }
    
    /// Dekodiert ein rohes Byte-Paket vom ESP32-Modem in ein MapStation-Objekt
    public static func decodeV2X(from data: Data) throws -> MapStation {
        guard data.count >= 12 else { throw DecoderError.insufficientData }
        
        // 1. Extrahiere ETSI MessageID (Byte 0: 1 = DENM, 2 = CAM)
        let messageID = Int(data[0])
        guard messageID == 1 || messageID == 2 else { throw DecoderError.unknownMessageID }
        
        // 2. Extrahiere 4-Byte StationID (Big Endian) aus Bytes 1 bis 4
        let stationID = data.subdata(in: 1..<5).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        // 3. Extrahiere GPS-Koordinaten (je 4-Byte Signed Integer, Big Endian)
        let rawLat = data.subdata(in: 5..<9).withUnsafeBytes {
            $0.load(as: Int32.self).bigEndian
        }
        let rawLon = data.subdata(in: 9..<13).withUnsafeBytes {
            $0.load(as: Int32.self).bigEndian
        }
        
        let latitude = CLLocationDegrees(rawLat) / 10_000_000.0
        let longitude = CLLocationDegrees(rawLon) / 10_000_000.0
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        var speed: Double = 0.0
        var heading: Double = 0.0
        if data.count >= 17 {
            let rawSpeed = data.subdata(in: 13..<15).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let rawHeading = data.subdata(in: 15..<17).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            speed = Double(rawSpeed) * 0.1
            heading = Double(rawHeading) * 0.1
        }
        
        // KORREKTUR: Initialisierung matcht jetzt exakt die bereinigte MapStation-Struktur
        return MapStation(
            stationID: Int(stationID),
            coordinate: coordinate,
            speed: speed,
            heading: heading,
            isHazard: messageID == 1, // true bei DENM (Alarm)
            lastUpdatedAt: Date()
        )
    }
}
