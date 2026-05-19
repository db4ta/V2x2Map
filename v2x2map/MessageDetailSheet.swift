//
//  MessageDetailSheet.swift
//  v2x2map
//
//  Created for iOS 26.
//  Detaillierte Protokoll-Aufschlüsselung für selektierte V2X-Teilnehmer (CAM/DENM)
//

import SwiftUI
import CoreLocation // ZWINGEND ERFORDERLICH für .latitude und .longitude Properties

struct MessageDetailSheet: View {
    let station: MapStation
    
    @Environment(\.dismiss) private var dismiss
    
    // Nativer Deepsea-Farbwert für Konsolen-Feeling
    private let deepseaBackground = Color(red: 10/255, green: 15/255, blue: 28/255)
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Hintergrund-Styling je nach Nachrichtentyp (Rot bei Alarm, Dunkelblau bei Standard)
                if station.isHazard {
                    Color.red.opacity(0.06).ignoresSafeArea()
                } else {
                    deepseaBackground.opacity(0.02).ignoresSafeArea()
                }
                
                Form {
                    // Sektion 1: Kern-Identifikation & C-ITS Typ
                    Section(header: Text("🚨 ETSI Protokoll-Header")) {
                        HStack {
                            Text("Nachrichten-Typ:")
                            Spacer()
                            Text(station.isHazard ? "DENM (Gefahrenmeldung)" : "CAM (Fahrzeugtelegramm)")
                                .bold()
                                .foregroundColor(station.isHazard ? .red : .green)
                        }
                        
                        HStack {
                            Text("Station ID:")
                            Spacer()
                            Text("\(station.stationID)")
                                .font(.system(.body, design: .monospaced))
                                .bold()
                        }
                        
                        HStack {
                            Text("Letztes Signal:")
                            Spacer()
                            Text(station.lastUpdatedAt.formatted(date: .omitted, time: .standard))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Sektion 2: Telemetrie & Kinematik (Geschwindigkeit & Richtung)
                    Section(header: Text("🚗 Kinematische Telemetrie")) {
                        HStack {
                            Text("Geschwindigkeit:")
                            Spacer()
                            // Umrechnung von m/s in km/h (station.speed * 3.6)
                            Text("\(Int(station.speed * 3.6)) km/h")
                                .bold()
                            Text("(\(station.speed.formatted(.number.precision(.fractionLength(1)))) m/s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Fahrtrichtung (Heading):")
                            Spacer()
                            Text("\(Int(station.heading))°")
                                .bold()
                            Text(getCompassDirection(heading: station.heading))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                    
                    // Sektion 3: Geografischer ASN.1 Auszug
                    Section(header: Text("🌐 Geografische Position (WGS84)")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Breitengrad (Lat):")
                                Spacer()
                                Text("\(station.coordinate.latitude.formatted(.number.precision(.fractionLength(6))))")
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack {
                                Text("Längengrad (Lon):")
                                Spacer()
                                Text("\(station.coordinate.longitude.formatted(.number.precision(.fractionLength(6))))")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(station.isHazard ? "⚠️ C-ITS Warnung" : "📡 V2X Live-Daten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
    
    // Hilfsfunktion zur Ermittlung der Himmelsrichtung aus dem Heading-Wert
    private func getCompassDirection(heading: Double) -> String {
        let directions = ["N", "NO", "O", "SO", "S", "SW", "W", "NW", "N"]
        let index = Int((heading + 22.5) / 45.0) & 7
        return directions[index]
    }
}
