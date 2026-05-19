//
//  MessageDetailSheet.swift
//  v2x2map
//
//  Created for iOS 26.
//  100% kompatibel zum Android-Originalprojekt (Detaillierte ASN.1-Ansicht)
//

import SwiftUI
import CoreLocation // Hinzugefügt: Löst den _LocationEssentials Fehler

struct MessageDetailSheet: View {
    /// Die ausgewählte Station, deren ASN.1-Felder angezeigt werden
    let station: MapStation
    
    /// Ermöglicht das Schließen des Sheets über die Umgebung
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Sektion 1: Allgemeine ETSI Metadaten
                Section(header: Text("Allgemeine C-ITS Header")) {
                    LabeledContent("Station ID", value: "\(station.stationID)")
                    LabeledContent("Protokoll-Typ", value: station.primaryMessageType.rawValue)
                    LabeledContent("Letztes Update", value: station.lastUpdatedAt.formatted(date: .omitted, time: .standard))
                }
                
                // MARK: - Sektion 2: Geografische Daten
                Section(header: Text("Geografische Position")) {
                    LabeledContent("Breitengrad (Lat)", value: String(format: "%.7f°", station.coordinate.latitude))
                    LabeledContent("Längengrad (Lon)", value: String(format: "%.7f°", station.coordinate.longitude))
                }
                
                // MARK: - Sektion 3: Spezifische CAM Nutzdaten
                if station.primaryMessageType == .cam {
                    Section(header: Text("Cooperative Awareness Payload (CAM)")) {
                        LabeledContent("Stationstyp", value: translateStationType(station.stationType))
                        
                        if let heading = station.heading {
                            LabeledContent("Fahrtrichtung", value: String(format: "%.1f°", heading))
                        } else {
                            LabeledContent("Fahrtrichtung", value: "N/A")
                        }
                        
                        if let speed = station.speedKmH {
                            LabeledContent("Geschwindigkeit", value: String(format: "%.1f km/h", speed))
                        } else {
                            LabeledContent("Geschwindigkeit", value: "0.0 km/h")
                        }
                    }
                }
                
                // MARK: - Sektion 4: Spezifische DENM Nutzdaten
                if station.primaryMessageType == .denm {
                    Section(header: Text("Decentralized Environmental Payload (DENM)")) {
                        LabeledContent("Gefahrenmeldung", value: station.eventLabel ?? "Unbekanntes Ereignis")
                        LabeledContent("Ereignis-ID", value: station.id)
                    }
                }
            }
            .navigationTitle("ASN.1 Protokoll-Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Hilfsmethoden zur Textübersetzung
    /// Übersetzt den ETSI StationType in ein lesbares, deutsches Äquivalent
    private func translateStationType(_ type: ETSIStationType) -> String {
        switch type {
        case .pedestrian: return "Fußgänger (1)"
        case .cyclist: return "Fahrradfahrer (2)"
        case .moped: return "Mofa / Moped (3)"
        case .motorcycle: return "Motorrad (4)"
        case .passengerCar: return "Personenkraftwagen / PKW (5)"
        case .bus: return "Omnibus (6)"
        case .lightTruck: return "Leichter LKW (7)"
        case .heavyTruck: return "Schwerer LKW (8)"
        case .trailer: return "Anhänger (9)"
        case .specialVehicles: return "Einsatzfahrzeug (10)"
        case .tram: return "Straßenbahn (11)"
        case .roadSideUnit: return "Infrastruktur / RSU (15)"
        case .unknown: return "Unbekannter Typ (0)"
        }
    }
}

// MARK: - Vorschau für SwiftUI-Canvas (Fehler behoben durch explizite Zuweisung)
#Preview {
    MessageDetailSheet(station: MapStation(
        id: "CAM_5001",
        stationID: 5001,
        coordinate: CLLocationCoordinate2D(latitude: 50.7753, longitude: 6.0839),
        stationType: .passengerCar,
        speedKmH: 48.5,
        heading: 120.0,
        primaryMessageType: .cam
    ))
}
