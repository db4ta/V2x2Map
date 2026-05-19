//
//  USBManager.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import Observation
import CoreLocation
import MapKit

@Observable
public final class USBManager: @unchecked Sendable {
    
    public struct LogEntry: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let text: String
        public let type: LogType
    }
    
    public enum LogType: Sendable { case info, rx, error }
    
    public var usbIsConnected: Bool = false
    public var usbIsEnabled: Bool = false
    public var bleIsConnected: Bool = false
    public var bleIsEnabled: Bool = false
    
    // Labor-Simulation: Schalter-Kopplung
    public var isSimulationEnabled: Bool = false {
        didSet {
            if isSimulationEnabled { startLabSimulation() }
            else { stopLabSimulation() }
        }
    }
    
    public private(set) var debugLog: [USBManager.LogEntry] = []
    public private(set) var packetCount: UInt64 = 0
    public var discoveredBLEDevices: [BLEDevice] = []
    
    public let usbReceiver: USBReceiver
    public let bleReceiver: BLEReceiver
    private let lock = NSLock()
    private let maxLogLines = 40
    private var lastUIUpdateTime: Date = Date.distantPast
    private var simulationTimer: Timer? = nil
    private var pendingLogText: String? = nil
    
    private struct SimulatedCITSVehicle {
        let stationID: UInt32
        let btpPort: UInt16
        var latOffset: Double
        var lonOffset: Double
        var speedMPS: Double
        var headingDeg: Double
    }
    private var simVehicles: [SimulatedCITSVehicle] = []
    
    public init(usbReceiver: USBReceiver, bleReceiver: BLEReceiver) {
        self.usbReceiver = usbReceiver
        self.bleReceiver = bleReceiver
        
        self.bleReceiver.onDataReceived = { [weak self] data in self?.logIncomingData(data, source: "BLE") }
        self.bleReceiver.onDevicesUpdated = { [weak self] devices in Task { @MainActor in self?.discoveredBLEDevices = devices } }
        self.bleReceiver.onLogUpdated = { [weak self] logLine in Task { @MainActor in self?.logDebug(logLine, type: .info) } }
        self.bleReceiver.onConnectionStateChanged = { [weak self] name in
            Task { @MainActor in
                self?.bleIsConnected = (name != nil)
                if name == nil { self?.discoveredBLEDevices.removeAll() }
            }
        }
    }
    
    private func startLabSimulation() {
        logDebug("🕹️ Konformitäts-Simulator aktiv. Sende ETSI GeoNet-Frames...", type: .info)
        
        // KORREKTUR: Nutzt den echten, im Simulator aktiven Standort, um Anzeigefehler zu vermeiden
        let locManager = CLLocationManager()
        let currentCenterLat = locManager.location?.coordinate.latitude ?? 48.7758
        let currentCenterLon = locManager.location?.coordinate.longitude ?? 9.1829
        
        // Initialisiere stochastische Start-Offsets im 1km-Radius um den Sichtbereich des iPhones
        simVehicles = [
            SimulatedCITSVehicle(stationID: 4422, btpPort: 2001, latOffset: Double.random(in: -300...300), lonOffset: Double.random(in: -300...300), speedMPS: 14.1, headingDeg: 90.0), // CAM Auto
            SimulatedCITSVehicle(stationID: 8833, btpPort: 2002, latOffset: 150.0, lonOffset: 150.0, speedMPS: 0.0, headingDeg: 0.0) // DENM Ampel
        ]
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let metersPerDegreeLat = 111132.92
            let metersPerDegreeLon = 111319.49 * cos(currentCenterLat * .pi / 180.0)
            
            for i in 0..<self.simVehicles.count {
                var vehicle = self.simVehicles[i]
                
                if vehicle.speedMPS > 0 {
                    vehicle.lonOffset += vehicle.speedMPS
                    if abs(vehicle.lonOffset) > 800 { vehicle.lonOffset = -800 } // Begrenzung auf Sichtbereich
                    self.simVehicles[i] = vehicle
                }
                
                let finalLat = currentCenterLat + (vehicle.latOffset / metersPerDegreeLat)
                let finalLon = currentCenterLon + (vehicle.lonOffset / metersPerDegreeLon)
                
                // Formation eines echten opentrafficmap BTP-A Frames
                var frame = Data()
                frame.append(Data(repeating: 0x00, count: 20)) // GeoNet Header
                
                var portBytes = vehicle.btpPort.bigEndian
                frame.append(Data(bytes: &portBytes, count: 2)) // BTP Port
                frame.append(Data(repeating: 0x00, count: 2)) // Extended Header
                
                var vID = vehicle.stationID.bigEndian
                frame.append(Data(bytes: &vID, count: 4)) // StationID
                
                var latBytes = Int32(finalLat * 10_000_000.0).bigEndian
                frame.append(Data(bytes: &latBytes, count: 4))
                var lonBytes = Int32(finalLon * 10_000_000.0).bigEndian
                frame.append(Data(bytes: &lonBytes, count: 4))
                
                var speedBytes = UInt16(vehicle.speedMPS * 10.0).bigEndian
                frame.append(Data(bytes: &speedBytes, count: 2))
                var headingBytes = UInt16(vehicle.headingDeg * 10.0).bigEndian
                frame.append(Data(bytes: &headingBytes, count: 2))
                
                let tlvPacket = self.wrapInTLV(payload: frame)
                self.bleReceiver.onDataReceived?(tlvPacket)
            }
        }
    }
    
    private func stopLabSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        simVehicles.removeAll()
        logDebug("🕹️ Simulator gestoppt.", type: .info)
    }
    
    private func wrapInTLV(payload: Data) -> Data {
        var packet = Data()
        packet.append(0x02)
        var lenBytes: UInt16 = UInt16(payload.count).bigEndian
        packet.append(Data(bytes: &lenBytes, count: 2))
        packet.append(payload)
        return packet
    }
    
    @MainActor public func toggleUsbConnection(to enabled: Bool) async {
        lock.lock(); self.usbIsEnabled = enabled; lock.unlock()
        if enabled {
            logDebug("Scanne USB-Bus nach ESP32-C5...", type: .info)
            usbReceiver.startListening()
            try? await Task.sleep(nanoseconds: 200_000_000)
            lock.lock(); self.usbIsConnected = usbReceiver.checkConnectionStatus(); let connected = self.usbIsConnected; lock.unlock()
            if connected { logDebug("USB-Schnittstelle geöffnet.", type: .info) }
            else { logDebug("[WARNUNG]: Hardware nicht gefunden.", type: .error) }
        } else {
            usbReceiver.stopListening(); lock.lock(); self.usbIsConnected = false; lock.unlock()
            logDebug("USB-Schnittstelle geschlossen.", type: .info)
        }
    }
    
    @MainActor public func toggleBleConnection(to enabled: Bool) async {
        lock.lock(); self.bleIsEnabled = enabled; lock.unlock()
        if enabled { logDebug("Bluetooth LE Scan gestartet.", type: .info); bleReceiver.startListening() }
        else { bleReceiver.stopListening(); lock.lock(); self.bleIsConnected = false; self.discoveredBLEDevices.removeAll(); lock.unlock(); logDebug("BLE gestoppt.", type: .info) }
    }
    
    public func logIncomingData(_ data: Data, source: String) {
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "[\(timestamp)] \(source) -> \(hexString.prefix(24))..."
        lock.lock(); self.packetCount += 1; let currentPacketCount = self.packetCount; let now = Date()
        if now.timeIntervalSince(lastUIUpdateTime) < 0.1 { pendingLogText = logLine; lock.unlock(); Task { @MainActor in self.packetCount = currentPacketCount }; return }
        self.lastUIUpdateTime = now; self.pendingLogText = nil; lock.unlock()
        Task { @MainActor in
            lock.lock()
            if source == "USB" { self.usbIsConnected = true }
            if source == "BLE" { self.bleIsConnected = true }
            self.debugLog.append(USBManager.LogEntry(text: logLine, type: .rx))
            if self.debugLog.count > maxLogLines { self.debugLog.removeFirst() }
            lock.unlock()
        }
    }
    
    @MainActor public func runHardwarePingTest() {
        logDebug("👉 Starte Leitungs-Diagnose...", type: .info)
        logDebug(usbIsConnected ? "✅ USB: Aktiv" : "❌ USB: Getrennt", type: usbIsConnected ? .info : .error)
        logDebug(bleIsConnected ? "✅ BLE: Gekoppelt" : "❌ BLE: Getrennt", type: bleIsConnected ? .info : .error)
    }
    
    @MainActor public func clearLog() { lock.lock(); debugLog.removeAll(); packetCount = 0; lock.unlock() }
    @MainActor public func logDebug(_ text: String, type: USBManager.LogType) { lock.lock(); debugLog.append(USBManager.LogEntry(text: text, type: type)); lock.unlock() }
}
