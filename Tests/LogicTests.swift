import XCTest
@testable import ThreeUTools

final class FormatTests: XCTestCase {
    func testBytesUsesDecimalUnits() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(999), "999 B")
        XCTAssertEqual(Format.bytes(1_500), "1.5 KB")
        XCTAssertEqual(Format.bytes(128_000_000_000), "128 GB")
        XCTAssertEqual(Format.bytes(63_400_000_000), "63.4 GB")
        XCTAssertEqual(Format.bytes(-5), "0 B")
    }

    func testPercentRoundsAndClamps() {
        XCTAssertEqual(Format.percent(0.823), "82%")
        XCTAssertEqual(Format.percent(0.005), "1%")
        XCTAssertEqual(Format.percent(1.4), "100%")
        XCTAssertEqual(Format.percent(-1), "0%")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(42), "42s")
        XCTAssertEqual(Format.duration(300), "5m")
        XCTAssertEqual(Format.duration(3 * 3600 + 12 * 60), "3h 12m")
        XCTAssertEqual(Format.duration(93_784), "1d 2h")
    }

    func testSpeedAndMilliseconds() {
        XCTAssertEqual(Format.speed(42.345), "42.3 Mbps")
        XCTAssertEqual(Format.milliseconds(0.0456), "46 ms")
    }
}

final class DeviceModelCatalogTests: XCTestCase {
    func testKnownIdentifier() {
        XCTAssertEqual(DeviceModelCatalog.name(for: "iPhone16,1"), "iPhone 15 Pro")
        XCTAssertEqual(DeviceModelCatalog.displayName(for: "iPhone14,5"), "iPhone 13")
    }

    func testUnknownIdentifierFallsBackToIdentifier() {
        XCTAssertNil(DeviceModelCatalog.name(for: "iPhone99,9"))
        XCTAssertEqual(DeviceModelCatalog.displayName(for: "iPhone99,9"), "iPhone99,9")
    }
}

final class BatteryMathTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(_ minutes: Double, _ level: Double, _ state: BatteryState) -> BatteryPoint {
        BatteryPoint(date: base.addingTimeInterval(minutes * 60), level: level, state: state)
    }

    func testFirstSampleIsAlwaysRecorded() {
        XCTAssertTrue(BatteryMath.shouldRecord(last: nil, new: point(0, 0.5, .unplugged)))
    }

    func testRepeatWithinAMinuteIsSkipped() {
        let last = point(0, 0.5, .unplugged)
        XCTAssertFalse(BatteryMath.shouldRecord(last: last, new: point(0.5, 0.5, .unplugged)))
        XCTAssertTrue(BatteryMath.shouldRecord(last: last, new: point(2, 0.5, .unplugged)))
    }

    func testChangeOfLevelOrStateIsRecorded() {
        let last = point(0, 0.5, .unplugged)
        XCTAssertTrue(BatteryMath.shouldRecord(last: last, new: point(0.1, 0.51, .unplugged)))
        XCTAssertTrue(BatteryMath.shouldRecord(last: last, new: point(0.1, 0.5, .charging)))
    }

    func testChargingSessionsAreGrouped() {
        let points = [
            point(0, 0.40, .unplugged),
            point(5, 0.41, .charging),
            point(20, 0.60, .charging),
            point(40, 0.80, .full),
            point(45, 0.79, .unplugged),
            point(100, 0.70, .charging),
            point(110, 0.75, .charging)
        ]
        let sessions = BatteryMath.chargingSessions(from: points)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].startLevel, 0.41)
        XCTAssertEqual(sessions[0].endLevel, 0.80)
        XCTAssertEqual(sessions[0].duration, 35 * 60)
        XCTAssertEqual(sessions[1].gained, 0.05, accuracy: 0.0001)
    }

    func testLongGapSplitsASession() {
        let points = [
            point(0, 0.30, .charging),
            point(10, 0.40, .charging),
            point(500, 0.90, .charging),
            point(510, 0.95, .charging)
        ]
        XCTAssertEqual(BatteryMath.chargingSessions(from: points).count, 2)
    }

    func testSingleChargingSampleIsNotASession() {
        XCTAssertTrue(BatteryMath.chargingSessions(from: [point(0, 0.5, .charging)]).isEmpty)
    }

    func testRangeFilter() {
        let now = base.addingTimeInterval(86_400 * 3)
        let points = [point(0, 0.5, .unplugged), BatteryPoint(date: now.addingTimeInterval(-3600), level: 0.6, state: .unplugged)]
        XCTAssertEqual(BatteryMath.points(points, within: 86_400, endingAt: now).count, 1)
        XCTAssertEqual(BatteryMath.points(points, within: 7 * 86_400, endingAt: now).count, 2)
    }
}

final class StorageMathTests: XCTestCase {
    func testSnapshotMaths() {
        let snapshot = StorageSnapshot(total: 100, available: 25)
        XCTAssertEqual(snapshot.used, 75)
        XCTAssertEqual(snapshot.usedFraction, 0.75)
        XCTAssertEqual(snapshot.availableFraction, 0.25)
    }

    func testZeroTotalDoesNotDivideByZero() {
        let snapshot = StorageSnapshot(total: 0, available: 0)
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func testHealthyStorageGivesGoodRecommendation() {
        let result = StorageMath.recommendations(storage: StorageSnapshot(total: 100, available: 60), photos: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.level, .good)
    }

    func testVeryLowStorageIsUrgent() {
        let result = StorageMath.recommendations(storage: StorageSnapshot(total: 100, available: 5), photos: nil)
        XCTAssertEqual(result.first?.level, .urgent)
    }

    func testLowStorageIsAdvice() {
        let result = StorageMath.recommendations(storage: StorageSnapshot(total: 100, available: 15), photos: nil)
        XCTAssertEqual(result.first?.level, .advice)
    }

    func testLargePhotoLibraryAndManyVideosAreMentioned() {
        let stats = PhotoLibraryStats(photoCount: 5000, videoCount: 300, estimatedBytes: 40)
        let result = StorageMath.recommendations(storage: StorageSnapshot(total: 100, available: 50), photos: stats)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.level == .advice })
    }
}

final class CoordinateParserTests: XCTestCase {
    func testParsesCommaAndSpaceSeparatedPairs() {
        XCTAssertEqual(CoordinateParser.parse("28.6139, 77.2090"), Coordinate(latitude: 28.6139, longitude: 77.2090))
        XCTAssertEqual(CoordinateParser.parse("-33.8688 151.2093"), Coordinate(latitude: -33.8688, longitude: 151.2093))
    }

    func testRejectsOutOfRangeAndMalformedInput() {
        XCTAssertNil(CoordinateParser.parse("91, 10"))
        XCTAssertNil(CoordinateParser.parse("10, 181"))
        XCTAssertNil(CoordinateParser.parse("New Delhi"))
        XCTAssertNil(CoordinateParser.parse("12.5"))
        XCTAssertNil(CoordinateParser.parse("1 2 3"))
        XCTAssertNil(CoordinateParser.validated(latitude: .nan, longitude: 0))
    }
}

final class SpeedMathTests: XCTestCase {
    func testMegabitsPerSecond() {
        XCTAssertEqual(SpeedMath.megabitsPerSecond(bytes: 12_500_000, seconds: 1), 100, accuracy: 0.0001)
        XCTAssertEqual(SpeedMath.megabitsPerSecond(bytes: 25_000_000, seconds: 4), 50, accuracy: 0.0001)
    }

    func testZeroInputsGiveZero() {
        XCTAssertEqual(SpeedMath.megabitsPerSecond(bytes: 0, seconds: 1), 0)
        XCTAssertEqual(SpeedMath.megabitsPerSecond(bytes: 100, seconds: 0), 0)
    }
}

final class DiagnosticRulesTests: XCTestCase {
    func testBattery() {
        XCTAssertEqual(DiagnosticRules.battery(level: nil, state: .unknown).status, .notAvailable)
        XCTAssertEqual(DiagnosticRules.battery(level: 0.10, state: .unplugged).status, .warning)
        XCTAssertEqual(DiagnosticRules.battery(level: 0.10, state: .charging).status, .passed)
        XCTAssertEqual(DiagnosticRules.battery(level: 0.80, state: .unplugged).status, .passed)
    }

    func testStorage() {
        XCTAssertEqual(DiagnosticRules.storage(nil).status, .notAvailable)
        XCTAssertEqual(DiagnosticRules.storage(StorageSnapshot(total: 100, available: 5)).status, .warning)
        XCTAssertEqual(DiagnosticRules.storage(StorageSnapshot(total: 100, available: 50)).status, .passed)
    }

    func testThermalAndLowPower() {
        XCTAssertEqual(DiagnosticRules.thermal(.nominal).status, .passed)
        XCTAssertEqual(DiagnosticRules.thermal(.serious).status, .warning)
        XCTAssertEqual(DiagnosticRules.lowPowerMode(true).status, .warning)
        XCTAssertEqual(DiagnosticRules.lowPowerMode(false).status, .passed)
    }

    func testNetwork() {
        var status = NetworkStatus.unknown
        XCTAssertEqual(DiagnosticRules.network(status).status, .warning)
        status.isConnected = true
        status.interface = "Wi-Fi"
        XCTAssertEqual(DiagnosticRules.network(status).status, .passed)
    }

    func testPermissions() {
        XCTAssertEqual(DiagnosticRules.permission(.granted).status, .passed)
        XCTAssertEqual(DiagnosticRules.permission(.limited).status, .passed)
        XCTAssertEqual(DiagnosticRules.permission(.notDetermined).status, .notAvailable)
        XCTAssertEqual(DiagnosticRules.permission(.denied).status, .warning)
    }

    func testHardwareAndSummary() {
        XCTAssertEqual(DiagnosticRules.hardware(present: true, name: "Gyroscope").status, .passed)
        XCTAssertEqual(DiagnosticRules.hardware(present: false, name: "Barometer").status, .notAvailable)

        let checks = [
            DiagnosticCheck(id: "a", title: "A", systemImage: "", category: .power, result: .init(status: .passed, detail: "")),
            DiagnosticCheck(id: "b", title: "B", systemImage: "", category: .power, result: .init(status: .warning, detail: "")),
            DiagnosticCheck(id: "c", title: "C", systemImage: "", category: .power, result: .init(status: .notAvailable, detail: ""))
        ]
        let summary = DiagnosticRules.summary(of: checks)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.warnings, 1)
        XCTAssertEqual(summary.notAvailable, 1)
    }
}
