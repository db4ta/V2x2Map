//
//  WirelessSettingsView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Untermenü für die manuelle GATT-Server-Suche des ESP32-C5.
//

import SwiftUI

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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Funk-Einstellungen")
    }
}

#Preview {
    NavigationStack {
        WirelessSettingsView()
            .environment(MapViewModel())
    }
}
