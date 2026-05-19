//
//  USBReceiver.swift
//  v2x2map
//
//  Created for iOS 26.
//  Hochrobuster, nativer USB-Host-Treiber für ESP32 CDC-ACM (Fehlerbehoben)
//

import Foundation
import OSLog

public final class USBReceiver: Sendable {
    
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "USBReceiver")
    private let lock = NSLock()
    
    private final class ProtectedState: @unchecked Sendable {
        var fileDescriptor: Int32 = -1
        var isListening = false
        var devicePath: String? = nil
        var onDataReceived: (@Sendable (Data) -> Void)?
        var ioQueue: DispatchQueue?
        // BEHOBEN: Typkonflikt aufgelöst (DispatchSourceRead statt Tippfehler)
        var readSource: DispatchSourceRead?
    }
    private let state = ProtectedState()
    
    public var onDataReceived: (@Sendable (Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return state.onDataReceived }
        set { lock.lock(); defer { lock.unlock() }; state.onDataReceived = newValue }
    }
    
    public init() {}
    
    public func checkConnectionStatus() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.fileDescriptor != -1
    }
    
    private func findESP32DeviceNode() -> String? {
        let fileManager = FileManager.default
        let possibleNodes = [
            "/dev/cu.usbmodem",
            "/dev/cu.usbserial",
            "/dev/tty.usbmodem",
            "/dev/tty.usbserial"
        ]
        
        for node in possibleNodes {
            if fileManager.fileExists(atPath: node) {
                return node
            }
        }
        
        if let devFiles = try? fileManager.contentsOfDirectory(atPath: "/dev") {
            for file in devFiles {
                if file.hasPrefix("cu.usb") || file.hasPrefix("tty.usb") {
                    return "/dev/\(file)"
                }
            }
        }
        return nil
    }
    
    public func startListening() {
        lock.lock()
        if state.isListening { lock.unlock(); return }
        state.isListening = true
        lock.unlock()
        
        guard let path = findESP32DeviceNode() else {
            logger.error("ESP32 Hardware nicht im UNIX-Subsystem gefunden.")
            lock.lock()
            state.isListening = false
            lock.unlock()
            return
        }
        
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY)
        
        guard fd != -1 else {
            logger.error("Zugriffsfehler auf Device: \(path)")
            lock.lock()
            state.isListening = false
            lock.unlock()
            return
        }
        
        var tty = termios()
        if tcgetattr(fd, &tty) == 0 {
            cfsetispeed(&tty, speed_t(B115200))
            tty.c_cflag &= ~tcflag_t(PARENB)
            tty.c_cflag &= ~tcflag_t(CSTOPB)
            tty.c_cflag &= ~tcflag_t(CSIZE)
            tty.c_cflag |= tcflag_t(CS8)
            tty.c_cflag |= tcflag_t(CREAD) | tcflag_t(CLOCAL)
            tcsetattr(fd, TCSANOW, &tty)
        }
        
        lock.lock()
        state.fileDescriptor = fd
        state.devicePath = path
        
        let ioQueue = DispatchQueue(label: "com.v2x2map.usb.io", qos: .userInteractive)
        state.ioQueue = ioQueue
        
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 2048)
            let readBytes = read(fd, &buffer, buffer.count)
            
            if readBytes > 0 {
                let rawData = Data(bytes: buffer, count: readBytes)
                self.lock.lock()
                let callback = self.state.onDataReceived
                self.lock.unlock()
                callback?(rawData)
            } else if readBytes == 0 {
                self.stopListening()
            }
        }
        
        state.readSource = source
        source.resume()
        lock.unlock()
        
        logger.info("USB-Verbindung hergestellt zu: \(path)")
    }
    
    public func stopListening() {
        lock.lock()
        defer { lock.unlock() }
        
        state.readSource?.cancel()
        state.readSource = nil
        
        if state.fileDescriptor != -1 {
            close(state.fileDescriptor)
            state.fileDescriptor = -1
        }
        state.devicePath = nil
        state.isListening = false
        logger.info("USB-Schnittstelle sicher getrennt.")
    }
}
