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
    
    public let bleReceiver = BLEReceiver()
    
    // KORREKTUR: Umstellung auf ein reaktives Array. Das zwingt SwiftUI bei jeder
    // Paket-Änderung zu einer sofortigen Neuzeichnung von Karte und Liste!
    public var stations: [MapStation] = []
    
    public var isTrackingUserLocation: Bool = true
    public var cameraPosition: MapKit.MapCameraPosition = .automatic
    public var lastUserLocation: CLLocation?
    
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
            
            // Erzwinge die Verarbeitung direkt auf dem MainActor
            Task { @MainActor in
                do {
                    let parsedStation = try ASN1Decoder.decodeV2X(from: rawBytes)
                    
                    // Entferne ein älteres Paket derselben StationID, falls vorhanden
                    self.stations.removeAll(where: { $0.stationID == parsedStation.stationID })
                    
                    // Füge das frische V2X-Objekt dem Array hinzu
                    self.stations.append(parsedStation)
                    
                    if self.isTrackingUserLocation {
                        self.triggerDynamicAutoZoom()
                    }
                } catch {
                    self.logger.error("C-ITS Decoder-Fehler: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startLifecycleTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let now = Date()
                // Timeout-Müllabfuhr: Löscht Stationen, die länger als 8 Sek. stumm sind
                self.stations.removeAll(where: { now.timeIntervalSince($0.lastUpdatedAt) > 8.0 })
            }
        }
    }
    
    public func triggerDynamicAutoZoom() {
        guard let userCoord = lastUserLocation?.coordinate else { return }
        var targetMeters: CLLocationDistance = 350.0
        
        if let closestStation = stations.first {
            let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
            let stationLoc = CLLocation(latitude: closestStation.coordinate.latitude, longitude: closestStation.coordinate.longitude)
            let distance = userLoc.distance(from: stationLoc)
            
            if distance > 100 && distance < 1500 {
                targetMeters = distance * 2.2
            }
        }
        
        let mapRegion = MKCoordinateRegion(
            center: userCoord,
            latitudinalMeters: targetMeters,
            longitudinalMeters: targetMeters
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
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
        logger.error("GPS Fehler: \(error.localizedDescription)")
    }
}
