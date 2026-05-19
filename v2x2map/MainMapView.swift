//
//  MainMapView.swift
//  v2x2map
//
//  Created for iOS 26.
//

import SwiftUI
import MapKit

struct MainMapView: View {
    @Environment(MapViewModel.self) private var viewModel
    @State private var showSettings = false
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(center: AppConfig.Map.defaultCenter, latitudinalMeters: AppConfig.Map.defaultRadiusInMeters, longitudinalMeters: AppConfig.Map.defaultRadiusInMeters))
    
    // NEU: Steuerung des Ansichts-Modus (0 = Karte, 1 = Liste)
    @State private var selectedViewMode = 0
    
    var body: some View {
        @Bindable var bindableViewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                // NEU: Die obere Auswahleiste für den Ansichts-Wechsel
                Picker("Ansicht", selection: $selectedViewMode) {
                    Text("Karte").tag(0)
                    Text("Liste").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                
                ZStack {
                    if selectedViewMode == 0 {
                        // ➡️ MODUS MAPKIT-KARTE
                        Map(position: $cameraPosition) {
                            UserAnnotation()
                            ForEach(Array(viewModel.stations.values)) { station in
                                Annotation(station.eventLabel ?? "ITS Station", coordinate: station.coordinate) {
                                    // Zeigt ein rotes Warnleuchten auf der Karte, falls Zeit X überschritten ist
                                    StationAnnotationView(station: station)
                                        .scaleEffect(station.exceedsAlertThreshold ? 1.2 : 1.0)
                                        .shadow(color: station.exceedsAlertThreshold ? .red : .clear, radius: 8)
                                        .onTapGesture { viewModel.selectStation(station) }
                                }
                                .annotationTitles(.hidden)
                            }
                        }
                        .onMapCameraChange { viewModel.isTrackingUserLocation = false }
                        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
                        
                        // Karten-Bedienelemente
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    Button(action: {
                                        viewModel.isTrackingUserLocation = true
                                        viewModel.resetMapCenter()
                                        cameraPosition = .userLocation(fallback: .automatic)
                                    }) {
                                        Image(systemName: viewModel.isTrackingUserLocation ? "location.fill" : "location")
                                            .font(.title2).padding().background(.ultraThinMaterial).clipShape(Circle())
                                            .foregroundColor(viewModel.isTrackingUserLocation ? .blue : .primary)
                                    }
                                    Button(action: { showSettings.toggle() }) {
                                        Image(systemName: "gearshape.fill").font(.title2).padding().background(.ultraThinMaterial).clipShape(Circle())
                                    }
                                }.padding(.trailing, 16).padding(.bottom, 32)
                            }
                        }
                    } else {
                        // ➡️ MODUS PASTELL-LISTE
                        StationListView()
                    }
                }
            }
            .navigationTitle("v2x2map Live-Ansicht")
            .navigationBarTitleDisplayMode(.inline)
            // Stellt sicher, dass das Zahnrad-Symbol im Listenmodus über die Navigationsleiste erreichbar bleibt
            .toolbar {
                if selectedViewMode == 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape.fill")
                        }
                    }
                }
            }
            .sheet(item: $bindableViewModel.selectedStation) { station in
                MessageDetailSheet(station: station)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear { viewModel.requestLocationAccess() }
            .onChange(of: viewModel.mapRegion.center.latitude) {
                if viewModel.isTrackingUserLocation { cameraPosition = .region(viewModel.mapRegion) }
            }
        }
    }
}

#Preview {
    MainMapView()
        .environment(MapViewModel())
}
