//
//  DENMessage.swift
//  v2x2map
//
//  Created for iOS 26.
//  100% kompatibel zum Android-Originalprojekt (ETSI DENM-Datenstruktur)
//

import Foundation

/// Bildet die ETSI Standard-Hauptursachencodes (Cause Codes) ab (ETSI TS 102 894-2).
public enum ETSICauseCode: Int, Sendable, Codable {
    case reserved = 0
    case trafficCondition = 1
    case accident = 2
    case roadworks = 3
    case adverseWeatherCondition_Adhesion = 6
    case hazardousLocation_SurfaceCondition = 9
    case hazardousLocation_ObstacleOnTheRoad = 10
    case hazardousLocation_AnimalOnTheRoad = 11
    case humanPresenceOnTheRoad = 12
    case wrongWayDriving = 14
    case rescueAndRecoveryWorkInProgress = 15
    case adverseWeatherCondition_Visibility = 17
    case adverseWeatherCondition_Precipitation = 18
    case slowVehicle = 26
    case dangerousSituation = 99
}

/// Die spezifischen Nutzdaten einer Decentralized Environmental Notification Message (DENM).
public struct DENMPayload: Sendable, Codable {
    
    // MARK: - Identifikation der Meldung
    
    /// Eindeutige ID der Event-Sequenz (Kombination aus Ursprungs-StationID und Sequenznummer)
    public let actionID: String
    
    /// Die ETSI-Stations-ID, welche das Ereignis ursprünglich ausgelöst hat
    public let originatorStationID: UInt32
    
    /// Fortlaufende Sequenznummer des Ereignisses
    public let sequenceNumber: UInt16
    
    // MARK: - Ereignis-Details
    
    /// Der ETSI-Hauptursachencode (z.B. 3 für Baustelle, 2 für Unfall)
    public let causeCode: ETSICauseCode
    
    /// Der spezifische Unter-Code (Sub-Cause Code) für detailliertere Spezifikationen
    public let subCauseCode: Int
    
    // MARK: - Zeitliche Gültigkeit
    
    /// Zeitpunkt, an dem das Ereignis abläuft (berechnet aus DetectionTime + ValidityDuration)
    public let expiryTime: Date
    
    /// Die ETSI-Priorität der Meldung (InformationQuality: 0 = niedrig, 7 = kritisch)
    public let informationQuality: Int
    
    /// Gibt an, ob das Ereignis aktiv ist oder storniert wurde (Termination: 0 = IsCancellation, 1 = IsNegation, 2 = Normal)
    public let isTermination: Bool
    
    // MARK: - Hilfsfunktionen für die UI
    
    /// Liefert eine lokalisiert lesbare Textbeschreibung des Ereignisses für die UI
    public var eventDescription: String {
        switch causeCode {
        case .trafficCondition: return "Stau / Verkehrsbehinderung"
        case .accident: return "Unfall"
        case .roadworks: return "Baustelle"
        case .adverseWeatherCondition_Adhesion: return "Straßenglätte"
        case .hazardousLocation_SurfaceCondition: return "Schlechter Straßenzustand"
        case .hazardousLocation_ObstacleOnTheRoad: return "Hindernis auf der Fahrbahn"
        case .hazardousLocation_AnimalOnTheRoad: return "Wildwechsel"
        case .humanPresenceOnTheRoad: return "Personen auf der Fahrbahn"
        case .wrongWayDriving: return "Geisterfahrer!"
        case .rescueAndRecoveryWorkInProgress: return "Einsatzfahrzeuge vor Ort"
        case .adverseWeatherCondition_Visibility: return "Eingeschränkte Sicht (Nebel/Rauch)"
        case .adverseWeatherCondition_Precipitation: return "Starker Niederschlag"
        case .slowVehicle: return "Langsames Fahrzeug"
        case .dangerousSituation: return "Gefahrensituation"
        case .reserved: return "Unbekannte Gefahr"
        }
    }
    
    // MARK: - Initialisierer
    public init(
        originatorStationID: UInt32,
        sequenceNumber: UInt16,
        causeCode: ETSICauseCode,
        subCauseCode: Int,
        expiryTime: Date,
        informationQuality: Int,
        isTermination: Bool = false
    ) {
        self.originatorStationID = originatorStationID
        self.sequenceNumber = sequenceNumber
        self.actionID = "\(originatorStationID)_\(sequenceNumber)"
        self.causeCode = causeCode
        self.subCauseCode = subCauseCode
        self.expiryTime = expiryTime
        self.informationQuality = informationQuality
        self.isTermination = isTermination
    }
}

// MARK: - Erweiterung für V2XMessage
extension V2XMessage {
    /// Hilfseigenschaft, um direkt zu prüfen, ob es sich um eine gültige DENM handelt.
    public var isDENM: Bool {
        return messageType == .denm && denmPayload != nil
    }
    
    /// Prüft, ob die Gefahrenmeldung basierend auf der aktuellen Systemzeit noch gültig ist.
    public var isExpired: Bool {
        guard let payload = denmPayload else { return true }
        return Date() > payload.expiryTime
    }
}
