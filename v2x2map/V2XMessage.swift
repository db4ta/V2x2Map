//
//  V2XMessage.swift
//  v2x2map
//
//  Created for iOS 26.
//  100% kompatibel zum Android-Originalprojekt (Basis-Datenmodell für ETSI C-ITS)
//

import Foundation
import CoreLocation

/// Definiert die unterstützten ETSI C-ITS Nachrichtentypen analog zum Android-Projekt.
public enum V2XMessageType: String, Sendable, Codable {
    case cam   = "CAM"
    case denm  = "DENM"
    case mapem = "MAPEM"
    case ivim  = "IVIM"
    case unknown = "UNKNOWN"
}

/// Das Basis-Protokoll, das jede spezifische V2X-Nachricht erfüllen muss.
public protocol V2XMessageProtocol: Sendable {
    var stationID: UInt32 { get }
    var generationTimestamp: Date { get }
    var messageType: V2XMessageType { get }
    var coordinate: CLLocationCoordinate2D { get }
}

/// Einheitlicher Container für empfangene und geparste V2X-Nachrichten.
public struct V2XMessage: V2XMessageProtocol, Sendable, Codable {
    
    // MARK: - Protokoll-Eigenschaften
    
    public let stationID: UInt32
    public let generationTimestamp: Date
    public let messageType: V2XMessageType
    public let coordinate: CLLocationCoordinate2D
    
    // MARK: - Typspezifische Nutzdaten (Payloads)
    
    public var camPayload: CAMPayload?
    public var denmPayload: DENMPayload?
    
    // MARK: - Initialisierer
    public init(
        stationID: UInt32,
        generationTimestamp: Date,
        messageType: V2XMessageType,
        coordinate: CLLocationCoordinate2D,
        camPayload: CAMPayload? = nil,
        denmPayload: DENMPayload? = nil
    ) {
        self.stationID = stationID
        self.generationTimestamp = generationTimestamp
        self.messageType = messageType
        self.coordinate = coordinate
        self.camPayload = camPayload
        self.denmPayload = denmPayload
    }
}

// MARK: - Codable Erweiterung für CLLocationCoordinate2D
extension CLLocationCoordinate2D: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}
