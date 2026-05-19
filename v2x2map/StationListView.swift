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
            List(Array(viewModel.stations.values)) { station in
                HStack(spacing: 12) {
                    // Visueller Indikator für den C-ITS Stationstyp
                    Circle()
                        .fill(station.stationID % 2 == 0 ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Station ID: \(station.stationID)")
                            .font(.system(.headline, design: .rounded))
                        
                        Text("Lat: \(station.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), Lon: \(station.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: station.stationID % 2 == 0 ? "car.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(station.stationID % 2 == 0 ? .blue : .orange)
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
                        description: Text("Warte auf CAM/DENM Pakete des Modems...")
                    )
                }
            }
        }
    }
}
