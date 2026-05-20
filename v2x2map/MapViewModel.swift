//
//  MapViewModel.swift
//  v2x2map
//
//  Created for iOS 26.
//  Zentraler Observable-Datenverteiler für C-ITS Telemetrie, Simulator- und Parameter-Updates.
//

import Foundation
import CoreLocation
import Observation
import MapKit
import SwiftUI

@Observable
@MainActor
final class MapViewModel: BLEManagerDelegate {
    // UI-relevante Zustände für Kartendarstellung
    var isConnected: Bool = false
    var citsNodes: [UInt32: CITSNode] = [:]
    var mapPosition: MapKit.MapCameraPosition = .automatic
    
    // Globale Parameter gekoppelt an deine Einstellungsmenüs
    var isDebugModeEnabled: Bool = false
    var selectedMapStyle: Int = 0       // 0: Standard, 1: Satellit, 2: Hybrid
    var showTrafficOnMap: Bool = true
    
    // Live-Register für das Debug-Terminal
    var debugLogs: [String] = []
    
    var isSimulatorEnabled: Bool = false {
        didSet {
            if isSimulatorEnabled { startSimulation() } else { stopSimulation() }
        }
    }
    
    private let bleManager = BLEManager()
    private var simulationTimer: Timer?
    
    init() {
        bleManager.delegate = self
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
        logMessage(connected ? "GATT-Server erfolgreich gekoppelt." : "Verbindung zum GATT-Server getrennt.")
    }
    
    func bleManager(_ manager: BLEManager, didLogDebugMessage message: String) {
        logMessage(message)
    }
    
    func bleManager(_ manager: BLEManager, didAssembleCITSFrame frame: Data) {
        guard frame.count >= 15 else { return }
        
        let type = Int(frame[0])
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
        if self.debugLogs.count > 100 { self.debugLogs.removeLast() }
    }
    
    private func processIncomingNode(id: UInt32, lat: Double, lon: Double, speed: Double, type: Int) {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let updatedNode = CITSNode(id: id, coordinate: coordinate, speedKmH: speed, timestamp: Date(), stationType: type)
        
        self.citsNodes[id] = updatedNode
        
        SwiftUI.withAnimation(.easeInOut(duration: 0.2)) {
            let region = MapKit.MKCoordinateRegion(
                center: coordinate,
                span: MapKit.MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            )
            self.mapPosition = MapKit.MapCameraPosition.region(region)
        }
    }
    
    private func startSimulation() {
        stopSimulation()
        isConnected = true
        var baseLat = 52.520008
        var baseLon = 13.404954
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                baseLat += Double.random(in: -0.0002...0.0002)
                baseLon += Double.random(in: -0.0002...0.0002)
                let speed = Double.random(in: 25.0...65.0)
                
                self.logMessage("SIM-OUT: CAM-Frame generiert für RSU-ID 0x000F41A2")
                self.processIncomingNode(id: 0x000F41A2, lat: baseLat, lon: baseLon, speed: speed, type: 1)
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
