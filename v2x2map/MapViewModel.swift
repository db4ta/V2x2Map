import SwiftUI
import MapKit
import CoreLocation
import Foundation
import OSLog

@Observable
@MainActor
public final class MapViewModel: NSObject, CLLocationManagerDelegate {
    private let logger = Logger(subsystem: "com.v2x2map.app", category: "MapViewModel")
    private let locationManager = CLLocationManager()
    
    // Core-Logik deines Repositories
    public let messageProcessor = MessageProcessor()
    public let bleReceiver = BLEReceiver()
    public let usbReceiver = USBReceiver()
    
    // Der zentrale Hardware-Hüter
    public var usbManager: USBManager!
    
    // Reaktives Array für die Karte und die Listen
    public var stations: [MapStation] = []
    public var isTrackingUserLocation: Bool = true
    public var cameraPosition: MapKit.MapCameraPosition = .automatic
    private var lastUserLocation: CLLocation?
    
    public override init() {
        super.init()
        self.usbManager = USBManager(usbReceiver: usbReceiver, bleReceiver: bleReceiver)
        setupLocationManager()
        setupHardwarePipeline()
        startLifecycleTimer()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if [.authorizedAlways, .authorizedWhenInUse].contains(locationManager.authorizationStatus) {
            locationManager.startUpdatingLocation()
        }
    }
    
    private func setupHardwarePipeline() {
        // Verbindet die Hardware-Bytes lückenlos mit dem ASN1Decoder und dem MessageProcessor
        bleReceiver.onDataReceived = { [weak self] rawBytes in
            guard let self = self else { return }
            Task { @MainActor in
                do {
                    let parsedStation = try ASN1Decoder.decodeV2X(from: rawBytes)
                    
                    // 1. Aktualisiere deinen originalen MessageProcessor
                    self.messageProcessor.updateStation(parsedStation)
                    
                    // 2. Synchronisiere das reaktive UI-Array
                    self.stations.removeAll(where: { $0.stationID == parsedStation.stationID })
                    self.stations.append(parsedStation)
                    
                    if self.isTrackingUserLocation {
                        self.triggerDynamicAutoZoom()
                    }
                } catch {
                    self.logger.error("C-ITS Parsing-Fehler: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startLifecycleTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Abgleich mit der Müllabfuhr deines MessageProcessors
                let active = self.messageProcessor.activeStations
                self.stations = Array(active.values)
            }
        }
    }
    
    public func triggerDynamicAutoZoom() {
        guard let userCoord = lastUserLocation?.coordinate else { return }
        var targetMeters: CLLocationDistance = 400.0
        
        if let closestStation = stations.first {
            let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
            let stationLoc = CLLocation(latitude: closestStation.coordinate.latitude, longitude: closestStation.coordinate.longitude)
            targetMeters = max(400.0, userLoc.distance(from: stationLoc) * 2.2)
        }
        
        let mapRegion = MKCoordinateRegion(center: userCoord, latitudinalMeters: targetMeters, longitudinalMeters: targetMeters)
        withAnimation(.easeInOut(duration: 0.3)) {
            self.cameraPosition = .region(mapRegion)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }
        self.lastUserLocation = latestLocation
        if isTrackingUserLocation { triggerDynamicAutoZoom() }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("GPS Fehler: \(error.localizedDescription)")
    }
}
