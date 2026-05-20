//
//  MainMapView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Kartenhauptansicht mit funktionstüchtiger Menü-Navigation und Live-Annotations.
//

import SwiftUI
import MapKit

struct MainMapView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                // Live MapKit Karte
                Map(position: Bindable(viewModel).mapPosition) {
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
                .mapStyle(determineMapStyle())
                
                // Kontroll- und Navigationsoverlay oben rechts (Dashboard nach pit711)
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(viewModel.isConnected ? "V2X CO-PROCESSOR ACTIVE" : "SEARCHING HARDWARE...")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(viewModel.isConnected ? .green : .orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.04, green: 0.06, blue: 0.11).opacity(0.9))
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    
                    // Button öffnet das zentrale Einstellungsmenü
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color(red: 0.04, green: 0.06, blue: 0.11).opacity(0.9))
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
    
    private func determineMapStyle() -> MapStyle {
        switch viewModel.selectedMapStyle {
        case 1:
            return .imagery(elevation: .realistic)
        case 2:
            return .hybrid(elevation: .realistic, showsTraffic: viewModel.showTrafficOnMap)
        default:
            return .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: viewModel.showTrafficOnMap)
        }
    }
}
