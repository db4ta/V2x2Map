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

public final class UDPReceiver: Sendable {
    
    private let port: UInt16
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "UDPReceiver")
    
    private final class ProtectedState: @unchecked Sendable {
        var listener: NWListener?
        var onDataReceived: (@Sendable (Data) -> Void)?
    }
    
    private let state = ProtectedState()
    private let lock = NSLock()
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onDataReceived }
        set { lock.lock(); defer { lock.unlock() }; state.onDataReceived = newValue }
    }
    
    public init(port: UInt16 = AppConfig.Network.defaultUdpPort) {
        self.port = port
    }
    
    public func startListening() async {
        lock.lock()
        if state.listener != nil {
            lock.unlock()
            return
        }
        lock.unlock()
        
        do {
            let parameters = NWParameters.udp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: parameters, on: nwPort)
            
            listener.stateUpdateHandler = { [weak self] newState in
                if case .failed = newState { self?.stopListening() }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            lock.lock()
            state.listener = listener
            lock.unlock()
            
            listener.start(queue: DispatchQueue(label: "com.v2x2map.udp.network", qos: .userInteractive))
            logger.info("UDP-Listener erfolgreich gestartet auf Port \(self.port)")
        } catch {
            logger.error("Fehler beim Starten des UDP-Listeners: \(error.localizedDescription)")
        }
    }
    
    public func stopListening() {
        lock.lock()
        defer { lock.unlock() }
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
                self.lock.lock()
                let callback = self.state.onDataReceived
                self.lock.unlock()
                callback?(data)
            }
            if error == nil && isComplete {
                self.receivePacket(from: connection)
            }
        }
    }
}
