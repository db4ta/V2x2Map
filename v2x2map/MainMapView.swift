//
//  MainMapView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Kartenhauptansicht mit dynamischem Kartenstil-Wechsel und Live-Rendering der V2X-Symbole.
//

import SwiftUI
import MapKit

struct MainMapView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                
                // MARK: - Live MapKit Karte mit parametrisiertem Stil
                Map(position: Bindable(viewModel).mapPosition) {
                    
                    // SCHLEIFE ZUM RENDERN DER V2X SYMBOLE AUF DER KARTE
                    ForEach(Array(viewModel.citsNodes.values), id: \.id) { node in
                        Annotation(
                            node.stationType == 2 ? "C-ITS Ampel" : "C-ITS Fahrzeug",
                            coordinate: node.coordinate
                        ) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(node.stationType == 2 ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: node.stationType == 2 ? "lightrail.lamp.fill" : "car.radio.2")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(node.stationType == 2 ? Color.red : Color.blue)
                                        .clipShape(Circle())
                                }
                                
                                // Geschwindigkeitsanzeige über dem Symbol
                                if node.stationType != 2 && node.speedKmH > 0.5 {
                                    Text(String(format: "%.0f km/h", node.speedKmH))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(4)
                                        .shadow(color: .black.opacity(0.1), radius: 2)
                                }
                            }
                        }
                    }
                }
                // Auswertung deines Segmented-Pickers für den Kartenstil
                .mapStyle(determineMapStyle())
                
                // MARK: - Live Konnektivitäts-Overlay
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(viewModel.isConnected ? "V2X DISCOVERED" : "NO HARDWARE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(viewModel.isConnected ? .green : .orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.04, green: 0.06, blue: 0.11).opacity(0.9))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 4)
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
    
    /// Wandelt den ausgewählten Integer-Index in den MapKit-Kartenstil um
    private func determineMapStyle() -> MapStyle {
        switch viewModel.selectedMapStyle {
        case 1:
            return .imagery(elevation: .realistic)
        case 2:
            return .hybrid(elevation: .realistic, showsTraffic: viewModel.showTrafficOnMap)
        default:
            // Argumentenreihenfolge korrigiert (pointsOfInterest vor showsTraffic)
            return .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: viewModel.showTrafficOnMap)
        }
    }
}

#Preview {
    MainMapView()
        .environment(MapViewModel())
}
