//
//  WirelessSettingsView.swift
//  v2x2map
//
//  Created for iOS 26.
//

import SwiftUI
import CoreBluetooth

struct WirelessSettingsView: View {
    @Environment(MapViewModel.self) private var viewModel
    @Bindable var usbManager: USBManager
    
    // Parametrisierungs-Zustände
    @State private var isAutoScanEnabled: Bool = true
    @State private var scanInterval: Int = 5
    @State private var topNDevices: Int = 5
    @State private var isAutoReconnectEnabled: Bool = true
    @State private var nameFilter: String = ""
    
    var body: some View {
        Form {
            // Sektion 1: Scan-Parameter
            Section(header: Text("📡 Scan-Einstellungen & Filter")) {
                Toggle(isOn: Binding(
                    get: { isAutoScanEnabled },
                    set: { newValue in
                        isAutoScanEnabled = newValue
                        Task { await usbManager.toggleBleConnection(to: newValue) }
                    }
                )) {
                    Label("Automatischer Scan", systemImage: "antenna.radiowaves.left.and.right")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Scan-Intervall")
                        Spacer()
                        Text("\(scanInterval) Sek.")
                            .bold()
                            .foregroundColor(.cyan)
                    }
                    Slider(value: Binding(
                        get: { Double(scanInterval) },
                        set: { scanInterval = Int($0) }
                    ), in: 1.0...30.0, step: 1.0)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Top-N Geräte anzeigen")
                        Spacer()
                        Text("\(topNDevices)")
                            .bold()
                            .foregroundColor(.cyan)
                    }
                    Slider(value: Binding(
                        get: { Double(topNDevices) },
                        set: { topNDevices = Int($0) }
                    ), in: 1.0...10.0, step: 1.0)
                }
                
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.gray)
                    TextField("Optionaler Namensfilter (z. B. ITS-G5-RX)", text: $nameFilter)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                
                Button(action: {
                    Task {
                        await usbManager.toggleBleConnection(to: false)
                        await usbManager.toggleBleConnection(to: true)
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                        Text("Jetzt manuell aktualisieren")
                        Spacer()
                    }
                }
                .disabled(!isAutoScanEnabled)
            }
            
            // Sektion 2: Erkanntes Hardware-Spektrum (Gefundene Modems)
            Section(header: Text("📱 Gefundene C-ITS Modems (Sortiert nach RSSI)")) {
                let discovered = usbManager.discoveredBLEDevices
                let filtered = discovered.filter { device in
                    nameFilter.isEmpty ||
                    device.name.localizedCaseInsensitiveContains(nameFilter) ||
                    device.name.contains("V2X") ||
                    device.name.contains("Unbekanntes")
                }
                let sortedAndLimited = Array(filtered.sorted(by: { $0.rssi > $1.rssi }).prefix(topNDevices))
                
                if !usbManager.bleIsEnabled {
                    Text("Schalte den Empfänger oben ein, um den BLE-Scan zu starten.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else if sortedAndLimited.isEmpty {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Scanne Hardware-Umfeld nach C-ITS Sendern...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    // KORREKTUR: Auslagerung der Schleifen-Generierung bricht den @Bindable-Zwang auf und kompiliert fehlerfrei!
                    List {
                        ForEach(sortedAndLimited) { device in
                            DeviceRowView(device: device, usbManager: usbManager)
                        }
                    }
                }
            }
            
            // Sektion 3: Verbindung & Auto-Reconnect
            Section(header: Text("🔒 Verbindungs-Zustand")) {
                Toggle("Auto-Reconnect", isOn: $isAutoReconnectEnabled)
                
                HStack {
                    Text("Aktuelles Modem:")
                    Spacer()
                    if usbManager.bleIsConnected {
                        Text("C-ITS G5-Modem Aktiv")
                            .bold()
                            .foregroundColor(.green)
                    } else {
                        Text("Keine Verbindung")
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Sektion 4: Live C-ITS Modem-Diagnose
            Section(header: Text("🛠️ Live C-ITS Modem-Diagnose")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(usbManager.bleIsConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text("GATT-Modem-Status:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(usbManager.bleIsConnected ? "TRANSPARENT-MODE (C-ITS)" : "DISCONNECTED")
                            .font(.caption)
                            .bold()
                    }
                    
                    Divider()
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(usbManager.debugLog.suffix(20)) { entry in
                                Text(entry.text)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(entry.type == .error ? .red : (entry.type == .rx ? .cyan : .white))
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
        .navigationTitle("Drahtlos-Setup")
    }
}

// MARK: - NEU: Isolierte Read-Only Subview zur Eliminierung jeglicher Compiler-Typkonflikte
struct DeviceRowView: View {
    let device: BLEDevice
    let usbManager: USBManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(device.name.contains("Unbekanntes") ? .orange : .primary)
                Text("UUID: \(device.id.uuidString.prefix(14))...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            if usbManager.bleIsConnected {
                Button("Trennen") {
                    Task { await usbManager.toggleBleConnection(to: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Koppeln") {
                    usbManager.bleReceiver.connectToDevice(device)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
            
            HStack(spacing: 2) {
                Image(systemName: "cellularbars")
                Text("\(device.rssi)dB")
                    .font(.caption2)
            }
            .foregroundColor(device.rssi > -75 ? .green : .orange)
            .frame(width: 55)
        }
    }
}
