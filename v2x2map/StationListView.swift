//
//  StationListView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Pastell-Listen-View mit optimiertem, schwarzem Textkontrast
//

import SwiftUI

struct StationListView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        List {
            if viewModel.stations.isEmpty {
                ContentUnavailableView(
                    "Keine C-ITS Objekte",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Schalte USB-C, BLE oder das Simulationslabor ein, um Daten zu empfangen.")
                )
                .listRowBackground(Color.clear)
            } else {
                // Sortiert nach Zeit-X-Hervorhebung, dann nach StationID
                ForEach(Array(viewModel.stations.values).sorted(by: {
                    if $0.exceedsAlertThreshold != $1.exceedsAlertThreshold {
                        return $0.exceedsAlertThreshold && !$1.exceedsAlertThreshold
                    }
                    return $0.stationID < $1.stationID
                })) { station in
                    StationRowView(station: station)
                        .onTapGesture {
                            viewModel.selectStation(station)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(
                            station.isHazard
                            ? Color(red: 1.0, green: 0.85, blue: 0.85) // Weiches Pastell-Rot für DENM
                            : Color(red: 0.85, green: 0.98, blue: 0.85) // Weiches Pastell-Grün für CAM
                        )
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct StationRowView: View {
    let station: MapStation
    @State private var pulseAlpha = 1.0
    
    var body: some View {
        HStack(spacing: 14) {
            // Visuelles Icon
            ZStack {
                Circle()
                    .fill(station.isHazard ? Color.red : (station.stationType == .roadSideUnit ? Color.blue : Color.green))
                    .frame(width: 40, height: 40)
                
                Image(systemName: station.isHazard ? "exclamationmark.triangle.fill" : (station.stationType == .roadSideUnit ? "antenna.radiowaves.left.and.right" : "car.fill"))
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
            }
            
            // Text-Inhalte mit erzwungenem hohem Kontrast für Pastell-Hintergründe
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(station.isHazard ? "Gefahr ID: \(station.stationID)" : "Station ID: \(station.stationID)")
                        .font(.headline)
                        .bold()
                        .foregroundColor(.black) // BEHOBEN: Feste schwarze Schriftfarbe
                    
                    Spacer()
                    
                    Text(formatDuration(from: station.firstDetectedAt))
                        .font(.system(.caption2, design: .monospaced))
                        .bold()
                        .foregroundColor(Color(white: 0.15)) // BEHOBEN: Sehr dunkles Anthrazit für exzellenten Kontrast
                }
                
                HStack {
                    Text(station.eventLabel ?? (station.stationType == .roadSideUnit ? "Infrastruktur-Mast (RSU)" : "Mobiles Fahrzeug (CAM)"))
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.2)) // BEHOBEN: Dunkles Grau für die Beschreibung
                    
                    Spacer()
                    
                    if let speed = station.speedKmH {
                        Text("\(Int(speed)) km/h")
                            .font(.system(.subheadline, design: .rounded)).bold()
                            .foregroundColor(.black) // BEHOBEN: Feste schwarze Schriftfarbe
                    }
                }
            }
            
            // Zeit X Warn-Indikator
            if station.exceedsAlertThreshold {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                    .opacity(pulseAlpha)
                    .shadow(color: .red, radius: 4)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulseAlpha = 0.3
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(from date: Date) -> String {
        let interval = Int(Date().timeIntervalSince(date))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d min", minutes, seconds)
    }
}
