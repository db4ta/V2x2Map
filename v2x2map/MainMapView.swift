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
    
    // Zentraler Hardware-Manager deiner Git-Architektur
    @State private var usbManager = USBManager(usbReceiver: USBReceiver(), bleReceiver: BLEReceiver())
    
    @State private var showSettings: Bool = false
    @State private var selectedStation: MapStation? = nil
    
    private let deepseaBackground = Color(red: 10/255, green: 15/255, blue: 28/255)
    
    var body: some View {
        @Bindable var um = usbManager
        
        NavigationStack {
            ZStack {
                // 1. KORREKTUR: Stabile, parameterlose Map-Variante eliminiert Selection- und Typenkonflikte vollständig
                Map {
                    UserAnnotation()
                    
                    // Sauberes Flachklopfen des Dictionarys in ein Werte-Array
                    ForEach(Array(viewModel.stations.values)) { station in
                        Annotation(
                            "Station \(station.stationID)",
                            coordinate: station.coordinate
                        ) {
                            StationAnnotationView(station: station)
                                .onTapGesture {
                                    // Öffnet das Detail-Sheet sicher über deine bestehende Tap-Logik
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
                                    .shadow(radius: 4)
                            }
                            .padding(.leading, 16)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        
                        Spacer()
                        
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
                                            get: { usbManager.usbIsEnabled },
                                            set: { newValue in Task { await usbManager.toggleUsbConnection(to: newValue) } }
                                        )) {
                                            Label("USB-Modem (Kabel)", systemImage: "cable.connector")
                                                .foregroundColor(.white)
                                        }
                                        .tint(.green)
                                        
                                        // Weiterleitung zur WirelessSettingsView
                                        NavigationLink(destination: WirelessSettingsView(usbManager: usbManager)) {
                                            HStack {
                                                Label("Drahtlos-Setup (BLE)", systemImage: "wifi")
                                                    .foregroundColor(.white)
                                                Spacer()
                                                HStack(spacing: 4) {
                                                    Text(usbManager.bleIsConnected ? "Verbunden" : "Konfigurieren")
                                                        .font(.caption)
                                                        .foregroundColor(usbManager.bleIsConnected ? .green : .gray)
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
                                
                                // --- SCHWARZES SERIELLES DEBUG-TERMINAL ---
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Serielles Hex-Debug-Log")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.cyan)
                                        Spacer()
                                        Button("Clear") { usbManager.clearLog() }
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
                                
                                Button(action: { usbManager.runHardwarePingTest() }) {
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
            .sheet(item: $selectedStation) { station in
                MessageDetailSheet(station: station)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
