//
//  MainMapView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Vollständiges Haupt-Kartenfenster mit Live-Zentrierung, Einstellungs-Menü und Hex-Debug-Log.
//

import SwiftUI
import MapKit

struct MainMapView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    @State private var showSettings: Bool = false
    @State private var showStationList: Bool = false
    @State private var selectedStation: MapStation? = nil
    
    private let deepseaBackground = Color(red: 10/255, green: 15/255, blue: 28/255)
    
    var body: some View {
        @Bindable var vm = viewModel
        // Gekoppelt an das im globalen Scope gehaltene Manager-Objekt deines ViewModels
        @Bindable var um = viewModel.usbManager
        
        NavigationStack {
            ZStack {
                // 1. MapKit Live-Karte gekoppelt an dein reaktives Array
                Map(position: $vm.cameraPosition) {
                    UserAnnotation()
                    
                    // Direktes, stabiles Iterieren über das fehlerfreie Array
                    ForEach(viewModel.stations) { station in
                        Annotation("Station \(station.stationID)", coordinate: station.coordinate) {
                            StationAnnotationView(station: station)
                                .onTapGesture {
                                    selectedStation = station
                                }
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .gesture(
                    DragGesture().onChanged { _ in
                        viewModel.isTrackingUserLocation = false
                    }
                )
                
                // 2. Schwebende Steuerungs-Buttons (Overlays)
                VStack {
                    HStack {
                        if !viewModel.isTrackingUserLocation {
                            Button(action: { viewModel.isTrackingUserLocation = true }) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            .padding(.leading, 16)
                        }
                        
                        Spacer()
                        
                        Button(action: { showStationList.toggle() }) {
                            Image(systemName: "list.bullet.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(deepseaBackground.opacity(0.85))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                        }
                        .padding(.trailing, 8)
                        
                        Button(action: { withAnimation { showSettings.toggle() } }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(deepseaBackground.opacity(0.85))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                }
                
                // 3. V2X-Steuerzentrale (Seitenmenü)
                if showSettings {
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 16) {
                                // KORREKTUR: Flacher SwiftUI-Header ersetzt die fehlende 'AppMenuHeaderView' direkt im Scope
                                HStack {
                                    Text("V2X Steuerzentrale")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button(action: { withAnimation { showSettings = false } }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .font(.title3)
                                    }
                                }
                                .padding(.top, 10)
                                
                                Divider()
                                    .background(Color.cyan.opacity(0.3))
                                
                                ScrollView {
                                    VStack(spacing: 14) {
                                        Toggle(isOn: Binding(
                                            get: { viewModel.usbManager.usbIsEnabled },
                                            set: { newValue in Task { await viewModel.usbManager.toggleUsbConnection(to: newValue) } }
                                        )) {
                                            Label("USB-Modem (Kabel)", systemImage: "cable.connector")
                                                .foregroundColor(.white)
                                        }
                                        .tint(.green)
                                        
                                        NavigationLink(destination: WirelessSettingsView(usbManager: viewModel.usbManager)) {
                                            HStack {
                                                Label("Drahtlos-Setup (BLE)", systemImage: "wifi")
                                                    .foregroundColor(.white)
                                                Spacer()
                                                HStack(spacing: 4) {
                                                    Text(viewModel.usbManager.bleIsConnected ? "Verbunden" : "Konfigurieren")
                                                        .font(.caption)
                                                        .foregroundColor(viewModel.usbManager.bleIsConnected ? .green : .gray)
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        
                                        Toggle(isOn: $um.isSimulationEnabled) {
                                            Label("Labor-Simulation", systemImage: "waveform.path.ecg")
                                                .foregroundColor(.white)
                                        }
                                        .tint(.cyan)
                                        
                                        Toggle(isOn: Binding(
                                            get: { viewModel.isTrackingUserLocation },
                                            set: { viewModel.isTrackingUserLocation = $0 }
                                        )) {
                                            Label("Auto-Kartenzentrierung", systemImage: "location.circle")
                                                .foregroundColor(.white)
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .frame(maxHeight: 180)
                                
                                Divider()
                                    .background(Color.cyan.opacity(0.3))
                                
                                // Debug Terminal
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Serielles Hex-Debug-Log")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.cyan)
                                        Spacer()
                                        Button("Clear") { viewModel.usbManager.clearLog() }
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 4) {
                                                ForEach(um.debugLog) { entry in
                                                    Text(entry.text)
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundColor(entry.type == .error ? .red : (entry.type == .rx ? .cyan : .white))
                                                        .id(entry.id)
                                                }
                                            }
                                            .padding(8)
                                        }
                                        .frame(height: 150)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(8)
                                        .task(id: um.packetCount) {
                                            if let lastEntry = um.debugLog.last {
                                                withAnimation { proxy.scrollTo(lastEntry.id, anchor: .bottom) }
                                            }
                                        }
                                    }
                                }
                                
                                Button(action: { viewModel.usbManager.runHardwarePingTest() }) {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "gauge.with.needle")
                                        Text("Hardware-Diagnose")
                                        Spacer()
                                    }
                                    .font(.subheadline)
                                    .bold()
                                    .padding(.vertical, 8)
                                    .foregroundColor(.white)
                                    .background(Color.cyan.opacity(0.2))
                                    .cornerRadius(6)
                                }
                                Spacer()
                            }
                            .padding()
                            .frame(width: geometry.size.width * 0.82)
                            .background(deepseaBackground)
                            .transition(.move(edge: .trailing))
                        }
                    }
                    .background(Color.black.opacity(0.4).onTapGesture { withAnimation { showSettings = false } })
                }
            }
            .sheet(isPresented: $showStationList) {
                StationListView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedStation) { station in
                MessageDetailSheet(station: station)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
