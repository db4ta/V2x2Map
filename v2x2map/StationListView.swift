//
//  StationListView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Erhaltene Listenansicht für C-ITS Stationen, fehlerfrei an citsNodes angebunden.
//

import SwiftUI
import CoreLocation

struct StationListView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        NavigationStack {
            // Sortiertes Array deiner aktiven Hardwareknoten erzeugen (Neueste zuerst)
            let activeNodes = Array(viewModel.citsNodes.values).sorted(by: { $0.timestamp > $1.timestamp })
            
            Group {
                if activeNodes.isEmpty {
                    // Abwärtskompatibles Empty-State-Design ohne iOS 17 Abhängigkeiten
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Keine V2X-Signale")
                            .font(.title2)
                            .bold()
                        
                        Text("Verbinde dich mit dem OpenTrafficMap-Empfänger, um Live-Verkehrstelemetrie zu scannen.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // MARK: - LISTVIEW MIT DIREKTER ANBINDUNG AN DIE NEUE DATENQUELLE
                    List(activeNodes) { node in
                        HStack(spacing: 16) {
                            // Linkes Icon-Badge (Ampel / Fahrzeug)
                            ZStack {
                                Circle()
                                    .fill(node.stationType == 2 ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: node.stationType == 2 ? "lightrail.lamp.fill" : "car.radio.2")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(node.stationType == 2 ? .red : .blue)
                            }
                            
                            // Mittlere Textblock-Informationen
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.stationType == 2 ? "C-ITS Ampel (R-IVW)" : "C-ITS Fahrzeug (CAM)")
                                    .font(.headline)
                                
                                Text(String(format: "Station-ID: 0x%08X", node.id))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                // Debug-Zusatzzeile: Koordinaten-Anzeige
                                Text(String(format: "Lat: %.5f, Lon: %.5f", node.coordinate.latitude, node.coordinate.longitude))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Rechte Status- und Geschwindigkeitsanzeige
                            if node.stationType != 2 {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(String(format: "%.1f", node.speedKmH)) km/h")
                                        .font(.system(.title3, design: .rounded))
                                        .bold()
                                    
                                    Text("Live")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                            } else {
                                Text("Signal")
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.secondarySystemFill))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("C-ITS Stationen")
            .toolbar {
                ToolbarItem(placement: .status) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isConnected ? "Hardware Aktiv" : "Suche...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    StationListView()
        .environment(MapViewModel())
}
