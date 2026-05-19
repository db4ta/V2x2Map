//
//  MapViewModel.swift
//  v2x2map
//
//  Created for iOS 26.
//

import SwiftUI
import MapKit
import CoreLocation
import Foundation
import OSLog

@Observable
@MainActor
public final class MapViewModel: NSObject, CLLocationManagerDelegate {
    
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "MapViewModel")
    
    private let locationManager = CLLocationManager()
    private let messageProcessor = MessageProcessor()
    
    public let bleReceiver = BLEReceiver()
    
    // KORREKTUR: Verwendung deines originalen Stations-Dictionarys
    public var stations: [String: MapStation] = [:]
    public var isTrackingUserLocation: Bool = true
    public var cameraPosition: MapKit.MapCameraPosition = .automatic
    private var lastUserLocation: CLLocation?
    
    public override init() {
        super.init()
        setupLocationManager()
        setupHardwarePipeline()
        startLifecycleTimer()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
        }
    }
    
    private func setupHardwarePipeline() {
        bleReceiver.onDataReceived = { [weak self] rawBytes in
            guard let self = self else { return }
            
            Task { @MainActor in
                do {
                    // Schaltet das Live-Decoding scharf und fügt Pakete in die Map-Pipeline ein
                    let parsedStation = try ASN1Decoder.decodeV2X(from: rawBytes)
                    let key = "\(parsedStation.stationID)"
                    self.stations[key] = parsedStation
                    
                    if self.isTrackingUserLocation {
                        self.triggerDynamicAutoZoom()
                    }
                } catch {
                    self.logger.error("Decoder-Fehler: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startLifecycleTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Bereinigt tote Stationen nach 10 Sekunden Inaktivität
                let now = Date()
                self.stations = self.stations.filter { _, station in
                    now.timeIntervalSince(station.lastUpdatedAt) < 10.0
                }
            }
        }
    }
    
    public func triggerDynamicAutoZoom() {
        guard let userCoord = lastUserLocation?.coordinate else { return }
        var targetMeters: CLLocationDistance = 350.0
        
        if let closestStation = stations.values.first {
            let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
            let stationLoc = CLLocation(latitude: closestStation.coordinate.latitude, longitude: closestStation.coordinate.longitude)
            let distance = userLoc.distance(from: stationLoc)
            
            if distance > 150 && distance < 2000 {
                targetMeters = distance * 2.0
            }
        }
        
        let mapRegion = MKCoordinateRegion(
            center: userCoord,
            latitudinalMeters: targetMeters,
            longitudinalMeters: targetMeters
        )
        
        withAnimation(.easeInOut(duration: 0.4)) {
            self.cameraPosition = .region(mapRegion)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }
        self.lastUserLocation = latestLocation
        if isTrackingUserLocation {
            triggerDynamicAutoZoom()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("GPS Ortungsfehler: \(error.localizedDescription)")
    }
}
