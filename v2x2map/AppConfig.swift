//
//  AppConfig.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import CoreLocation

public enum AppConfig {
    public enum Network {
        public static let defaultUdpPort: UInt16 = 26001
        public static let camPort: UInt16 = 2001
        public static let denmPort: UInt16 = 2002
        public static let mapemPort: UInt16 = 2003
        public static let ivimPort: UInt16 = 2004
        public static let networkTimeout: TimeInterval = 5.0
    }
    
    public enum Map {
        public static let defaultCenter = CLLocationCoordinate2D(latitude: 48.7784, longitude: 9.1800) // Stuttgart Fallback
        public static let defaultRadiusInMeters: Double = 500.0
        public static let uiRefreshInterval: TimeInterval = 0.1
    }
    
    public enum StationLifecycle {
        public static let vehicleTimeout: TimeInterval = 5.0
        public static let denmTimeout: TimeInterval = 10.0
        public static let cleanupInterval: TimeInterval = 1.0
        
        // NEU: Standardwert für die Hervorhebung (Zeit X in Minuten)
        @MainActor public static var alertThresholdMinutes: Double = 2.0
    }
    
    public enum Filters {
        public static let showRoadsideUnits: Bool = true
        public static let showVehicles: Bool = true
        public static let minimumSpeedThreshold: Double = 0.1
    }
}
