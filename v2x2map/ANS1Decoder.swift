//
//  ASN1Decoder.swift
//  v2x2map
//
//  Created for iOS 26.
//  Hybrid-Prüfstand: Konstante Dauerläufer PLUS parallele Zufallsfahrzeuge
//

import Foundation
import CoreLocation
import OSLog

public final class ASN1Decoder: Sendable {
    
    private static let logger = Logger(subsystem: "com.v2x2map.app", category: "ASN1Decoder")
    
    public static func decode(data: Data, isSimulationAllowed: Bool, referenceCoordinate: CLLocationCoordinate2D) -> V2XMessage? {
        guard data.count >= 4 else { return nil }
        
        // 1. SCAN-PHASE: Suche nach echten ETSI-Frames im Funkstrom
        for index in 0..<(data.count - 4) {
            let protocolVersion = data[index]
            let messageID = data[index + 1]
            
            if (protocolVersion == 1 || protocolVersion == 2) {
                if messageID == 2 {
                    return parseRealCAM(data, offset: index, fallbackCenter: referenceCoordinate)
                } else if messageID == 1 {
                    return parseRealDENM(data, offset: index, fallbackCenter: referenceCoordinate)
                }
            }
        }
        
        // 2. LABOR-TESTPHASE: Wenn der lila Schalter aktiv ist
        if isSimulationAllowed {
            return generateMixedSimulation(around: referenceCoordinate)
        }
        
        return nil
    }
    
    private static func parseRealCAM(_ data: Data, offset: Int, fallbackCenter: CLLocationCoordinate2D) -> V2XMessage? {
        let idIndex = offset + 2
        guard data.count > idIndex + 3 else { return nil }
        let stationID = data.subdata(in: idIndex..<idIndex+4).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        return V2XMessage(
            stationID: stationID,
            generationTimestamp: Date(),
            messageType: .cam,
            coordinate: fallbackCenter,
            camPayload: CAMPayload(stationType: .passengerCar, speed: 13.89, heading: 90.0, vehicleLength: 4.5, vehicleWidth: 1.8)
        )
    }
    
    private static func parseRealDENM(_ data: Data, offset: Int, fallbackCenter: CLLocationCoordinate2D) -> V2XMessage? {
        return V2XMessage(
            stationID: 99001,
            generationTimestamp: Date(),
            messageType: .denm,
            coordinate: fallbackCenter,
            denmPayload: DENMPayload(originatorStationID: 99001, sequenceNumber: 1, causeCode: .accident, subCauseCode: 0, expiryTime: Date().addingTimeInterval(60), informationQuality: 5)
        )
    }
    
    // MARK: - Gemischter Simulations-Generator
    
    private static func generateMixedSimulation(around center: CLLocationCoordinate2D) -> V2XMessage {
        // Gewürfelt: In 40% der Fälle feuern wir die langlebigen Alarmoberflächen-Dauerläufer ab
        let diceRoll = Double.random(in: 0...1)
        
        if diceRoll < 0.20 {
            // Dauerläufer 1: PKW (Bleibt unendlich, da ID fix)
            let simulatedCoordinate = CLLocationCoordinate2D(latitude: center.latitude + 0.0006, longitude: center.longitude + 0.0004)
            return V2XMessage(
                stationID: 55555,
                generationTimestamp: Date(),
                messageType: .cam,
                coordinate: simulatedCoordinate,
                camPayload: CAMPayload(stationType: .passengerCar, speed: 11.1, heading: 45.0, vehicleLength: 4.5, vehicleWidth: 1.8)
            )
        } else if diceRoll < 0.40 {
            // Dauerläufer 2: Baustelle (Bleibt unendlich, da ID fix)
            let simulatedCoordinate = CLLocationCoordinate2D(latitude: center.latitude - 0.0005, longitude: center.longitude - 0.0007)
            return V2XMessage(
                stationID: 77777,
                generationTimestamp: Date(),
                messageType: .denm,
                coordinate: simulatedCoordinate,
                denmPayload: DENMPayload(originatorStationID: 77777, sequenceNumber: 1, causeCode: .roadworks, subCauseCode: 0, expiryTime: Date().addingTimeInterval(3600), informationQuality: 7)
            )
        } else {
            // ➡️ PARALLEL IN 60% DER FÄLLE: Dynamische Zufalls-Objekte (Verschwinden nach 5s von selbst)
            let randomLatDelta = Double.random(in: -0.002...0.002)
            let randomLonDelta = Double.random(in: -0.002...0.002)
            let simulatedCoordinate = CLLocationCoordinate2D(latitude: center.latitude + randomLatDelta, longitude: center.longitude + randomLonDelta)
            
            if Bool.random() {
                // Zufälliges CAM-Fahrzeug
                return V2XMessage(
                    stationID: UInt32.random(in: 10000...49999), // Zufällige ID
                    generationTimestamp: Date(),
                    messageType: .cam,
                    coordinate: simulatedCoordinate,
                    camPayload: CAMPayload(stationType: .passengerCar, speed: Double.random(in: 5.0...15.0), heading: Double.random(in: 0.0...360.0), vehicleLength: 4.5, vehicleWidth: 1.8)
                )
            } else {
                // Zufälliges DENM-Gefahrenereignis
                let randomID = UInt32.random(in: 80000...99000)
                return V2XMessage(
                    stationID: randomID,
                    generationTimestamp: Date(),
                    messageType: .denm,
                    coordinate: simulatedCoordinate,
                    denmPayload: DENMPayload(originatorStationID: randomID, sequenceNumber: UInt16.random(in: 2...255), causeCode: .accident, subCauseCode: 0, expiryTime: Date().addingTimeInterval(15), informationQuality: 4)
                )
            }
        }
    }
}
