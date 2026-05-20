//
//  V2XMapSettingsSubView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Untermenü für deine Kartentyp- und Traffic-Einstellungen.
//

import SwiftUI

struct V2XMapSettingsSubView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        let editableModel = Bindable(viewModel)
        
        List {
            // MARK: - Sektion 1: Kartenstil-Auswahl
            Section(header: Text("Darstellungsart")) {
                Picker("Kartenstil", selection: editableModel.selectedMapStyle) {
                    Text("Standard").tag(0)
                    Text("Satellit").tag(1)
                    Text("Hybrid").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
            }
            
            // MARK: - Sektion 2: Anzeige & Display
            Section(header: Text("Anzeige-Optionen")) {
                Toggle(isOn: editableModel.showTrafficOnMap) {
                    HStack {
                        Image(systemName: "car.2.fill")
                            .foregroundColor(.blue)
                        Text("Apple Traffic anzeigen")
                    }
                }
                
                Toggle(isOn: editableModel.isDisplayAlwaysOn) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.orange)
                        Text("Bildschirm immer eingeschaltet lassen")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Karteneinstellungen")
    }
}

#Preview {
    V2XMapSettingsSubView()
        .environment(MapViewModel())
}
