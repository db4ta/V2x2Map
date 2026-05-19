//
//  MapStation.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import CoreLocation

public struct MapStation: Identifiable, Sendable, Equatable {
    public let id: String
    public let stationID: UInt32
    public let coordinate: CLLocationCoordinate2D
    public let stationType: ETSIStationType
    public let speedKmH: Double?
    public let heading: Double?
    public let primaryMessageType: V2XMessageType
    public let eventLabel: String?
    public let lastUpdatedAt: Date
    
    // NEU: Verfolgung des ersten Kontakts für die Zeit-X-Überwachung
    public let firstDetectedAt: Date
    
    public var isMoving: Bool {
        guard let speed = speedKmH else { return false }
        return speed > AppConfig.Filters.minimumSpeedThreshold * 3.6
    }
    
    public var isHazard: Bool { return primaryMessageType == .denm }
    
    // NEU: Prüft reaktiv auf dem MainActor, ob das Objekt das eingestellte Zeit-X-Limit überschreitet
    @MainActor
    public var exceedsAlertThreshold: Bool {
        let durationSeconds = Date().timeIntervalSince(firstDetectedAt)
        let thresholdSeconds = AppConfig.StationLifecycle.alertThresholdMinutes * 60.0
        return durationSeconds >= thresholdSeconds
    }
    
    public init(id: String, stationID: UInt32, coordinate: CLLocationCoordinate2D, stationType: ETSIStationType, speedKmH: Double? = nil, heading: Double? = nil, primaryMessageType: V2XMessageType, eventLabel: String? = nil, lastUpdatedAt: Date = Date(), firstDetectedAt: Date = Date()) {
        self.id = id
        self.stationID = stationID
        self.coordinate = coordinate
        self.stationType = stationType
        self.speedKmH = speedKmH
        self.heading = heading
        self.primaryMessageType = primaryMessageType
        self.eventLabel = eventLabel
        self.lastUpdatedAt = lastUpdatedAt
        self.firstDetectedAt = firstDetectedAt
    }
    
    public static func from(camMessage: V2XMessage, existingStation: MapStation? = nil) -> MapStation? {
        guard let payload = camMessage.camPayload else { return nil }
        return MapStation(
            id: String(camMessage.stationID),
            stationID: camMessage.stationID,
            coordinate: camMessage.coordinate,
            stationType: payload.stationType,
            speedKmH: payload.speedKmH,
            heading: payload.heading,
            primaryMessageType: .cam,
            eventLabel: nil,
            lastUpdatedAt: Date(),
            firstDetectedAt: existingStation?.firstDetectedAt ?? Date() // Behält den ersten Kontakt bei Updates
        )
    }
    
    public static func from(denmMessage: V2XMessage, existingStation: MapStation? = nil) -> MapStation? {
        guard let payload = denmMessage.denmPayload else { return nil }
        return MapStation(
            id: payload.actionID,
            stationID: denmMessage.stationID,
            coordinate: denmMessage.coordinate,
            stationType: .unknown,
            speedKmH: nil,
            heading: nil,
            primaryMessageType: .denm,
            eventLabel: payload.eventDescription,
            lastUpdatedAt: Date(),
            firstDetectedAt: existingStation?.firstDetectedAt ?? Date()
        )
    }
    
    // Equatable Konformität für reibungslose SwiftUI-Listen-Updates
    public static func qquatable(lhs: MapStation, rhs: MapStation) -> Bool {
        return lhs.id == rhs.id && lhs.lastUpdatedAt == rhs.lastUpdatedAt
    }
    
    public static func == (lhs: MapStation, rhs: MapStation) -> Bool {
        return lhs.id == rhs.id && lhs.lastUpdatedAt == rhs.lastUpdatedAt
    }
}
