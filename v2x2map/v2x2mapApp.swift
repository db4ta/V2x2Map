//
//  v2x2mapApp.swift
//  v2x2map
//
//  Created for iOS 26.
//  100% kompatibel zum Android-Originalprojekt (Dual-Datalink für USB & BLE)
//

import SwiftUI
import Network
import MapKit

@main
struct v2x2mapApp: App {
    // Globale Zustandsverwaltung via modernem @Observable Makro
    @State private var mapViewModel = MapViewModel()
    
    // Core Services als langlebige Instanzen (Direkte Deklaration verhindert den let-Fehler)
    private let messageProcessor = MessageProcessor()
    private let usbReceiver = USBReceiver()
    private let bleReceiver = BLEReceiver()
    
    // Globaler USB/BLE Manager für die UI- und Debug-Anbindung
    @State private var usbManager: USBManager
    
    // Zustände für die sanfte Ein- und Ausblendung des Startlogos
    @State private var isShowingSplashScreen = true
    @State private var splashOpacity: Double = 0.0
    
    init() {
        // BEHOBEN: Instanzen wurden bereits oben zugewiesen. Hier wird nur noch der Manager an diese Instanzen gebunden.
        self._usbManager = State(initialValue: USBManager(usbReceiver: usbReceiver, bleReceiver: bleReceiver))
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplashScreen {
                    // MARK: - Startlogo / Splash Screen Ansicht
                    VStack(spacing: 24) {
                        Spacer()
                        
                        // Hochpräzises, professionelles V2X-Navigationssymbol
                        ZStack {
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Color(red: 0.04, green: 0.06, blue: 0.11)) // #0A0F1C (Tiefseeblau)
                                .frame(width: 160, height: 160)
                                .overlay(
                                    // Leuchtendes, perspektivisch verzerrtes cyan-blaues Straßennetz/Grid (digitaler Stadtplan)
                                    ZStack {
                                        Path { path in
                                            // Horizontale Linien (schräg verzerrt)
                                            path.move(to: CGPoint(x: -20, y: 40)); path.addLine(to: CGPoint(x: 180, y: 20))
                                            path.move(to: CGPoint(x: -20, y: 100)); path.addLine(to: CGPoint(x: 180, y: 90))
                                            path.move(to: CGPoint(x: -20, y: 140)); path.addLine(to: CGPoint(x: 180, y: 130))
                                            // Vertikale Linien
                                            path.move(to: CGPoint(x: 30, y: -20)); path.addLine(to: CGPoint(x: 50, y: 180))
                                            path.move(to: CGPoint(x: 90, y: -20)); path.addLine(to: CGPoint(x: 120, y: 180))
                                        }
                                        .stroke(Color(red: 0.0, green: 0.8, blue: 1.0, opacity: 0.25), lineWidth: 1.5)
                                        .blur(radius: 0.5)
                                        
                                        // Hauptstraßen-Glow
                                        Path { path in
                                            path.move(to: CGPoint(x: -20, y: 70))
                                            path.addCurve(to: CGPoint(x: 180, y: 80), control1: CGPoint(x: 60, y: 120), control2: CGPoint(x: 120, y: 40))
                                        }
                                        .stroke(Color(red: 0.0, green: 0.9, blue: 1.0, opacity: 0.6), lineWidth: 2)
                                        .shadow(color: Color(red: 0.0, green: 0.9, blue: 1.0), radius: 4)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                                )
                                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 8)
                            
                            // Konzentrische, cyan-blaue Signalwellen/Radarwellen
                            ZStack {
                                Circle().stroke(Color(red: 0.0, green: 0.9, blue: 1.0, opacity: 0.7), lineWidth: 2).frame(width: 60, height: 60)
                                Circle().stroke(Color(red: 0.0, green: 0.9, blue: 1.0, opacity: 0.4), lineWidth: 1.5).frame(width: 95, height: 95)
                                Circle().stroke(Color(red: 0.0, green: 0.9, blue: 1.0, opacity: 0.2), lineWidth: 1.0).frame(width: 130, height: 130)
                            }
                            .blur(radius: 0.3)
                            
                            // Zentrales Motiv: Markanter, neon-grüner Navigations-Pfeil (45° nach rechts-oben)
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 42, weight: .black))
                                .foregroundColor(Color(red: 0.22, green: 1.0, blue: 0.08)) // #39FF14 Giftgrün
                                .rotationEffect(.degrees(45))
                                .shadow(color: Color(red: 0.22, green: 1.0, blue: 0.08), radius: 12)
                        }
                        .frame(width: 200, height: 200)
                        
                        VStack(spacing: 8) {
                            Text("V2x2Map")
                                .font(.system(size: 38, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .tracking(2)
                            
                            Text("C-ITS LIVE TELEMETRY")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.13, green: 0.6, blue: 1.0))
                                .tracking(4)
                        }
                        
                        Spacer()
                        
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                            .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.03, green: 0.04, blue: 0.1))
                    .opacity(splashOpacity)
                    
                } else {
                    // MARK: - Eigentliche App-Karte
                    MainMapView()
                        .environment(mapViewModel)
                        .environment(usbManager)
                        .transition(.opacity)
                }
            }
            .task {
                setupDataLink()
                startBackgroundSimulationLoop() // Startet den ununterbrochenen Labortakt
                
                // 1. Sanftes Einblenden des Logos
                withAnimation(.easeIn(duration: 0.6)) {
                    splashOpacity = 1.0
                }
                
                // 2. Haltezeit auf 5 Sekunden angehoben
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                
                // 3. Sanftes Ausblenden des Logos
                withAnimation(.easeOut(duration: 0.5)) {
                    splashOpacity = 0.0
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                withAnimation {
                    isShowingSplashScreen = false
                }
            }
        }
    }
    
    private func setupDataLink() {
        // 1. Pipeline für USB-Kabel-Daten
        usbReceiver.onDataReceived = { [messageProcessor, usbManager, mapViewModel] rawData in
            usbManager.logIncomingData(rawData, source: "USB")
            
            Task { @MainActor in
                let isSimAllowed = usbManager.isSimulationEnabled
                let currentGPS = mapViewModel.mapRegion.center
                
                Task(priority: .high) {
                    if let v2xMessage = ASN1Decoder.decode(data: rawData, isSimulationAllowed: isSimAllowed, referenceCoordinate: currentGPS) {
                        await messageProcessor.process(v2xMessage)
                    }
                }
            }
        }
        
        // 2. Pipeline für Bluetooth-Funk-Daten
        bleReceiver.onDataReceived = { [messageProcessor, usbManager, mapViewModel] rawData in
            usbManager.logIncomingData(rawData, source: "BLE")
            
            Task { @MainActor in
                let isSimAllowed = usbManager.isSimulationEnabled
                let currentGPS = mapViewModel.mapRegion.center
                
                Task(priority: .high) {
                    if let v2xMessage = ASN1Decoder.decode(data: rawData, isSimulationAllowed: isSimAllowed, referenceCoordinate: currentGPS) {
                        await messageProcessor.process(v2xMessage)
                    }
                }
            }
        }
        
        // Verarbeitete Stationen an das MapViewModel auf dem MainActor weiterleiten
        messageProcessor.onModelUpdate = { [mapViewModel] updatedStations in
            Task { @MainActor in
                mapViewModel.updateStations(with: updatedStations)
            }
        }
    }
    
    // Taktgeber füttert das System konstant jede Sekunde im Labormodus,
    // um die Müllabfuhr-Timeouts auszuhebeln
    private func startBackgroundSimulationLoop() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 Sekunde
                
                await MainActor.run {
                    if usbManager.isSimulationEnabled {
                        let currentGPS = mapViewModel.mapRegion.center
                        let dummyData = Data([0x00, 0x00, 0x00, 0x00]) // Dummy-Trigger
                        
                        Task(priority: .high) {
                            if let v2xMessage = ASN1Decoder.decode(data: dummyData, isSimulationAllowed: true, referenceCoordinate: currentGPS) {
                                await messageProcessor.process(v2xMessage)
                            }
                        }
                    }
                }
            }
        }
    }
}
