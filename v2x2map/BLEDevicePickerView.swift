import Combine
import SwiftUI

final class BLEViewModel: ObservableObject {
    @Published var devices: [BLEReceiver.DiscoveredDevice] = []
    @Published var isConnected: Bool = false
    @Published var selectedDeviceID: UUID?

    private let receiver: BLEReceiver
    private var timer: Timer?

    init(receiver: BLEReceiver) {
        self.receiver = receiver
    }

    func start() {
        receiver.startScan()
        startPolling()
    }

    func stop() {
        stopPolling()
        receiver.stopScan()
    }

    func connect(to device: BLEReceiver.DiscoveredDevice) {
        selectedDeviceID = device.id
        receiver.connect(to: device.id)
    }

    func disconnect() {
        receiver.disconnect()
        selectedDeviceID = nil
    }

    private func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let newDevices = self.receiver.devices
            let connected = self.receiver.checkConnectionStatus()
            DispatchQueue.main.async {
                self.devices = newDevices
                self.isConnected = connected
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}

struct BLEDevicePickerView: View {
    @StateObject private var viewModel: BLEViewModel

    init(receiver: BLEReceiver) {
        _viewModel = StateObject(wrappedValue: BLEViewModel(receiver: receiver))
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.devices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Keine Geräte gefunden")
                            .font(.headline)
                        Text("Aktiviere Bluetooth und stelle sicher, dass Geräte in der Nähe sind.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.devices.prefix(5)) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name).font(.headline)
                                Text("RSSI: \(device.rssi)").font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Verbinden") {
                                viewModel.connect(to: device)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("BLE Geräte")
            .toolbar {
                if viewModel.isConnected {
                    Button("Trennen") { viewModel.disconnect() }
                }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}

#if DEBUG
#Preview {
    BLEDevicePickerView(receiver: BLEReceiver())
}
#endif

