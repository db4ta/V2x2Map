//
//  MessageProcessor.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import CoreLocation

public final class MessageProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var internalStations: [String: MapStation] = [:]
    
    public var activeStations: [String: MapStation] {
        lock.lock()
        defer { lock.unlock() }
        cleanupExpiredStations()
        return internalStations
    }
    
    public init() {}
    
    public func updateStation(_ station: MapStation) {
        lock.lock()
        defer { lock.unlock() }
        internalStations["\(station.stationID)"] = station
    }
    
    private func cleanupExpiredStations() {
        let now = Date()
        // KORREKTUR: Nutzt das reale lastUpdatedAt zur fehlerfreien Timeout-Berechnung
        internalStations = internalStations.filter { _, station in
            now.timeIntervalSince(station.lastUpdatedAt) < 10.0
        }
    }
}
