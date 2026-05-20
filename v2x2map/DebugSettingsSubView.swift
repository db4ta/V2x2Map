//
//  DebugSettingsSubView.swift
//  v2x2map
//
//  Created for iOS 26.
//  Untermenü für den V2X-Signalsimulator und das Live-Byte-Terminal.
//

import SwiftUI

struct DebugSettingsSubView: View {
    @Environment(MapViewModel.self) private var viewModel
    
    var body: some View {
        let editableModel = Bindable(viewModel)
        
        List {
            // MARK: - Sektion 1: Simulator nach pit711-Spezifikation
            Section(header: Text("Signalsimulation"), footer: Text("Der Simulator erzeugt künstliche CAM/DENM-Knoten auf der Karte, falls keine ESP32-C5 Hardware angeschlossen ist.")) {
                Toggle(isOn: editableModel.isSimulatorEnabled) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.purple)
                        Text("V2X-Signalsimulator")
                    }
                }
            }
            
            // MARK: - Sektion 2: Hexadezimales Datenstrom-Terminal
            Section(header: Text("Datenstrom-Terminal")) {
                Toggle(isOn: editableModel.isDebugModeEnabled) {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .foregroundColor(.orange)
                        Text("Erweiterten Debug-Modus aktivieren")
                    }
                }
                
                if viewModel.isDebugModeEnabled {
                    VStack(alignment: .leading) {
                        Text("C-ITS TERMINAL OUTPUT:")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.bottom, 4)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewModel.debugLogs, id: \.self) { logLine in
                                    Text(verbatim: logLine)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(logLine.contains("Stream-In") ? .green : .white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(height: 250)
                        .padding(8)
                        .background(Color.black)
                        .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            if viewModel.isDebugModeEnabled {
                Section(header: Text("Buffer-Statistiken")) {
                    HStack {
                        Text("Registrierte Knoten")
                        Spacer()
                        Text("\(viewModel.citsNodes.count) Active Nodes")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Entwickler / Debug")
    }
}

#Preview {
    DebugSettingsSubView()
        .environment(MapViewModel())
}
