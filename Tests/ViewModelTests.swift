import XCTest
@testable import ThreeUTools

@MainActor
private struct FakeDevice: DeviceInfoProviding {
    var value: DeviceSnapshot
    func snapshot() -> DeviceSnapshot { value }
}

@MainActor
private struct FakeBattery: BatteryProviding {
    var value: BatteryReading
    func current() -> BatteryReading { value }
}

@MainActor
private struct FakeStorage: StorageProviding {
    var value: StorageSnapshot?
    func snapshot() throws -> StorageSnapshot {
        guard let value else { throw StorageError.unavailable }
        return value
    }
    func appDocumentsSize() -> Int64 { 1234 }
}

private func sampleDevice() -> DeviceSnapshot {
    DeviceSnapshot(
        name: "iPhone",
        modelIdentifier: "iPhone16,1",
        modelName: "iPhone 15 Pro",
        deviceType: "iPhone",
        isSimulator: false,
        systemName: "iOS",
        systemVersion: "18.1",
        buildVersion: "22B83",
        processorCount: 6,
        activeProcessorCount: 6,
        physicalMemory: 8_000_000_000,
        screenPoints: CGSize(width: 393, height: 852),
        screenScale: 3,
        maximumFramesPerSecond: 120,
        thermalState: .nominal,
        uptime: 3600,
        lowPowerMode: false,
        vendorIdentifier: "TEST"
    )
}

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testRefreshLoadsEverything() {
        let model = HomeViewModel(
            device: FakeDevice(value: sampleDevice()),
            battery: FakeBattery(value: BatteryReading(level: 0.82, state: .charging)),
            storage: FakeStorage(value: StorageSnapshot(total: 128_000_000_000, available: 98_000_000_000))
        )
        model.refresh()
        XCTAssertEqual(model.device?.displayModel, "iPhone 15 Pro")
        XCTAssertEqual(model.batteryText, "82%")
        XCTAssertEqual(model.storageFreeText, "98.0 GB free")
        XCTAssertNil(model.storageError)
    }

    func testMissingReadingsAreReportedAsNotAvailable() {
        let model = HomeViewModel(
            device: FakeDevice(value: sampleDevice()),
            battery: FakeBattery(value: BatteryReading(level: nil, state: .unknown)),
            storage: FakeStorage(value: nil)
        )
        model.refresh()
        XCTAssertEqual(model.batteryText, "Not available")
        XCTAssertEqual(model.storageFreeText, "Not available")
        XCTAssertNotNil(model.storageError)
    }
}

@MainActor
final class StorageViewModelTests: XCTestCase {
    func testLoadSuccess() {
        let model = StorageViewModel(storage: FakeStorage(value: StorageSnapshot(total: 100, available: 5)))
        model.load()
        XCTAssertEqual(model.snapshot, StorageSnapshot(total: 100, available: 5))
        XCTAssertEqual(model.appSize, 1234)
        XCTAssertEqual(model.recommendations.first?.level, .urgent)
    }

    func testLoadFailure() {
        let model = StorageViewModel(storage: FakeStorage(value: nil))
        model.load()
        XCTAssertNil(model.snapshot)
        if case .failed = model.state {} else { XCTFail("Expected the failed state") }
        XCTAssertTrue(model.recommendations.isEmpty)
    }
}

@MainActor
final class DiagnosticsViewModelTests: XCTestCase {
    func testRunProducesEveryCategoryAndUsesInjectedReadings() {
        let model = DiagnosticsViewModel(
            device: FakeDevice(value: sampleDevice()),
            battery: FakeBattery(value: BatteryReading(level: 0.05, state: .unplugged)),
            storage: FakeStorage(value: StorageSnapshot(total: 100, available: 50))
        )
        model.run()
        XCTAssertFalse(model.checks.isEmpty)
        XCTAssertEqual(model.checks.first { $0.id == "battery" }?.result.status, .warning)
        XCTAssertEqual(model.checks.first { $0.id == "storage" }?.result.status, .passed)
        let summary = model.summary
        XCTAssertEqual(summary.passed + summary.warnings + summary.notAvailable, model.checks.count)
        XCTAssertNotNil(model.lastRun)
    }
}

final class DeviceReportTests: XCTestCase {
    @MainActor
    func testReportOmitsVendorIdentifierAndEncodes() throws {
        let report = DeviceReport.make(
            device: sampleDevice(),
            battery: BatteryReading(level: 0.5, state: .unplugged),
            storage: StorageSnapshot(total: 100, available: 40),
            checks: [],
            installIdentifier: "install-1",
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(report.batteryLevelPercent, 50)
        let text = String(decoding: try report.json(), as: UTF8.self)
        XCTAssertTrue(text.contains("install-1"))
        XCTAssertFalse(text.contains("TEST"), "The vendor identifier must not be exported")
    }
}
