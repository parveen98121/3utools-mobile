import Foundation
import CoreLocation
import MapKit
import SwiftUI
import Observation

/// Wraps Core Location. Delegate callbacks arrive on the main thread because the manager is created there.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var permission: PermissionState = .notDetermined
    private(set) var current: CLLocation?
    private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        permission = PermissionService.map(manager.authorizationStatus)
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
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latest = locations.last {
            current = latest
            errorMessage = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

struct SelectedPlace: Equatable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let item: MKMapItem

    var title: String { item.name ?? "Unnamed place" }
    var subtitle: String { LocationViewModel.address(from: item.placemark) }
}

@MainActor
@Observable
final class LocationViewModel {
    let service = LocationService()

    var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    var query = ""
    var latitudeText = ""
    var longitudeText = ""
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var selected: SelectedPlace?
    var message: String?

    var distanceText: String? {
        guard let selected, let current = service.current else { return nil }
        let target = CLLocation(latitude: selected.latitude, longitude: selected.longitude)
        let metres = current.distance(from: target)
        let formatter = MKDistanceFormatter()
        return formatter.string(fromDistance: metres)
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            return
        }
        // A pair of numbers is treated as coordinates, not as a place name.
        if let coordinate = CoordinateParser.parse(text) {
            results = []
            await select(latitude: coordinate.latitude, longitude: coordinate.longitude, name: nil)
            return
        }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let current = service.current {
            request.region = MKCoordinateRegion(center: current.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map(SearchResult.init)
            if results.isEmpty { message = "No places found for “\(text)”." }
        } catch {
            results = []
            message = "Search failed: \(error.localizedDescription)"
        }
    }

    func select(_ result: SearchResult) async {
        let coordinate = result.item.placemark.coordinate
        results = []
        query = ""
        await select(latitude: coordinate.latitude, longitude: coordinate.longitude,
                     name: result.item.name, knownAddress: result.subtitle)
    }

    func selectTypedCoordinates() async {
        guard let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: ".")),
              let coordinate = CoordinateParser.validated(latitude: latitude, longitude: longitude) else {
            message = "Enter a latitude between -90 and 90 and a longitude between -180 and 180."
            return
        }
        await select(latitude: coordinate.latitude, longitude: coordinate.longitude, name: nil)
    }

    /// `moveCamera` is false for a pin dropped by tapping: the pin is already on screen,
    /// so the map keeps its position and zoom instead of jumping.
    func select(latitude: Double, longitude: Double, name: String?, knownAddress: String? = nil,
                moveCamera: Bool = true) async {
        var place = SelectedPlace(name: name ?? "Dropped pin", address: knownAddress ?? "",
                                  latitude: latitude, longitude: longitude)
        latitudeText = Format.coordinate(latitude)
        longitudeText = Format.coordinate(longitude)
        selected = place
        if moveCamera {
            withAnimation {
                camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
            }
        }

        guard knownAddress == nil || knownAddress?.isEmpty == true else { return }
        // Look up the address for a pin dropped on the map or typed as coordinates.
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude)).first {
            place.address = Self.address(from: placemark)
            if name == nil, let found = placemark.name { place.name = found }
            // Only apply if the user has not picked something else meanwhile.
            if selected?.latitude == latitude, selected?.longitude == longitude {
                selected = place
            }
        }
    }

    /// Removes the selected pin and goes back to the phone's real position.
    func restoreActualLocation() {
        selected = nil
        latitudeText = ""
        longitudeText = ""
        if service.permission == .granted {
            withAnimation { camera = .userLocation(fallback: .automatic) }
        } else {
            message = "Location access is off, so the map cannot centre on your position."
        }
    }

    func show(_ saved: SavedLocation) {
        selected = SelectedPlace(name: saved.name, address: saved.address,
                                 latitude: saved.latitude, longitude: saved.longitude)
        latitudeText = Format.coordinate(saved.latitude)
        longitudeText = Format.coordinate(saved.longitude)
        withAnimation {
            camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude),
                                                latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
    }

    func openInMaps() {
        guard let selected else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: selected.coordinate))
        item.name = selected.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    nonisolated static func address(from placemark: CLPlacemark) -> String {
        [placemark.thoroughfare, placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
