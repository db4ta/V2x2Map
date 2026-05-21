//
//  WirelessSettingsView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Untermenü für die manuelle GATT-Server-Suche des ESP32-C5.
//

import SwiftUI
import Combine // Garantiert saubere Auflösung von ObservableObject-Referenzen in SwiftUI-Views

struct WirelessSettingsView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        List {
            // MARK: - Sektion 1: Manuelle GATT-Server-Suche
            Section(header: Text("GATT-Server Hardware-Suche")) {
                HStack {
                    Text("Verbindungsstatus")
                    Spacer()
                    Text(viewModel.isConnected ? "VERBUNDEN" : "TRENNT / SCANNT")
                        .bold()
                        .foregroundColor(viewModel.isConnected ? .green : .orange)
                }
                
                Button(action: {
                    viewModel.triggerManualScan()
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Nach OpenTrafficMap-Knoten scannen")
                            .bold()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isConnected)
            }
            
            // MARK: - Sektion 2: Schnittstellenkonfiguration
            Section(header: Text("Schnittstellen-Info"), footer: Text("Der ESP32-C5 fungiert als Co-Prozessor im 5-GHz-Band und streamt die Datenpakete via BLE-Notify.")) {
                HStack {
                    Text("Übertragungsmodus")
                    Spacer()
                    Text("Asynchrones Push-Verfahren")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("MTU-Größe")
                    Spacer()
                    Text("Maximiert (512 Bytes)")
                        .foregroundColor(.secondary)
                }
            }
            
            // MARK: - Sektion 3: Coexistenz-Steuerung (COEX)
            Section(header: Text("Hardware-Steuerung")) {
                CoexSettingsView(commandManager: V2xCommandManager.shared)
                    .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Funk-Einstellungen")
    }
}

// Visualisiertes Steuerungselement laut Spezifikation
struct CoexSettingsView: View {
    @ObservedObject var commandManager: V2xCommandManager
    @State private var selectedMode: UInt8 = 0x00
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hardware-Koexistenz (COEX)")
                .font(.headline)
            
            Picker("Prioritätsmodus", selection: $selectedMode) {
                Text("Ausgeglichen").tag(UInt8(0x00))
                Text("V2X-Fokus (Hohe Last)").tag(UInt8(0x01))
                Text("Bluetooth-Stabilität").tag(UInt8(0x02))
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedMode) { _, newMode in
                // Ruft deinen Command-Manager mit der neuen iOS 17-Signatur auf
                commandManager.sendCoexCommand(mode: newMode)
            }
            
            Text("Hinweis: Der V2X-Fokus kann bei hoher Kanallast zu kurzzeitigen Verbindungsabbrüchen unter iOS führen.")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    NavigationStack {
        WirelessSettingsView()
            .environment(MapViewModel())
    }
}
