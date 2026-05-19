//
//  MapViewModel.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import MapKit
import CoreLocation
import Observation
import SwiftUI

@MainActor
@Observable
public final class MapViewModel: NSObject, CLLocationManagerDelegate {
    
    // MARK: - UI-Zustand
    public private(set) var stations: [String: MapStation] = [:]
    public var mapRegion: MKCoordinateRegion
    public var isTrackingUserLocation: Bool = true
    public var selectedStation: MapStation? = nil
    
    private let locationManager = CLLocationManager()
    
    public override init() {
        // Initiale Region ist Stuttgart (Fallback)
        self.mapRegion = MKCoordinateRegion(
            center: AppConfig.Map.defaultCenter,
            latitudinalMeters: AppConfig.Map.defaultRadiusInMeters,
            longitudinalMeters: AppConfig.Map.defaultRadiusInMeters
        )
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        
        // BEHOBEN: GPS wird sofort im Hintergrund hochgefahren, um die Karte direkt auszurichten
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        // Falls bereits ein fixer letzter Standort bekannt ist, diesen sofort nutzen
        if let lastLocation = locationManager.location?.coordinate {
            self.mapRegion.center = lastLocation
        }
    }
    
    public func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    public func updateStations(with newStations: [String: MapStation]) {
        self.stations = newStations
        if let selected = selectedStation, newStations[selected.id] == nil {
            self.selectedStation = nil
        }
    }
    
    public func resetMapCenter() {
        if let userLocation = locationManager.location?.coordinate {
            self.mapRegion.center = userLocation
            self.isTrackingUserLocation = true
        } else {
            self.mapRegion.center = AppConfig.Map.defaultCenter
        }
    }
    
    public func selectStation(_ station: MapStation) {
        self.selectedStation = station
    }
    
    public func clearSelection() {
        self.selectedStation = nil
    }
    
    // MARK: - CLLocationManagerDelegate
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, isTrackingUserLocation else { return }
        // Folgt dem echten GPS-Signal flüssig zur Laufzeit
        withAnimation(.easeInOut) {
            self.mapRegion.center = location.coordinate
        }
    }
}
