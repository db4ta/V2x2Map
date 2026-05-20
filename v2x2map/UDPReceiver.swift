//
//  UDPReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Hochperformanter WLAN UDP-Listener für C-ITS-Nachrichtenströme
//

import Foundation
import Network
import OSLog

@MainActor public final class UDPReceiver: Sendable {
    
    private let port: UInt16
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "UDPReceiver")
    
    private final class ProtectedState: @unchecked Sendable {
        var listener: NWListener?
        var onDataReceived: (@Sendable (Data) -> Void)?
    }
    
    private let state = ProtectedState()
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { state.onDataReceived }
        set { state.onDataReceived = newValue }
    }
    
    public init(port: UInt16 = 26262) {
        self.port = port
    }
    
    public func startListening() async {
        if state.listener != nil {
            return
        }
        
        do {
            let parameters = NWParameters.udp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: parameters, on: nwPort)
            
            listener.stateUpdateHandler = { [weak self] newState in
                if case .failed = newState {
                    Task { @MainActor in
                        self?.stopListening()
                    }
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }
            
            state.listener = listener
            
            listener.start(queue: DispatchQueue(label: "com.v2x2map.udp.network", qos: .userInteractive))
            logger.info("UDP-Listener erfolgreich gestartet auf Port \(self.port)")
        } catch {
            logger.error("Fehler beim Starten des UDP-Listeners: \(error.localizedDescription)")
        }
    }
    
    public func stopListening() {
        state.listener?.cancel()
        state.listener = nil
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "com.v2x2map.udp.connection", qos: .userInteractive))
        receivePacket(from: connection)
    }
    
    private func receivePacket(from connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let data = content, !data.isEmpty {
                Task { @MainActor in
                    let callback = self.state.onDataReceived
                    callback?(data)
                }
            }
            if error == nil && isComplete {
                Task { @MainActor in
                    self.receivePacket(from: connection)
                }
            }
        }
    }
}
