//
//  StationAnnotationView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Dynamische Karten-Icons für Fahrzeuge (CAM) und blinkende Alarme (DENM)
//

import SwiftUI

struct StationAnnotationView: View {
    let station: MapStation
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    private let deepseaBackground = Color(red: 10/255, green: 15/255, blue: 28/255)
    
    var body: some View {
        ZStack {
            // KORREKTUR: Nutzt dein reales 'isHazard' Property aus deiner originalen Modellstruktur
            if station.isHazard {
                // --- DENM ALARM-ICON (Rot blinkendes Gefahren-Dreieck mit Puls-Effekt) ---
                Circle()
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                            pulseScale = 2.2
                            pulseOpacity = 0.0
                        }
                    }
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.8), radius: 6)
                    .background(Circle().fill(deepseaBackground).frame(width: 20, height: 20))
                
            } else {
                // --- CAM FAHRZEUG-ICON (Giftgrüner Navigationspfeil in Fahrtrichtung gedreht) ---
                ZStack {
                    Circle()
                        .fill(deepseaBackground)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.green.opacity(0.6), lineWidth: 1.5))
                        .shadow(radius: 3)
                    
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(red: 0.22, green: 1.0, blue: 0.08))
                        .rotationEffect(.degrees(station.heading))
                        .shadow(color: Color(red: 0.22, green: 1.0, blue: 0.08).opacity(0.6), radius: 4)
                }
            }
        }
    }
}
