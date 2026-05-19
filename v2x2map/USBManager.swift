//
//  USBManager.swift
//  v2x2map
//
//  Created for iOS 26.
//

import Foundation
import Observation

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
    
    public var isSimulationEnabled: Bool = false
    
    public private(set) var debugLog: [LogEntry] = []
    public private(set) var packetCount: UInt64 = 0
    
    // NEU: Veröffentlichter Zustand gefundener Geräte direkt im Hardware-Zustandshüter
    public var discoveredBLEDevices: [BLEDevice] = []
    
    public let usbReceiver: USBReceiver
    public let bleReceiver: BLEReceiver
    private let lock = NSLock()
    private let maxLogLines = 50
    
    public init(usbReceiver: USBReceiver, bleReceiver: BLEReceiver) {
        self.usbReceiver = usbReceiver
        self.bleReceiver = bleReceiver
        
        // KORREKTUR: Datenbrücke fängt nun die Live-Bytes vom transparenten C-ITS Modem ab
        self.bleReceiver.onDataReceived = { [weak self] data in
            self?.logIncomingData(data, source: "BLE")
        }
        
        // KORREKTUR: Synchronisierung der Bluetooth-Ereignisse direkt mit dem DebugLog des Managers
        self.bleReceiver.onDevicesUpdated = { [weak self] devices in
            Task { @MainActor in self?.discoveredBLEDevices = devices }
        }
        
        self.bleReceiver.onLogUpdated = { [weak self] logLine in
            Task { @MainActor in self?.logDebug(logLine, type: .info) }
        }
        
        self.bleReceiver.onConnectionStateChanged = { [weak self] name in
            Task { @MainActor in
                self?.bleIsConnected = (name != nil)
                if let deviceName = name {
                    self?.logDebug("Modem-Zustand: Verbunden mit \(deviceName)", type: .info)
                } else {
                    self?.logDebug("Modem-Zustand: Getrennt", type: .error)
                }
            }
        }
    }
    
    @MainActor
    public func toggleUsbConnection(to enabled: Bool) async {
        lock.lock()
        self.usbIsEnabled = enabled
        lock.unlock()
        
        if enabled {
            logDebug("Scanne USB-Bus nach ESP32-C5 (CDC-ACM)...", type: .info)
            usbReceiver.startListening()
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            lock.lock()
            self.usbIsConnected = usbReceiver.checkConnectionStatus()
            let connected = self.usbIsConnected
            lock.unlock()
            
            if connected {
                logDebug("USB-Schnittstelle geöffnet. Warte auf V2X-Kabeldaten...", type: .info)
            } else {
                logDebug("[WARNUNG]: USB-CDC Gerät blockiert oder nicht gefunden.", type: .error)
            }
        } else {
            usbReceiver.stopListening()
            lock.lock()
            self.usbIsConnected = false
            lock.unlock()
            logDebug("USB-Schnittstelle manuell geschlossen.", type: .info)
        }
    }
    
    @MainActor
    public func toggleBleConnection(to enabled: Bool) async {
        lock.lock()
        self.bleIsEnabled = enabled
        lock.unlock()
        
        if enabled {
            logDebug("Bluetooth LE Scan gestartet. Suche ESP32 Peripheral...", type: .info)
            bleReceiver.startListening()
        } else {
            bleReceiver.stopListening()
            lock.lock()
            self.bleIsConnected = false
            self.discoveredBLEDevices.removeAll()
            lock.unlock()
            logDebug("Bluetooth LE Funkverbindung manuell gestoppt.", type: .info)
        }
    }
    
    public func logIncomingData(_ data: Data, source: String) {
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "[\(timestamp)] \(source) -> \(hexString.prefix(36))..."
        
        Task { @MainActor in
            lock.lock()
            self.packetCount += 1
            if source == "USB" { self.usbIsConnected = true }
            if source == "BLE" { self.bleIsConnected = true }
            
            self.debugLog.append(LogEntry(text: logLine, type: .rx))
            if self.debugLog.count > maxLogLines {
                self.debugLog.removeFirst()
            }
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
        lock.lock()
        debugLog.removeAll()
        packetCount = 0
        lock.unlock()
    }
    
    @MainActor
    public func logDebug(_ text: String, type: LogEntry.LogType) {
        lock.lock()
        debugLog.append(LogEntry(text: text, type: type))
        lock.unlock()
    }
}
