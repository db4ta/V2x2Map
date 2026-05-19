//
//  ASN1Decoder.swift
//  v2x2map
//
//  Created for iOS 26.
//  Konform mit opentrafficmap & ETSI C-ITS Spezifikationen.
//

import Foundation
import CoreLocation

public final class ASN1Decoder: @unchecked Sendable {
    
    public enum DecoderError: Error {
        case insufficientData
        case invalidBTPPort
    }
    
    /// Dekodiert ein echtes opentrafficmap/ETSI GeoNetworking-BTP Paket
    public static func decodeV2X(from data: Data) throws -> MapStation {
        // Ein echtes C-ITS Paket mit GeoNet + BTP-A Header hat mindestens 36 Bytes
        guard data.count >= 36 else { throw DecoderError.insufficientData }
        
        // 1. Extrahiere den BTP-Destination-Port (Bytes 20-21 im kombinierten Header)
        let btpPort = data.subdata(in: 20..<22).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        
        let isHazard: Bool
        if btpPort == 2001 {
            isHazard = false // CAM (Kooperative Fahrzeuge)
        } else if btpPort == 2002 {
            isHazard = true  // DENM (Dezentrale Gefahrenmeldung / Ampel-Warnung)
        } else {
            throw DecoderError.invalidBTPPort
        }
        
        // 2. Extrahiere 4-Byte ETSI StationID (Bytes 24-27)
        let stationID = data.subdata(in: 24..<28).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        // 3. Extrahiere hochpräzise WGS84-Koordinaten (je 4-Byte Signed Integer, Bytes 28-32 und 32-36)
        let rawLat = data.subdata(in: 28..<32).withUnsafeBytes {
            $0.load(as: Int32.self).bigEndian
        }
        let rawLon = data.subdata(in: 32..<36).withUnsafeBytes {
            $0.load(as: Int32.self).bigEndian
        }
        
        // ETSI Standard-Skalierung: 1/10 Micrograd (Faktor 10^7)
        let latitude = CLLocationDegrees(rawLat) / 10_000_000.0
        let longitude = CLLocationDegrees(rawLon) / 10_000_000.0
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        // 4. Kinematik (Geschwindigkeit und Richtung)
        var speed: Double = 0.0
        var heading: Double = 0.0
        if data.count >= 40 {
            let rawSpeed = data.subdata(in: 36..<38).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let rawHeading = data.subdata(in: 38..<40).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            speed = Double(rawSpeed) * 0.1 // ETSI: 0.1 m/s
            heading = Double(rawHeading) * 0.1 // ETSI: 0.1 Grad
        }
        
        return MapStation(
            stationID: Int(stationID),
            coordinate: coordinate,
            speed: speed,
            heading: heading,
            isHazard: isHazard,
            lastUpdatedAt: Date()
        )
    }
}
