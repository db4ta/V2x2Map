//
//  MapStation.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import CoreLocation

public struct MapStation: Identifiable, Equatable {
    public let id = UUID()
    public let stationID: Int
    public let coordinate: CLLocationCoordinate2D
    public let speed: Double   // in m/s
    public let heading: Double // in Grad
    public let isHazard: Bool  // true = DENM (Alarm), false = CAM (Fahrzeug)
    
    // KORREKTUR: Exakter Variablenname aus deinem originalen GitHub-Code
    public var lastUpdatedAt: Date
    
    public init(stationID: Int, coordinate: CLLocationCoordinate2D, speed: Double, heading: Double, isHazard: Bool, lastUpdatedAt: Date = Date()) {
        self.stationID = stationID
        self.coordinate = coordinate
        self.speed = speed
        self.heading = heading
        self.isHazard = isHazard
        self.lastUpdatedAt = lastUpdatedAt
    }
    
    public static func == (lhs: MapStation, rhs: MapStation) -> Bool {
        lhs.id == rhs.id && lhs.lastUpdatedAt == rhs.lastUpdatedAt
    }
}
