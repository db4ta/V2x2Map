//
//  MapViewModel.swift
//  v2x2map
//
//  Created for iOS 26.
//  Zentraler reaktiver Zustandshüter mit iPhone-GPS-Kopplung und Kompass-Ausrichtung.
//

import Foundation
import CoreLocation
import Observation
import MapKit
import SwiftUI

@Observable
@MainActor
final class MapViewModel: NSObject, BLEManagerDelegate, CLLocationManagerDelegate {
    // UI Zustände
    var isConnected: Bool = false
    var citsNodes: [UInt32: CITSNode] = [:]
    
    // Gültige, plattformstabile Standard-Kamera für SwiftUI MapKit
    var mapPosition: MapKit.MapCameraPosition = MapKit.MapCameraPosition.userLocation(fallback: .automatic)
    
    var mapInteractionIsActive: Bool = false // Verhindert den Zoom-Lock
    var currentHeading: Double = 0.0          // Für Kompass-Ausrichtung
    
    // Parameter
    var isDebugModeEnabled: Bool = false
    var selectedMapStyle: Int = 0
    var showTrafficOnMap: Bool = true
    var debugLogs: [String] = []
    
    var isSimulatorEnabled: Bool = false {
        didSet {
            if isSimulatorEnabled { startSimulation() } else { stopSimulation() }
        }
    }
    
    private let bleManager = BLEManager()
    private var simulationTimer: Timer?
    private let locationManager = CLLocationManager()
    private var lastKnownGPSLocation: CLLocation?
    
    override init() {
        super.init()
        bleManager.delegate = self
        
        // GPS & Kompass-Infrastruktur initialisieren
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func initiateBluetoothSubsystem() {
        bleManager.startScanning()
    }
    
    func triggerManualScan() {
        bleManager.startScanning()
    }
    
    // MARK: - BLEManagerDelegate
    func bleManager(_ manager: BLEManager, didUpdateConnectionStatus connected: Bool) {
        self.isConnected = connected
        logMessage(connected ? "Kanal zu ITS-G5-RX offen." : "Kanal zu ITS-G5-RX getrennt.")
    }
    
    func bleManager(_ manager: BLEManager, didLogDebugMessage message: String) {
        logMessage(message)
    }
    
    func bleManager(_ manager: BLEManager, didAssembleCITSFrame frame: Data) {
        // Mindestgröße prüfen: 1 Byte Typ + 4 Bytes ID + 4 Bytes Lat + 4 Bytes Lon + 2 Bytes Speed = 15 Bytes
        guard frame.count >= 15 else { return }
        
        guard let firstByte = frame.first else { return }
        let type = Int(firstByte)
        
        let stationID = frame.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let latRaw = frame.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let lonRaw = frame.subdata(in: 9..<13).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
        let speedRaw = frame.subdata(in: 13..<15).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        let latitude = Double(latRaw) / 10000000.0
        let longitude = Double(lonRaw) / 10000000.0
        let speedKmH = (Double(speedRaw) * 0.01) * 3.6
        
        processIncomingNode(id: stationID, lat: latitude, lon: longitude, speed: speedKmH, type: type)
    }
    
    private func logMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.debugLogs.insert("[\(timestamp)] \(message)", at: 0)
        if self.debugLogs.count > 40 { self.debugLogs.removeLast() }
    }
    
    private func processIncomingNode(id: UInt32, lat: Double, lon: Double, speed: Double, type: Int) {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        // Kompiliert jetzt dank sauberer Typableitung fehlerfrei
        self.citsNodes[id] = CITSNode(
            id: id,
            coordinate: coordinate,
            speedKmH: speed,
            timestamp: Date(),
            stationType: type
        )
        
        // Kamera zoomt nur automatisch nach, wenn der Nutzer die Karte NICHT aktiv verschiebt (Lösen des Zoom-Locks)
        if !mapInteractionIsActive {
            SwiftUI.withAnimation(.easeInOut(duration: 0.3)) {
                let region = MapKit.MKCoordinateRegion(
                    center: coordinate,
                    span: MapKit.MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                )
                // Kompiliert jetzt ebenfalls einwandfrei im Macro-Scope
                self.mapPosition = MapKit.MapCameraPosition.region(region)
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate (Echtes GPS & Kompass)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.lastKnownGPSLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            self.currentHeading = newHeading.magneticHeading
        }
    }
    
    // MARK: - GPS-gekoppelter Simulator (RSU / OBU um dich herum)
    private func startSimulation() {
        stopSimulation()
        isConnected = true
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let gps = self.lastKnownGPSLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 52.52, longitude: 13.40)
                
                let simLat = gps.latitude + Double.random(in: -0.0006...0.0006)
                let simLon = gps.longitude + Double.random(in: -0.0006...0.0006)
                let speed = Double.random(in: 35.0...55.0)
                
                self.logMessage("SIM-OUT: Live-GPS CAM Frame generiert für ID 0x00E2")
                self.processIncomingNode(id: 0x00E2, lat: simLat, lon: simLon, speed: speed, type: 1)
            }
        }
    }
    
    private func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        if !isSimulatorEnabled {
            citsNodes.removeAll()
            isConnected = false
        }
    }
}

