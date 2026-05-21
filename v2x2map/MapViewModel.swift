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
    
    // Einstellbares Inaktivitäts-Timeout für den Verbindungs-Watchdog
    var bleConnectionTimeout: Double = 5.0 {
        didSet {
            bleManager.setConnectionTimeout(bleConnectionTimeout)
        }
    }
    
    // COEX-Präferenz (0 = Balanced, 1 = Wi-Fi/V2X Priorität, 2 = BLE Priorität)
    var coexPreference: Int = 0 {
        didSet {
            let valueToByte: UInt8
            switch coexPreference {
            case 0: valueToByte = 0x00 // Balanced Mode
            case 1: valueToByte = 0x01 // Wi-Fi focus (Prefer Wi-Fi)
            case 2: valueToByte = 0x02 // BLE focus
            default: valueToByte = 0x00
            }
            // Übergabe direkt über CoreBluetooth an den ESP32-C5
            bleManager.writeCoexPriority(valueToByte)
        }
    }
    
    // Deaktiviert den Auto-Lock / Ruhezustand des iPhones für den Live-Betrieb
    var isDisplayAlwaysOn: Bool = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = isDisplayAlwaysOn
        }
    }
    
    var isSimulatorEnabled: Bool = false {
        didSet {
            if isSimulatorEnabled { startSimulation() } else { stopSimulation() }
        }
    }
    
    private let bleManager = BLEManager()
    private let udpReceiver: UDPReceiver
    private var simulationTimer: Timer?
    private let locationManager = CLLocationManager()
    private var lastKnownGPSLocation: CLLocation?
    
    private let decodingQueue = DispatchQueue(label: "com.v2x2map.decoding", qos: .userInitiated)
    
    override init() {
        // Explizite Initialisierung des UDPReceivers im MainActor-isolierten Kontext
        self.udpReceiver = UDPReceiver(port: AppConfig.Network.defaultUdpPort)
        
        super.init()
        bleManager.delegate = self
        
        // Verknüpfe den V2xCommandManager mit unserem bleManager, damit COEX-Updates über BLE laufen
        V2xCommandManager.shared.activeBLEManager = bleManager
        
        // Initialisiere Standard-Timeout im Manager
        bleManager.setConnectionTimeout(bleConnectionTimeout)
        
        // GPS & Kompass-Infrastruktur initialisieren
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        // Starte das UDP-Subsystem für Wi-Fi Telemetrie
        setupUDPReceiver()
    }
    
    func initiateBluetoothSubsystem() {
        bleManager.startScanning()
    }
    
    func triggerManualScan() {
        bleManager.startScanning()
    }
    
    private func setupUDPReceiver() {
        udpReceiver.onDataReceived = { [weak self] rawData in
            guard let self = self else { return }
            // Asynchrones Parsing komplett vom Main Thread fernhalten!
            self.decodingQueue.async {
                do {
                    let station = try ASN1Decoder.decodeV2X(from: rawData)
                    Task { @MainActor in
                        self.processDecodedStation(station)
                    }
                } catch {
                    // Fallback, falls kein vollständiges GeoNet Paket vorliegt
                    Task { @MainActor in
                        self.loggerFallbackParse(rawData)
                    }
                }
            }
        }
        
        Task {
            await udpReceiver.startListening()
        }
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
        // Zeitkritische Decodierung der BLE-Bytes im Hintergrund durchführen
        decodingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let station = try ASN1Decoder.decodeV2X(from: frame)
                Task { @MainActor in
                    self.processDecodedStation(station)
                }
            } catch {
                Task { @MainActor in
                    self.loggerFallbackParse(frame)
                }
            }
        }
    }
    
    private func logMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.debugLogs.insert("[\(timestamp)] \(message)", at: 0)
        if self.debugLogs.count > 40 { self.debugLogs.removeLast() }
    }
    
    private func processDecodedStation(_ station: MapStation) {
        let id = UInt32(station.stationID)
        let speedKmH = station.speed * 3.6 // m/s in km/h umrechnen
        let stationType = station.isHazard ? 2 : 1
        
        self.citsNodes[id] = CITSNode(
            id: id,
            coordinate: station.coordinate,
            speedKmH: speedKmH,
            timestamp: station.lastUpdatedAt,
            stationType: stationType
        )
        
        if !mapInteractionIsActive {
            SwiftUI.withAnimation(.easeInOut(duration: 0.3)) {
                let region = MapKit.MKCoordinateRegion(
                    center: station.coordinate,
                    span: MapKit.MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                )
                self.mapPosition = MapKit.MapCameraPosition.region(region)
            }
        }
    }
    
    private func loggerFallbackParse(_ frame: Data) {
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
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.citsNodes[stationID] = CITSNode(
            id: stationID,
            coordinate: coordinate,
            speedKmH: speedKmH,
            timestamp: Date(),
            stationType: type
        )
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
    
    // MARK: - GPS-gekoppelter Simulator
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
                let coordinate = CLLocationCoordinate2D(latitude: simLat, longitude: simLon)
                self.citsNodes[0x00E2] = CITSNode(
                    id: 0x00E2,
                    coordinate: coordinate,
                    speedKmH: speed,
                    timestamp: Date(),
                    stationType: 1
                )
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
