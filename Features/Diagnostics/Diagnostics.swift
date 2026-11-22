import Foundation
import Observation

struct DiagnosticResult: Equatable {
    let status: DiagnosticStatus
    let detail: String
}

struct DiagnosticCheck: Identifiable, Equatable {
    enum Category: String, CaseIterable {
        case power = "Power"
        case storage = "Storage"
        case network = "Network"
        case performance = "Performance"
        case permissions = "Permissions"
        case hardware = "Hardware availability"
    }

    let id: String
    let title: String
    let systemImage: String
    let category: Category
    let result: DiagnosticResult
}

/// The rules that turn a reading into Passed, Warning or Not Available. Pure, so they are unit tested.
enum DiagnosticRules {
    static func battery(level: Double?, state: BatteryState) -> DiagnosticResult {
        guard let level else {
            return .init(status: .notAvailable, detail: "iOS did not report a battery level.")
        }
        let text = "\(Format.percent(level)), \(state.label.lowercased())"
        if level < 0.20 && !state.isPluggedIn {
            return .init(status: .warning, detail: "\(text). Battery is low.")
        }
        return .init(status: .passed, detail: text)
    }

    static func lowPowerMode(_ enabled: Bool) -> DiagnosticResult {
        enabled
            ? .init(status: .warning, detail: "Low Power Mode is on, so performance and background activity are reduced.")
            : .init(status: .passed, detail: "Low Power Mode is off.")
    }

    static func storage(_ snapshot: StorageSnapshot?) -> DiagnosticResult {
        guard let snapshot, snapshot.total > 0 else {
            return .init(status: .notAvailable, detail: "iOS did not report storage figures.")
        }
        let text = "\(Format.bytes(snapshot.available)) free of \(Format.bytes(snapshot.total))"
        if snapshot.availableFraction < 0.10 {
            return .init(status: .warning, detail: "\(text). Less than 10% free.")
        }
        return .init(status: .passed, detail: text)
    }

    static func network(_ status: NetworkStatus) -> DiagnosticResult {
        guard status.isConnected else {
            return .init(status: .warning, detail: "No network connection.")
        }
        var text = "Connected over \(status.interface)"
        if status.isConstrained { text += ", Low Data Mode on" }
        return .init(status: .passed, detail: text + ".")
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> DiagnosticResult {
        switch state {
        case .nominal, .fair:
            return .init(status: .passed, detail: "Temperature state: \(state.label).")
        case .serious, .critical:
            return .init(status: .warning, detail: "Temperature state: \(state.label). iOS is slowing the phone down to cool it.")
        @unknown default:
            return .init(status: .notAvailable, detail: "iOS reported an unknown temperature state.")
        }
    }

    static func memory(physical: UInt64) -> DiagnosticResult {
        guard physical > 0 else {
            return .init(status: .notAvailable, detail: "iOS did not report installed memory.")
        }
        return .init(status: .passed, detail: "\(Format.bytes(Int64(physical))) installed.")
    }

    static func permission(_ state: PermissionState) -> DiagnosticResult {
        switch state {
        case .granted:
            return .init(status: .passed, detail: "Allowed.")
        case .limited:
            return .init(status: .passed, detail: "Limited access allowed.")
        case .notDetermined:
            return .init(status: .notAvailable, detail: "Not requested yet. It is asked for the first time you use the feature.")
        case .denied:
            return .init(status: .warning, detail: "Denied. Turn it on in Settings to use the feature.")
        case .restricted:
            return .init(status: .warning, detail: "Restricted by device settings.")
        }
    }

    static func hardware(present: Bool, name: String) -> DiagnosticResult {
        present
            ? .init(status: .passed, detail: "\(name) is reported as present.")
            : .init(status: .notAvailable, detail: "\(name) is not reported on this device.")
    }

    static func summary(of checks: [DiagnosticCheck]) -> (passed: Int, warnings: Int, notAvailable: Int) {
        (
            checks.filter { $0.result.status == .passed }.count,
            checks.filter { $0.result.status == .warning }.count,
            checks.filter { $0.result.status == .notAvailable }.count
        )
    }
}

@MainActor
@Observable
final class DiagnosticsViewModel {
    private(set) var checks: [DiagnosticCheck] = []
    private(set) var lastRun: Date?

    private let device: DeviceInfoProviding
    private let battery: BatteryProviding
    private let storage: StorageProviding

    init(device: DeviceInfoProviding = LiveDeviceInfoService(),
         battery: BatteryProviding = LiveBatteryService(),
         storage: StorageProviding = LiveStorageService()) {
        self.device = device
        self.battery = battery
        self.storage = storage
    }

    var summary: (passed: Int, warnings: Int, notAvailable: Int) {
        DiagnosticRules.summary(of: checks)
    }

    func checks(in category: DiagnosticCheck.Category) -> [DiagnosticCheck] {
        checks.filter { $0.category == category }
    }

    func run() {
        let snapshot = device.snapshot()
        let reading = battery.current()
        let storageSnapshot = try? storage.snapshot()
        let network = NetworkMonitor.shared.current
        let hardware = HardwareCapabilityService.read()

        var list: [DiagnosticCheck] = []
        func add(_ id: String, _ title: String, _ image: String, _ category: DiagnosticCheck.Category, _ result: DiagnosticResult) {
            list.append(DiagnosticCheck(id: id, title: title, systemImage: image, category: category, result: result))
        }

        add("battery", "Battery", "battery.75percent", .power,
            DiagnosticRules.battery(level: reading.level, state: reading.state))
        add("lowpower", "Low Power Mode", "leaf.fill", .power,
            DiagnosticRules.lowPowerMode(snapshot.lowPowerMode))
        add("storage", "Free storage", "internaldrive.fill", .storage,
            DiagnosticRules.storage(storageSnapshot))
        add("network", "Network connection", "wifi", .network,
            DiagnosticRules.network(network))
        add("thermal", "Temperature state", "thermometer.medium", .performance,
            DiagnosticRules.thermal(snapshot.thermalState))
        add("memory", "Memory", "memorychip.fill", .performance,
            DiagnosticRules.memory(physical: snapshot.physicalMemory))
        add("perm-camera", "Camera access", "camera.fill", .permissions,
            DiagnosticRules.permission(PermissionService.camera()))
        add("perm-mic", "Microphone access", "mic.fill", .permissions,
            DiagnosticRules.permission(PermissionService.microphone()))
        add("perm-location", "Location access", "location.fill", .permissions,
            DiagnosticRules.permission(PermissionService.location()))
        add("perm-photos", "Photos access", "photo.fill", .permissions,
            DiagnosticRules.permission(PermissionService.photos()))
        add("hw-camera", "Cameras", "camera.aperture", .hardware,
            hardware.cameraCount > 0
                ? DiagnosticResult(status: .passed, detail: "\(hardware.cameraCount) camera(s) reported.")
                : DiagnosticResult(status: .notAvailable, detail: "No cameras reported."))
        add("hw-torch", "Torch", "flashlight.on.fill", .hardware,
            DiagnosticRules.hardware(present: hardware.hasTorch, name: "Torch"))
        add("hw-biometry", "Face ID or Touch ID", "faceid", .hardware,
            hardware.biometry.map { DiagnosticResult(status: .passed, detail: "\($0) is reported.") }
                ?? DiagnosticResult(status: .notAvailable, detail: "No biometric sensor reported."))
        add("hw-accel", "Accelerometer", "move.3d", .hardware,
            DiagnosticRules.hardware(present: hardware.hasAccelerometer, name: "Accelerometer"))
        add("hw-gyro", "Gyroscope", "gyroscope", .hardware,
            DiagnosticRules.hardware(present: hardware.hasGyroscope, name: "Gyroscope"))
        add("hw-baro", "Barometer", "barometer", .hardware,
            DiagnosticRules.hardware(present: hardware.hasBarometer, name: "Barometer"))
        add("hw-haptics", "Haptic engine", "waveform", .hardware,
            DiagnosticRules.hardware(present: hardware.hasHaptics, name: "Haptic engine"))

        checks = list
        lastRun = Date()
    }
}
