//
//  CAMessage.swift
//  v2x2map
//
//  Created for iOS 26.
//  100% kompatibel zum Android-Originalprojekt (ETSI CAM-Datenstruktur)
//

import Foundation

/// Repräsentiert den ETSI Fahrzeugtyp (StationType) analog zu ETSI TS 102 894-2.
public enum ETSIStationType: Int, Sendable, Codable {
    case unknown = 0
    case pedestrian = 1
    case cyclist = 2
    case moped = 3
    case motorcycle = 4
    case passengerCar = 5
    case bus = 6
    case lightTruck = 7
    case heavyTruck = 8
    case trailer = 9
    case specialVehicles = 10
    case tram = 11
    case roadSideUnit = 15
}

/// Die spezifischen Nutzdaten einer Cooperative Awareness Message (CAM).
public struct CAMPayload: Sendable, Codable {
    
    /// ETSI StationType ID (z.B. 5 für PKW, 15 für RSU)
    public let stationType: ETSIStationType
    
    /// Fahrzeuggeschwindigkeit in Metern pro Sekunde (m/s)
    public let speed: Double
    
    /// Fahrzeuggeschwindigkeit umgerechnet in Kilometer pro Stunde (km/h)
    public var speedKmH: Double {
        return speed * 3.6
    }
    
    /// Fahrtrichtung (Heading) in Grad (0 = Norden, 90 = Osten, 180 = Süden, 270 = Westen)
    public let heading: Double
    
    /// Fahrzeuglänge in Metern
    public let vehicleLength: Double
    
    /// Fahrzeugbreite in Metern
    public let vehicleWidth: Double
    
    /// Optionaler Status der Lichtanlage / Warnblinker (ETSI ExteriorLights)
    public let exteriorLights: UInt8?
    
    // MARK: - Initialisierer
    public init(
        stationType: ETSIStationType,
        speed: Double,
        heading: Double,
        vehicleLength: Double,
        vehicleWidth: Double,
        exteriorLights: UInt8? = nil
    ) {
        self.stationType = stationType
        self.speed = speed
        self.heading = heading
        self.vehicleLength = vehicleLength
        self.vehicleWidth = vehicleWidth
        self.exteriorLights = exteriorLights
    }
}

// MARK: - Erweiterung für V2XMessage
extension V2XMessage {
    /// Hilfseigenschaft, um direkt zu prüfen, ob es sich um eine gültige CAM handelt.
    public var isCAM: Bool {
        return messageType == .cam && camPayload != nil
    }
    
    /// Komfortabler Zugriff auf die Fahrzeuggeschwindigkeit, falls vorhanden.
    public var currentSpeedKmH: Double? {
        return camPayload?.speedKmH
    }
}
