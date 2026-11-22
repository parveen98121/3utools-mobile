import SwiftUI
import UIKit
import Observation

@MainActor
@Observable
final class DeviceInfoViewModel {
    private(set) var device: DeviceSnapshot
    private(set) var battery: BatteryReading
    private(set) var storage: StorageSnapshot?
    private(set) var network: NetworkStatus
    private(set) var wifiAddress: String?
    private(set) var cellularAddress: String?

    private let deviceService: DeviceInfoProviding
    private let batteryService: BatteryProviding
    private let storageService: StorageProviding

    init(device: DeviceInfoProviding = LiveDeviceInfoService(),
         battery: BatteryProviding = LiveBatteryService(),
         storage: StorageProviding = LiveStorageService()) {
        self.deviceService = device
        self.batteryService = battery
        self.storageService = storage
        self.device = device.snapshot()
        self.battery = battery.current()
        self.storage = try? storage.snapshot()
        self.network = NetworkMonitor.shared.current
    }

    func refresh() {
        device = deviceService.snapshot()
        battery = batteryService.current()
        storage = try? storageService.snapshot()
        network = NetworkMonitor.shared.current
        wifiAddress = NetworkTools.wifiAddress()
        cellularAddress = NetworkTools.cellularAddress()
    }

    var screenText: String {
        let width = Int(device.screenPoints.width * device.screenScale)
        let height = Int(device.screenPoints.height * device.screenScale)
        return "\(width) × \(height) pixels"
    }
}

struct DeviceInfoView: View {
    @State private var model = DeviceInfoViewModel()
    @State private var identifierRevealed = false

    var body: some View {
        List {
            Section("Identity") {
                InfoRow("Device name", model.device.name,
                        note: "Since iOS 16, apps receive a generic name such as “iPhone” instead of the name you chose.")
                InfoRow("Model", model.device.modelName,
                        note: model.device.modelName == nil ? "This identifier is not in the app's model table yet." : nil)
                InfoRow("Model identifier", model.device.modelIdentifier)
                InfoRow("Device type", model.device.isSimulator ? "\(model.device.deviceType) (Simulator)" : model.device.deviceType)
            }

            Section("Software") {
                InfoRow("System", "\(model.device.systemName) \(model.device.systemVersion)")
                InfoRow("Build", model.device.buildVersion)
            }

            Section("Storage") {
                InfoRow("Capacity", model.storage.map { Format.bytes($0.total) })
                InfoRow("Available", model.storage.map { Format.bytes($0.available) })
            }

            Section("Battery") {
                InfoRow("Level", model.battery.level.map(Format.percent))
                InfoRow("State", model.battery.state.label)
                InfoRow("Low Power Mode", model.device.lowPowerMode ? "On" : "Off")
                InfoRow("Battery health", nil, note: "iOS does not share battery health with apps. See Settings > Battery > Battery Health.")
            }

            Section("Hardware") {
                InfoRow("Processor cores", "\(model.device.processorCount) (\(model.device.activeProcessorCount) active)")
                InfoRow("Memory", Format.bytes(Int64(model.device.physicalMemory)))
                InfoRow("Screen", model.screenText)
                InfoRow("Screen scale", "@\(Int(model.device.screenScale))x")
                InfoRow("Maximum refresh rate", "\(model.device.maximumFramesPerSecond) Hz")
                InfoRow("Temperature state", model.device.thermalState.label)
                InfoRow("Running for", Format.duration(model.device.uptime))
            }

            Section("Network") {
                InfoRow("Connection", model.network.isConnected ? model.network.interface : "Not connected")
                InfoRow("Wi-Fi IP address", model.wifiAddress)
                InfoRow("Mobile data IP address", model.cellularAddress)
                InfoRow("IPv6 support", model.network.supportsIPv6 ? "Yes" : "No")
                InfoRow("Wi-Fi network name", nil, note: "Needs a capability that free Apple ID signing does not include.")
            }

            Section {
                if identifierRevealed {
                    InfoRow("Vendor identifier", model.device.vendorIdentifier)
                    if let identifier = model.device.vendorIdentifier {
                        Button("Copy") { UIPasteboard.general.string = identifier }
                    }
                } else {
                    Button("Reveal vendor identifier") {
                        withAnimation { identifierRevealed = true }
                    }
                }
            } header: {
                Text("Identifier")
            } footer: {
                Text("This identifier belongs to this app on this phone and changes if the app is deleted. iOS does not give apps the serial number or IMEI, and this app does not try to read them.")
            }
        }
        .navigationTitle("Device information")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { model.refresh() }
        .onAppear { model.refresh() }
    }
}
