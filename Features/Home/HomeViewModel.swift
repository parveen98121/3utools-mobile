import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var device: DeviceSnapshot?
    private(set) var battery: BatteryReading?
    private(set) var storage: StorageSnapshot?
    private(set) var storageError: String?

    private let deviceService: DeviceInfoProviding
    private let batteryService: BatteryProviding
    private let storageService: StorageProviding

    init(device: DeviceInfoProviding = LiveDeviceInfoService(),
         battery: BatteryProviding = LiveBatteryService(),
         storage: StorageProviding = LiveStorageService()) {
        self.deviceService = device
        self.batteryService = battery
        self.storageService = storage
    }

    func refresh() {
        device = deviceService.snapshot()
        battery = batteryService.current()
        do {
            storage = try storageService.snapshot()
            storageError = nil
        } catch {
            storage = nil
            storageError = error.localizedDescription
        }
    }

    var batteryText: String {
        guard let level = battery?.level else { return "Not available" }
        return Format.percent(level)
    }

    var storageFreeText: String {
        guard let storage else { return "Not available" }
        return "\(Format.bytes(storage.available)) free"
    }
}
