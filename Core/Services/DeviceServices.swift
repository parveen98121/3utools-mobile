import Foundation
import UIKit

// MARK: - Device information

struct DeviceSnapshot: Equatable {
    var name: String
    var modelIdentifier: String
    var modelName: String?
    var deviceType: String
    var isSimulator: Bool
    var systemName: String
    var systemVersion: String
    var buildVersion: String?
    var processorCount: Int
    var activeProcessorCount: Int
    var physicalMemory: UInt64
    var screenPoints: CGSize
    var screenScale: CGFloat
    var maximumFramesPerSecond: Int
    var thermalState: ProcessInfo.ThermalState
    var uptime: TimeInterval
    var lowPowerMode: Bool
    var vendorIdentifier: String?

    /// Marketing name when known, otherwise the hardware identifier.
    var displayModel: String { modelName ?? modelIdentifier }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Slightly warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        @unknown default: return "Unknown"
        }
    }
}

@MainActor
protocol DeviceInfoProviding {
    func snapshot() -> DeviceSnapshot
}

@MainActor
struct LiveDeviceInfoService: DeviceInfoProviding {
    /// Nonisolated so the service can be used as a default argument.
    nonisolated init() {}

    func snapshot() -> DeviceSnapshot {
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        let screen = UIScreen.main
        let identifier = Self.modelIdentifier()

        let type: String
        switch device.userInterfaceIdiom {
        case .phone: type = "iPhone"
        case .pad: type = "iPad"
        default: type = "Other"
        }

        return DeviceSnapshot(
            name: device.name,
            modelIdentifier: identifier,
            modelName: DeviceModelCatalog.name(for: identifier),
            deviceType: type,
            isSimulator: Self.isSimulator,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            buildVersion: Self.sysctlString("kern.osversion"),
            processorCount: process.processorCount,
            activeProcessorCount: process.activeProcessorCount,
            physicalMemory: process.physicalMemory,
            screenPoints: screen.bounds.size,
            screenScale: screen.scale,
            maximumFramesPerSecond: screen.maximumFramesPerSecond,
            thermalState: process.thermalState,
            uptime: process.systemUptime,
            lowPowerMode: process.isLowPowerModeEnabled,
            vendorIdentifier: device.identifierForVendor?.uuidString
        )
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Battery

/// `level` runs from 0 to 1 and is nil when iOS reports it as unknown (for example in the simulator).
struct BatteryReading: Equatable {
    let level: Double?
    let state: BatteryState
}

@MainActor
protocol BatteryProviding {
    func current() -> BatteryReading
}

@MainActor
struct LiveBatteryService: BatteryProviding {
    nonisolated init() {}

    func current() -> BatteryReading {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        let raw = device.batteryLevel
        let level: Double? = raw < 0 ? nil : Double(raw)
        let state: BatteryState
        switch device.batteryState {
        case .unplugged: state = .unplugged
        case .charging: state = .charging
        case .full: state = .full
        default: state = .unknown
        }
        return BatteryReading(level: level, state: state)
    }
}

// MARK: - Storage

enum StorageError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "iOS did not return storage figures for this device."
    }
}

@MainActor
protocol StorageProviding {
    func snapshot() throws -> StorageSnapshot
    func appDocumentsSize() -> Int64
}

@MainActor
struct LiveStorageService: StorageProviding {
    nonisolated init() {}

    func snapshot() throws -> StorageSnapshot {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        guard let total = values.volumeTotalCapacity else { throw StorageError.unavailable }
        let available: Int64
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            available = important
        } else if let plain = values.volumeAvailableCapacity {
            available = Int64(plain)
        } else {
            throw StorageError.unavailable
        }
        return StorageSnapshot(total: Int64(total), available: available)
    }

    /// Size of this app's own Documents, Library and tmp folders.
    func appDocumentsSize() -> Int64 {
        let manager = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let folders = ["Documents", "Library", "tmp"].map { home.appendingPathComponent($0) }
        var total: Int64 = 0
        for folder in folders {
            guard let enumerator = manager.enumerator(at: folder,
                                                      includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
