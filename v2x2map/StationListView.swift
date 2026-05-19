//
//  StationListView.swift
//  v2x2map
//
//  Created for iOS 26.
//

import SwiftUI
import CoreLocation

struct StationListView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        NavigationStack {
            // KORREKTUR: Liest die Stationen direkt und performant aus dem reaktiven Array
            List(viewModel.stations) { station in
                HStack(spacing: 12) {
                    Circle()
                        .fill(station.isHazard ? Color.red : Color.green)
                        .frame(width: 12, height: 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Station ID: \(station.stationID)")
                            .font(.system(.headline, design: .rounded))
                        
                        Text("Lat: \(station.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), Lon: \(station.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: station.isHazard ? "trafficlight.3.fill" : "car.fill")
                        .foregroundColor(station.isHazard ? .orange : .blue)
                        .font(.title3)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("C-ITS Stationen (\(viewModel.stations.count))")
            .overlay {
                if viewModel.stations.isEmpty {
                    ContentUnavailableView(
                        "Keine Empfangsdaten",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Warte auf GeoNetworking Pakete des Modems...")
                    )
                }
            }
        }
    }
}
