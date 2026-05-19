//
//  StationAnnotationView.swift
//  v2x2map
//
//  Created for iOS 26.
//  100% kompatibel zum Android-Originalprojekt (Dynamische Kartensymbole)
//

import SwiftUI
import CoreLocation

struct StationAnnotationView: View {
    /// Die darzustellende V2X-Station
    let station: MapStation
    
    /// Interner Animationszustand für das Pulsieren von Gefahrenmeldungen (DENM)
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            if station.isHazard {
                // MARK: - DENM / Gefahrensymbol
                ZStack {
                    // Pulsierender Hintergrundring für erhöhte Aufmerksamkeit
                    Circle()
                        .fill(.red)
                        .frame(width: 44, height: 44)
                        .scaleEffect(isPulsing ? 1.4 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                    
                    // Statisches Gefahrendreieck
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(.red)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .onAppear {
                    // Startet den unendlichen Warn-Puls-Effekt
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        isPulsing = true
                    }
                }
            } else {
                // MARK: - CAM / Fahrzeug- & RSU-Symbol
                VStack(spacing: 2) {
                    ZStack {
                        // Kreishintergrund je nach Stationstyp (RSU blau, Fahrzeuge grün)
                        Circle()
                            .fill(station.stationType == .roadSideUnit ? .blue : .green)
                            .frame(width: 32, height: 32)
                            .shadow(radius: 3)
                        
                        // Passendes Icon laden
                        Image(systemName: iconName(for: station.stationType))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            // Dreht das Symbol exakt in Fahrtrichtung (0° = Norden)
                            .rotationEffect(.degrees(station.heading ?? 0.0))
                    }
                    
                    // Optionale Geschwindigkeitsanzeige direkt unter dem Fahrzeug (falls aktiv)
                    if let speed = station.speedKmH, speed > AppConfig.Filters.minimumSpeedThreshold * 3.6 {
                        Text("\(Int(speed)) km/h")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .shadow(radius: 1)
                    }
                }
            }
        }
    }
    
    // MARK: - Hilfsfunktion für SF Symbols
    /// Mappt den ETSI StationType auf ein passendes iOS-Systemsymbol
    private func iconName(for type: ETSIStationType) -> String {
        switch type {
        case .pedestrian:
            return "figure.walk"
        case .cyclist:
            return "bicycle"
        case .motorcycle:
            return "scooter"
        case .passengerCar:
            return "car.fill"
        case .bus:
            return "bus.fill"
        case .lightTruck, .heavyTruck:
            return "truck.box.fill"
        case .tram:
            return "tram.fill"
        case .roadSideUnit:
            return "antenna.radiowaves.left.and.right"
        default:
            return "car.side.fill"
        }
    }
}

// MARK: - Vorschau für SwiftUI-Canvas (Fehler behoben durch CoreLocation-Zuweisung)
#Preview {
    VStack(spacing: 20) {
        // Vorschau für ein Fahrzeug (CAM) mit Fahrtrichtung 45 Grad
        StationAnnotationView(station: MapStation(
            id: "1",
            stationID: 5001,
            coordinate: CLLocationCoordinate2D(latitude: 50.7753, longitude: 6.0839),
            stationType: .passengerCar,
            speedKmH: 50.0,
            heading: 45.0,
            primaryMessageType: .cam
        ))
        
        // Vorschau für eine Gefahrenstelle (DENM)
        StationAnnotationView(station: MapStation(
            id: "2",
            stationID: 9002,
            coordinate: CLLocationCoordinate2D(latitude: 50.7760, longitude: 6.0845),
            stationType: .unknown,
            primaryMessageType: .denm,
            eventLabel: "Unfall"
        ))
    }
    .padding()
    .background(.gray.opacity(0.2))
}
