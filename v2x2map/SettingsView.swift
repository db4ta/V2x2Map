//
//  SettingsView.swift
//  v2x2map
//
//  Created for iOS 26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(USBManager.self) private var usbManager
    
    @State private var showVehicles = AppConfig.Filters.showVehicles
    @State private var showRSUs = AppConfig.Filters.showRoadsideUnits
    
    // Reglerzustand für das Zeit-X-Limit
    @State private var alertMinutes: Double = AppConfig.StationLifecycle.alertThresholdMinutes
    
    var body: some View {
        @Bindable var bindableManager = usbManager
        
        NavigationStack {
            Form {
                // Sektion zur Konfiguration der Zeit-X-Überwachung
                Section(
                    header: Text("Dauerüberwachung (Zeit X)"),
                    footer: Text("Objekte, die ununterbrochen länger als das eingestellte Limit empfangen werden, erhalten ein rotes Ausrufezeichen.")
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Hervorheben ab:")
                            Spacer()
                            Text(String(format: "%.1f Min.", alertMinutes))
                                .bold()
                                .foregroundColor(.red)
                        }
                        // Slider von 0.5 Minuten (30s) bis 10 Minuten einstellbar
                        Slider(value: $alertMinutes, in: 0.5...10.0, step: 0.5) {
                            Text("Dauer")
                        }
                        .onChange(of: alertMinutes) {
                            // Schreibt den veränderten Wert direkt in den globalen App-Status
                            AppConfig.StationLifecycle.alertThresholdMinutes = alertMinutes
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Sektion: Labor- & Simulationsmodus
                Section(header: Text("Labor- & Simulationsmodus")) {
                    Toggle(isOn: $bindableManager.isSimulationEnabled) {
                        HStack {
                            Image(systemName: "flask.fill").foregroundColor(usbManager.isSimulationEnabled ? .purple : .gray)
                            Text("GPS-Testdaten generieren")
                        }
                    }.tint(.purple)
                }
                
                // Sektion: USB-Kabel-Steuerung
                Section(header: Text("Hardware-Verbindung (USB-C Kabel)")) {
                    Toggle(isOn: Binding(
                        get: { usbManager.usbIsEnabled },
                        set: { newValue in Task { await usbManager.toggleUsbConnection(to: newValue) } }
                    )) {
                        HStack {
                            Image(systemName: "cable.connector").foregroundColor(usbManager.usbIsConnected ? .green : .gray)
                            Text("USB-C Verbindung aktivieren")
                        }
                    }
                    HStack {
                        Text("USB Status")
                        Spacer()
                        Text(usbManager.usbIsConnected ? "Verbunden (CDC-ACM)" : (usbManager.usbIsEnabled ? "Suche Kabel..." : "Deaktiviert"))
                            .foregroundColor(usbManager.usbIsConnected ? .green : (usbManager.usbIsEnabled ? .orange : .secondary))
                    }
                }
                
                // Sektion: Bluetooth-Funk-Steuerung
                Section(header: Text("Drahtlose Verbindung (Bluetooth LE)")) {
                    Toggle(isOn: Binding(
                        get: { usbManager.bleIsEnabled },
                        set: { newValue in Task { await usbManager.toggleBleConnection(to: newValue) } }
                    )) {
                        HStack {
                            Image(systemName: "bluetooth").foregroundColor(usbManager.bleIsConnected ? .blue : .gray)
                            Text("Bluetooth LE aktivieren")
                        }
                    }
                    HStack {
                        Text("Bluetooth Status")
                        Spacer()
                        Text(usbManager.bleIsConnected ? "Gekoppelt (BLE Stream)" : (usbManager.bleIsEnabled ? "Scanne Funk..." : "Deaktiviert"))
                            .foregroundColor(usbManager.bleIsConnected ? .blue : (usbManager.bleIsEnabled ? .orange : .secondary))
                    }
                }
                
                // Sektion: Diagnosetools & Live Terminal
                Section(header: Text("Daten-Monitor & System-Diagnose")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            // BEHOBEN: Saubere und standardkonforme Button-Syntax ohne verschachtelten body-Aufruf
                            Button(action: {
                                usbManager.runHardwarePingTest()
                            }) {
                                HStack {
                                    Image(systemName: "waveform.path.ecg")
                                    Text("System prüfen")
                                }
                            }
                            .font(.caption).bold().padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.blue.opacity(0.15)).cornerRadius(4)
                            
                            Spacer()
                            
                            Button("Log leeren") { usbManager.clearLog() }.font(.caption)
                        }
                        
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if usbManager.debugLog.isEmpty {
                                        Text("Warte auf Schnittstellen-Aktivierung...")
                                            .font(.system(.caption, design: .monospaced)).foregroundColor(.gray)
                                    } else {
                                        ForEach(usbManager.debugLog) { entry in
                                            Text(entry.text)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(entry.type == .error ? .red : (entry.type == .info ? .cyan : .green))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .frame(height: 180).padding(6).background(Color(white: 0.08)).cornerRadius(6)
                            .onChange(of: usbManager.debugLog.count) {
                                if let last = usbManager.debugLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Karten-Optionen")) {
                    Toggle("Fahrzeuge anzeigen", isOn: $showVehicles)
                    Toggle("RSUs (Infrastruktur) anzeigen", isOn: $showRSUs)
                }
            }
            .navigationTitle("Optionen & Hardware")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
    }
}
