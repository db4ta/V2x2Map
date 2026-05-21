//
//  UDPReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Hochperformanter WLAN UDP-Listener für C-ITS-Nachrichtenströme (Network.framework)
//

import Foundation
import Network
import OSLog

// Durch die Platzierung im File-Scope erbt diese Hilfsklasse keine Akteur-Isolierung.
private final class UDPReceiverProtectedState: @unchecked Sendable {
    var listener: NWListener?
    var onDataReceived: (@Sendable (Data) -> Void)?
    init() {}
}

@MainActor 
public final class UDPReceiver: Sendable {
    // nonisolated let-Eigenschaften können von jedem Thread aus sicher ohne MainActor-Wechsel gelesen werden.
    nonisolated private let port: UInt16
    nonisolated private let logger = Logger(subsystem: "com.v2x2map.app", category: "UDPReceiver")
    nonisolated private let state = UDPReceiverProtectedState()
    
    private let processingQueue = DispatchQueue(label: "com.v2x2map.udp.processing", qos: .userInteractive)
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { state.onDataReceived }
        set { state.onDataReceived = newValue }
    }
    
    nonisolated public init(port: UInt16 = 26262) {
        self.port = port
    }
    
    public func startListening() async {
        if state.listener != nil { return }
        
        do {
            // Konfiguration für robustes lokales Wi-Fi Multicast / Unicast
            let parameters = NWParameters.udp
            
            // Verhindert, dass iOS Wi-Fi Assist den Socket über Mobilfunk umleitet
            parameters.prohibitedInterfaceTypes = [.cellular]
            parameters.includePeerToPeer = true
            
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: parameters, on: nwPort)
            
            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return } // Lokales, unveränderliches 'self' entpacken
                switch newState {
                case .ready:
                    self.logger.info("UDP-Listener bereit auf Port \(self.port)")
                case .failed(let error):
                    self.logger.error("UDP-Listener failed: \(error.localizedDescription)")
                    Task { @MainActor in self.stopListening() }
                case .waiting(let error):
                    // WICHTIG: Im .waiting Zustand (z.B. während ESP32-Bluetooth-Slot blockiert) 
                    // nicht trennen! Wir lassen den Socket geduldig auf das nächste Wi-Fi-Fenster warten.
                    self.logger.debug("Netzwerk temporär blockiert (COEX/Sperre): \(error.localizedDescription)")
                case .cancelled:
                    self.logger.info("UDP-Listener abgebrochen.")
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return } // Lokales, unveränderliches 'self' entpacken
                // Cross-Actor Boundary: Da die neue Verbindung asynchron im Hintergrund geliefert wird,
                // übergeben wir sie sicher verpackt an den Main Actor.
                Task { @MainActor in
                    self.handleIncomingConnection(connection)
                }
            }
            
            state.listener = listener
            listener.start(queue: processingQueue)
        } catch {
            logger.error("Fehler beim Starten des UDP-Listeners: \(error.localizedDescription)")
        }
    }
    
    public func stopListening() {
        state.listener?.cancel()
        state.listener = nil
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: processingQueue)
        receivePacket(from: connection)
    }
    
    private func receivePacket(from connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, isComplete, error in
            guard let self else { return } // Lokales, unveränderliches 'self' entpacken
            if let data = content, !data.isEmpty {
                let callback = self.state.onDataReceived
                callback?(data)
            }
            if error == nil && isComplete {
                // Cross-Actor Boundary: Rekursives Abhören auf dem Main Actor anfordern
                Task { @MainActor in
                    self.receivePacket(from: connection)
                }
            }
        }
    }
}
