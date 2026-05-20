//
//  SettingsView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Zentrales Einstellungsmenü aufgeteilt in übersichtliche Untermenüs.
//

import SwiftUI

struct SettingsView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Sektion 1: V2X & Funk-Parameter
                Section(header: Text("Hardware & Verbindung")) {
                    NavigationLink {
                        WirelessSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Funk-Einstellungen (BLE)")
                                    .font(.body)
                                Text(viewModel.isConnected ? "ESP32-C5 Online" : "Suche GATT-Server...")
                                    .font(.caption)
                                    .foregroundColor(viewModel.isConnected ? .green : .orange)
                            }
                        }
                    }
                }
                
                // MARK: - Sektion 2: Karten-Präferenzen
                Section(header: Text("Anzeige-Optionen")) {
                    NavigationLink {
                        V2XMapSettingsSubView()
                    } label: {
                        // KORREKTUR: Ersetzt durch stabiles, abwärtskompatibles HStack-Layout (Behebt Zeile 44 Initialisierungsfehler)
                        HStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .foregroundColor(.primary)
                                .frame(width: 24)
                            Text("Karteneinstellungen")
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                // MARK: - Sektion 3: Entwicklerwerkzeuge
                Section(header: Text("Labor & Analyse")) {
                    NavigationLink {
                        DebugSettingsSubView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "terminal.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            
                            HStack {
                                Text("Entwickler / Debug")
                                Spacer()
                                if viewModel.isSimulatorEnabled {
                                    Text("SIM AKTIV")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Sektion 4: System-Informationen
                Section(header: Text("System")) {
                    HStack {
                        // KORREKTUR: Bereinigung aller restlichen Label-Instanzen zu HStack
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Architektur")
                        }
                        Spacer()
                        Text("OpenTrafficMap G5")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("App-Version")
                        }
                        Spacer()
                        Text("1.0.0 (Build 26)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Einstellungen")
        }
    }
}

#Preview {
    SettingsView()
        .environment(MapViewModel())
}
