//
//  MessageProcessor.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation

public final class MessageProcessor: Sendable {
    private final class ProcessorState: @unchecked Sendable {
        var activeStations: [String: MapStation] = [:]
        var onModelUpdate: (@Sendable ([String: MapStation]) -> Void)?
        var cleanupTimer: Task<Void, Never>?
    }
    private let state = ProcessorState()
    private let lock = NSLock()
    
    public var onModelUpdate: (@Sendable ([String: MapStation]) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onModelUpdate }
        set { lock.lock(); defer { lock.unlock() }; state.onModelUpdate = newValue }
    }
    
    public init() { startCleanupTimer() }
    
    public func process(_ message: V2XMessage) async {
        lock.lock()
        var stationsChanged = false
        defer {
            let snapshot = state.activeStations
            let callback = state.onModelUpdate
            lock.unlock()
            if stationsChanged { callback?(snapshot) }
        }
        
        let existing = state.activeStations[String(message.stationID)]
        
        if message.messageType == .cam {
            if !AppConfig.Filters.showVehicles && message.camPayload?.stationType != .roadSideUnit { return }
            if !AppConfig.Filters.showRoadsideUnits && message.camPayload?.stationType == .roadSideUnit { return }
            
            if let newStation = MapStation.from(camMessage: message, existingStation: existing) {
                state.activeStations[newStation.id] = newStation
                stationsChanged = true
            }
        } else if message.messageType == .denm, let payload = message.denmPayload {
            let existingDenm = state.activeStations[payload.actionID]
            if payload.isTermination {
                if state.activeStations.removeValue(forKey: payload.actionID) != nil { stationsChanged = true }
            } else if let newHazard = MapStation.from(denmMessage: message, existingStation: existingDenm) {
                state.activeStations[newHazard.id] = newHazard
                stationsChanged = true
            }
        }
    }
    
    private func startCleanupTimer() {
        lock.lock()
        state.cleanupTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.StationLifecycle.cleanupInterval * 1_000_000_000))
                guard let self = self else { break }
                self.lock.lock()
                var changed = false
                let now = Date()
                for (id, station) in self.state.activeStations {
                    let timeout = station.isHazard ? AppConfig.StationLifecycle.denmTimeout : AppConfig.StationLifecycle.vehicleTimeout
                    if now.timeIntervalSince(station.lastUpdatedAt) > timeout {
                        self.state.activeStations.removeValue(forKey: id)
                        changed = true
                    }
                }
                let snapshot = self.state.activeStations
                let callback = self.state.onModelUpdate
                self.lock.unlock()
                if changed { callback?(snapshot) }
            }
        }
        lock.unlock()
    }
}
