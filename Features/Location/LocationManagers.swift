import Foundation
import CoreLocation
import MapKit
import SwiftUI
import SwiftData
import Observation

// The Virtual Location feature is split into five independent managers.
// None of them needs a computer, a cable, a pairing file or any other device:
// everything runs on the phone with MapKit, Core Location and local storage.

// MARK: - Shared types

struct SelectedPlace: Equatable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var point: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let item: MKMapItem

    var title: String { item.name ?? "Unnamed place" }
    var subtitle: String { LocationSearchManager.address(from: item.placemark) }
}

/// The location this app is using in place of the phone's actual one.
struct VirtualLocation: Codable, Equatable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var setAt: Date

    var point: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - VirtualLocationManager

/// Holds the app's virtual location. It is the single source of truth that every
/// location-dependent feature inside the app reads from.
///
/// This changes the location used inside this app only. iOS gives apps no public way
/// to change the GPS location that other apps receive.
@MainActor
@Observable
final class VirtualLocationManager {
    static let shared = VirtualLocationManager()

    private(set) var current: VirtualLocation?

    private let defaults: UserDefaults
    private let storageKey = "virtual-location"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(VirtualLocation.self, from: data),
           CoordinateParser.validated(latitude: saved.latitude, longitude: saved.longitude) != nil {
            current = saved
        }
    }

    var isActive: Bool { current != nil }

    /// Validates the coordinates and makes them the app's location. Returns false when they are out of range.
    @discardableResult
    func set(name: String, address: String, latitude: Double, longitude: Double, now: Date = Date()) -> Bool {
        guard CoordinateParser.validated(latitude: latitude, longitude: longitude) != nil else { return false }
        let location = VirtualLocation(name: name.isEmpty ? "Virtual location" : name, address: address,
                                       latitude: latitude, longitude: longitude, setAt: now)
        current = location
        if let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: storageKey)
        }
        return true
    }

    /// Goes back to using the phone's actual location.
    func restore() {
        current = nil
        defaults.removeObject(forKey: storageKey)
    }

    /// The location the app's features should use: the virtual one when set, otherwise the actual one.
    func effectiveLocation(actual: Coordinate?) -> Coordinate? {
        current?.point ?? actual
    }

    /// Distance in metres between the phone's actual position and the virtual location.
    func distanceFromActual(_ actual: Coordinate?) -> Double? {
        guard let current, let actual else { return nil }
        return GeoMath.distance(from: actual, to: current.point)
    }
}

// MARK: - LocationPermissionManager

/// Owns Core Location: permission state and the phone's actual position.
/// Delegate callbacks arrive on the main thread because the manager is created there.
@Observable
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    private(set) var permission: PermissionState = .notDetermined
    private(set) var actual: CLLocation?
    private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        permission = PermissionService.map(manager.authorizationStatus)
    }

    var actualPoint: Coordinate? {
        actual.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    /// Plain-language description of the current permission state.
    var explanation: String {
        switch permission {
        case .notDetermined:
            return "Allow location access to see your actual position and the distance to the places you pick. The app works without it."
        case .granted, .limited:
            return "Location access is on."
        case .denied:
            return "Location access is off. Everything still works; only your actual position and distances are hidden."
        case .restricted:
            return "Location access is restricted on this phone. Everything still works; only your actual position and distances are hidden."
        }
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        permission = PermissionService.map(manager.authorizationStatus)
        if permission == .granted {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permission = PermissionService.map(manager.authorizationStatus)
        if permission == .granted {
            manager.startUpdatingLocation()
        } else {
            actual = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latest = locations.last {
            actual = latest
            errorMessage = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

// MARK: - LocationSearchManager

/// Finds places and addresses, converts addresses to coordinates and back.
@MainActor
@Observable
final class LocationSearchManager {
    var query = ""
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    var errorMessage: String?

    /// What a search produced: a typed coordinate, a list of places, or nothing.
    enum Outcome: Equatable {
        case coordinate(Coordinate)
        case places(Int)
        case nothing
    }

    /// Searches for the current query. `near` biases results towards the location the app is using.
    func search(near: Coordinate?) async -> Outcome {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            return .nothing
        }
        // A pair of numbers is treated as latitude and longitude, not as a place name.
        if let coordinate = CoordinateParser.parse(text) {
            results = []
            return .coordinate(coordinate)
        }

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let near {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                latitudinalMeters: 200_000, longitudinalMeters: 200_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map { SearchResult(item: $0) }
            if results.isEmpty {
                errorMessage = "No places found for “\(text)”."
                return .nothing
            }
            return .places(results.count)
        } catch {
            results = []
            errorMessage = Self.message(for: error, searching: text)
            return .nothing
        }
    }

    func clear() {
        query = ""
        results = []
    }

    /// Looks up the name and address of a coordinate. Returns nil when offline or nothing is known.
    func reverseGeocode(latitude: Double, longitude: Double) async -> (name: String?, address: String)? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return (placemark.name, Self.address(from: placemark))
    }

    static func message(for error: Error, searching text: String) -> String {
        let code = (error as NSError).code
        if (error as NSError).domain == MKError.errorDomain, code == MKError.Code.placemarkNotFound.rawValue {
            return "No places found for “\(text)”."
        }
        if (error as NSError).domain == NSURLErrorDomain || code == MKError.Code.serverFailure.rawValue
            || code == MKError.Code.loadingThrottled.rawValue {
            return "Search needs an internet connection. You can still type a latitude and longitude, or tap the map."
        }
        return "Search failed: \(error.localizedDescription)"
    }

    nonisolated static func address(from placemark: CLPlacemark) -> String {
        [placemark.thoroughfare, placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - MapLocationManager

/// Owns what the map shows: the camera, the selected pin and zooming.
@MainActor
@Observable
final class MapLocationManager {
    var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    private(set) var selected: SelectedPlace?
    /// Kept up to date by the map so zoom buttons know the current view.
    var visibleRegion: MKCoordinateRegion?

    func select(_ place: SelectedPlace, moveCamera: Bool) {
        selected = place
        if moveCamera { centre(on: place.coordinate) }
    }

    /// Fills in the name and address once they are known, if the pin has not moved meanwhile.
    func updateDetails(name: String?, address: String, forLatitude latitude: Double, longitude: Double) {
        guard var place = selected, place.latitude == latitude, place.longitude == longitude else { return }
        if let name, !name.isEmpty { place.name = name }
        place.address = address
        selected = place
    }

    func clearSelection() {
        selected = nil
    }

    func centre(on coordinate: CLLocationCoordinate2D, metres: Double = 1500) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: metres, longitudinalMeters: metres))
        }
    }

    func showActualLocation() {
        withAnimation { camera = .userLocation(fallback: .automatic) }
    }

    /// A factor below 1 zooms in, above 1 zooms out.
    func zoom(by factor: Double) {
        guard let region = visibleRegion else { return }
        let span = MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.0005), 150),
            longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.0005), 300))
        withAnimation {
            camera = .region(MKCoordinateRegion(center: region.center, span: span))
        }
    }

    func openDirections(to place: SelectedPlace) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

// MARK: - LocationHistoryManager

/// Saves recent places and favourites in the app's local database.
@MainActor
struct LocationHistoryManager {
    let context: ModelContext

    static func matches(_ saved: SavedLocation, latitude: Double, longitude: Double) -> Bool {
        abs(saved.latitude - latitude) < 0.00001 && abs(saved.longitude - longitude) < 0.00001
    }

    /// Adds the place to history, or refreshes the entry that is already there.
    func remember(_ place: SelectedPlace, in saved: [SavedLocation]) {
        if let existing = saved.first(where: { Self.matches($0, latitude: place.latitude, longitude: place.longitude) }) {
            existing.date = Date()
            existing.name = place.name
            if !place.address.isEmpty { existing.address = place.address }
        } else {
            context.insert(SavedLocation(name: place.name, address: place.address,
                                         latitude: place.latitude, longitude: place.longitude))
        }
    }

    func isFavourite(_ place: SelectedPlace, in saved: [SavedLocation]) -> Bool {
        saved.contains { $0.isFavorite && Self.matches($0, latitude: place.latitude, longitude: place.longitude) }
    }

    func toggleFavourite(_ place: SelectedPlace, in saved: [SavedLocation]) {
        if let existing = saved.first(where: { Self.matches($0, latitude: place.latitude, longitude: place.longitude) }) {
            existing.isFavorite.toggle()
        } else {
            context.insert(SavedLocation(name: place.name, address: place.address,
                                         latitude: place.latitude, longitude: place.longitude, isFavorite: true))
        }
    }

    /// The most recently used places, newest first.
    static func recents(from saved: [SavedLocation], limit: Int = 3) -> [SavedLocation] {
        Array(saved.sorted { $0.date > $1.date }.prefix(limit))
    }

    func delete(_ location: SavedLocation) {
        context.delete(location)
    }

    /// Removes history entries but keeps favourites.
    func clearHistory(_ saved: [SavedLocation]) {
        for location in saved where !location.isFavorite {
            context.delete(location)
        }
    }
}
