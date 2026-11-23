import XCTest
@testable import ThreeUTools

@MainActor
final class VirtualLocationManagerTests: XCTestCase {
    /// A separate, empty store for each test, so tests never see each other's data or the app's.
    private var defaults: UserDefaults {
        if let existing = store { return existing }
        let suite = "virtual-location-tests-\(UUID().uuidString)"
        let fresh = UserDefaults(suiteName: suite)!
        store = fresh
        return fresh
    }

    private var store: UserDefaults?

    func testStartsInactive() {
        let manager = VirtualLocationManager(defaults: defaults)
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.current)
    }

    func testSetStoresValidatedLocation() {
        let manager = VirtualLocationManager(defaults: defaults)
        XCTAssertTrue(manager.set(name: "New Delhi", address: "India", latitude: 28.6139, longitude: 77.2090))
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.current?.name, "New Delhi")
        XCTAssertEqual(manager.current?.point, Coordinate(latitude: 28.6139, longitude: 77.2090))
    }

    func testOutOfRangeCoordinatesAreRejectedAndStateIsKept() {
        let manager = VirtualLocationManager(defaults: defaults)
        XCTAssertFalse(manager.set(name: "Bad", address: "", latitude: 95, longitude: 10))
        XCTAssertFalse(manager.isActive)

        manager.set(name: "Good", address: "", latitude: 10, longitude: 10)
        XCTAssertFalse(manager.set(name: "Bad", address: "", latitude: 10, longitude: 200))
        XCTAssertEqual(manager.current?.name, "Good")
    }

    func testEmptyNameGetsADefault() {
        let manager = VirtualLocationManager(defaults: defaults)
        manager.set(name: "", address: "", latitude: 1, longitude: 2)
        XCTAssertEqual(manager.current?.name, "Virtual location")
    }

    func testLocationSurvivesReopeningTheApp() {
        VirtualLocationManager(defaults: defaults).set(name: "Mumbai", address: "", latitude: 19.0760, longitude: 72.8777)
        let reopened = VirtualLocationManager(defaults: defaults)
        XCTAssertEqual(reopened.current?.name, "Mumbai")
        XCTAssertEqual(reopened.current?.latitude, 19.0760)
    }

    func testRestoreClearsStateAndStorage() {
        let manager = VirtualLocationManager(defaults: defaults)
        manager.set(name: "Mumbai", address: "", latitude: 19.0760, longitude: 72.8777)
        manager.restore()
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(VirtualLocationManager(defaults: defaults).current)
    }

    func testEffectiveLocationPrefersVirtualThenActual() {
        let manager = VirtualLocationManager(defaults: defaults)
        let actual = Coordinate(latitude: 1, longitude: 1)
        XCTAssertEqual(manager.effectiveLocation(actual: actual), actual)
        XCTAssertNil(manager.effectiveLocation(actual: nil))

        manager.set(name: "A", address: "", latitude: 5, longitude: 6)
        XCTAssertEqual(manager.effectiveLocation(actual: actual), Coordinate(latitude: 5, longitude: 6))
        XCTAssertEqual(manager.effectiveLocation(actual: nil), Coordinate(latitude: 5, longitude: 6))
    }

    func testDistanceFromActualNeedsBothLocations() {
        let manager = VirtualLocationManager(defaults: defaults)
        XCTAssertNil(manager.distanceFromActual(Coordinate(latitude: 0, longitude: 0)))
        manager.set(name: "A", address: "", latitude: 0, longitude: 1)
        XCTAssertNil(manager.distanceFromActual(nil))
        let metres = manager.distanceFromActual(Coordinate(latitude: 0, longitude: 0))
        XCTAssertEqual(metres ?? 0, 111_195, accuracy: 200)
    }
}

final class GeoMathTests: XCTestCase {
    func testDistanceBetweenSamePointIsZero() {
        let point = Coordinate(latitude: 28.6139, longitude: 77.2090)
        XCTAssertEqual(GeoMath.distance(from: point, to: point), 0, accuracy: 0.001)
    }

    func testDelhiToMumbaiIsAbout1150Kilometres() {
        let delhi = Coordinate(latitude: 28.6139, longitude: 77.2090)
        let mumbai = Coordinate(latitude: 19.0760, longitude: 72.8777)
        XCTAssertEqual(GeoMath.distance(from: delhi, to: mumbai), 1_150_000, accuracy: 15_000)
    }

    func testDistanceText() {
        XCTAssertEqual(GeoMath.distanceText(850), "850 m")
        XCTAssertEqual(GeoMath.distanceText(2740), "2.7 km")
        XCTAssertEqual(GeoMath.distanceText(1_150_000), "1150 km")
    }
}

@MainActor
final class LocationHistoryManagerTests: XCTestCase {
    func testMatchesUsesATightTolerance() {
        let saved = SavedLocation(name: "A", address: "", latitude: 10, longitude: 20)
        XCTAssertTrue(LocationHistoryManager.matches(saved, latitude: 10.000001, longitude: 20.000001))
        XCTAssertFalse(LocationHistoryManager.matches(saved, latitude: 10.001, longitude: 20))
    }

    func testRecentsAreNewestFirstAndLimited() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = (0..<5).map {
            SavedLocation(name: "P\($0)", address: "", latitude: Double($0), longitude: 0,
                          date: base.addingTimeInterval(Double($0) * 60))
        }
        let recents = LocationHistoryManager.recents(from: saved, limit: 3)
        XCTAssertEqual(recents.map(\.name), ["P4", "P3", "P2"])
    }
}
