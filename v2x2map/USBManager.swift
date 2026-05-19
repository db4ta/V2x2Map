//
//  USBManager.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import Observation

// KORREKTUR: Explizite Definition stellt den LogEntry-Typ für alle Module bereit
public struct LogEntry: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let text: String
    public let type: LogType
    
    public enum LogType: Sendable { case info, rx, error }
}

@Observable
public final class USBManager: @unchecked Sendable {
    public var usbIsConnected: Bool = false
    public var usbIsEnabled: Bool = false
    
    public var bleIsConnected: Bool = false
    public var bleIsEnabled: Bool = false
    
    public var isSimulationEnabled: Bool = false {
        didSet {
            if isSimulationEnabled { startLabSimulation() }
            else { stopLabSimulation() }
        }
    }
    
    public private(set) var debugLog: [LogEntry] = []
    public private(set) var packetCount: UInt64 = 0
    public var discoveredBLEDevices: [BLEDevice] = []
    
    public let usbReceiver: USBReceiver
    public let bleReceiver: BLEReceiver
    private let lock = NSLock()
    private let maxLogLines = 40
    
    private var pendingLogText: String? = nil
    private var lastUIUpdateTime: Date = Date.distantPast
    
    private var simulationTimer: Timer? = nil
    private var simVehicleHeading: Double = 90.0
    private var simVehicleLat: Int32 = 48775800
    private var simVehicleLon: Int32 = 9182900
    
    public init(usbReceiver: USBReceiver, bleReceiver: BLEReceiver) {
        self.usbReceiver = usbReceiver
        self.bleReceiver = bleReceiver
        
        self.bleReceiver.onDataReceived = { [weak self] data in
            self?.logIncomingData(data, source: "BLE")
        }
        
        self.bleReceiver.onDevicesUpdated = { [weak self] devices in
            Task { @MainActor in self?.discoveredBLEDevices = devices }
        }
        
        self.bleReceiver.onLogUpdated = { [weak self] logLine in
            Task { @MainActor in self?.logDebug(logLine, type: .info) }
        }
        
        self.bleReceiver.onConnectionStateChanged = { [weak self] name in
            Task { @MainActor in
                self?.bleIsConnected = (name != nil)
                if name == nil { self?.discoveredBLEDevices.removeAll() }
            }
        }
    }
    
    private func startLabSimulation() {
        logDebug("🕹️ Labor-Simulation gestartet. Generiere Pakete...", type: .info)
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.simVehicleLon += 40
            self.simVehicleHeading = 90.0
            
            var camData = Data()
            camData.append(0x02)
            var camStationID: UInt32 = UInt32(4422).bigEndian
            camData.append(Data(bytes: &camStationID, count: 4))
            var camLatBytes = self.simVehicleLat.bigEndian
            camData.append(Data(bytes: &camLatBytes, count: 4))
            var camLonBytes = self.simVehicleLon.bigEndian
            camData.append(Data(bytes: &camLonBytes, count: 4))
            var camSpeedBytes: UInt16 = UInt16(140).bigEndian
            camData.append(Data(bytes: &camSpeedBytes, count: 2))
            var camHeadingBytes: UInt16 = UInt16(900).bigEndian
            camData.append(Data(bytes: &camHeadingBytes, count: 2))
            
            var denmData = Data()
            denmData.append(0x01)
            var denmStationID: UInt32 = UInt32(9911).bigEndian
            denmData.append(Data(bytes: &denmStationID, count: 4))
            var denmLatBytes: Int32 = Int32(48778500).bigEndian
            denmData.append(Data(bytes: &denmLatBytes, count: 4))
            var denmLonBytes: Int32 = Int32(9184500).bigEndian
            denmData.append(Data(bytes: &denmLonBytes, count: 4))
            
            let finalCamPacket = self.wrapInTLV(payload: camData)
            let finalDenmPacket = self.wrapInTLV(payload: denmData)
            
            self.bleReceiver.onDataReceived?(finalCamPacket)
            if self.packetCount % 3 == 0 {
                self.bleReceiver.onDataReceived?(finalDenmPacket)
            }
        }
    }
    
    private func stopLabSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        logDebug("🕹️ Labor-Simulation gestoppt.", type: .info)
    }
    
    private func wrapInTLV(payload: Data) -> Data {
        var packet = Data()
        packet.append(0x02)
        var lenBytes: UInt16 = UInt16(payload.count).bigEndian
        packet.append(Data(bytes: &lenBytes, count: 2))
        packet.append(payload)
        return packet
    }
    
    @MainActor
    public func toggleUsbConnection(to enabled: Bool) async {
        lock.lock(); self.usbIsEnabled = enabled; lock.unlock()
        if enabled {
            logDebug("Scanne USB-Bus nach ESP32-C5...", type: .info)
            usbReceiver.startListening()
            try? await Task.sleep(nanoseconds: 200_000_000)
            lock.lock(); self.usbIsConnected = usbReceiver.checkConnectionStatus(); let connected = self.usbIsConnected; lock.unlock()
            if connected { logDebug("USB-Schnittstelle geöffnet.", type: .info) }
            else { logDebug("[WARNUNG]: USB-CDC Gerät nicht gefunden.", type: .error) }
        } else {
            usbReceiver.stopListening(); lock.lock(); self.usbIsConnected = false; lock.unlock()
            logDebug("USB-Schnittstelle geschlossen.", type: .info)
        }
    }
    
    @MainActor
    public func toggleBleConnection(to enabled: Bool) async {
        lock.lock(); self.bleIsEnabled = enabled; lock.unlock()
        if enabled {
            logDebug("Bluetooth LE Scan gestartet.", type: .info)
            bleReceiver.startListening()
        } else {
            bleReceiver.stopListening(); lock.lock(); self.bleIsConnected = false; self.discoveredBLEDevices.removeAll(); lock.unlock()
            logDebug("Bluetooth LE Funkverbindung manuell gestoppt.", type: .info)
        }
    }
    
    public func logIncomingData(_ data: Data, source: String) {
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "[\(timestamp)] \(source) -> \(hexString.prefix(28))..."
        
        lock.lock()
        self.packetCount += 1
        let currentPacketCount = self.packetCount
        let now = Date()
        
        if now.timeIntervalSince(lastUIUpdateTime) < 0.1 {
            pendingLogText = logLine
            lock.unlock()
            Task { @MainActor in self.packetCount = currentPacketCount }
            return
        }
        
        self.lastUIUpdateTime = now
        self.pendingLogText = nil
        lock.unlock()
        
        Task { @MainActor in
            lock.lock()
            if source == "USB" { self.usbIsConnected = true }
            if source == "BLE" { self.bleIsConnected = true }
            self.debugLog.append(LogEntry(text: logLine, type: .rx))
            if self.debugLog.count > maxLogLines { self.debugLog.removeFirst() }
            lock.unlock()
        }
    }
    
    @MainActor
    public func runHardwarePingTest() {
        logDebug("👉 Starte Leitungs- und Funk-Diagnose...", type: .info)
        logDebug("Statistik: Insgesamt \(packetCount) C-ITS Pakete empfangen.", type: .info)
        logDebug(usbIsConnected ? "✅ USB-Kabel: Aktiv" : "❌ USB-Kabel: Keine Verbindung", type: usbIsConnected ? .info : .error)
        logDebug(bleIsConnected ? "✅ Bluetooth LE: Gekoppelt" : "❌ Bluetooth LE: Getrennt", type: bleIsConnected ? .info : .error)
    }
    
    @MainActor
    public func clearLog() {
        lock.lock(); debugLog.removeAll(); packetCount = 0; lock.unlock()
    }
    
    @MainActor
    public func logDebug(_ text: String, type: LogEntry.LogType) {
        lock.lock(); debugLog.append(LogEntry(text: text, type: type)); lock.unlock()
    }
}
