import Foundation
import Network
import CoreLocation
#if !targetEnvironment(simulator)
import idevice
#endif

// Changes the phone's GPS location for every app, the same way desktop tools do over USB,
// but from the phone itself: a loopback VPN (LocalDevVPN) lets this app reach the phone's own
// developer services at 10.7.0.1, and a pairing file proves the app is trusted.
//
// The call sequence follows the open-source StikDebug project (AGPL-3.0) and uses the
// idevice library (MIT) in Vendor/idevice.

enum GPSSimulationError: LocalizedError {
    case unsupported
    case noPairingFile
    case pairingFile(String)
    case tunnel(String)
    case developerServices(String)
    case locationService(String)
    case notActive

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Changing the GPS location only works on a real iPhone, not in the simulator."
        case .noPairingFile:
            return "No pairing file has been added yet. Open Setup and import one."
        case .pairingFile(let detail):
            if detail.localizedCaseInsensitiveContains("public_key") {
                return "This is the wrong kind of pairing file. iOS 27 needs a Remote Pairing (RPPairing) file, not a Lockdown one. Create it again and choose Remote pairing. (\(detail))"
            }
            return "The pairing file could not be read. Create a new one and import it again. (\(detail))"
        case .tunnel(let detail):
            return "Could not connect to the phone's developer service. Check that LocalDevVPN is connected, the phone is on Wi-Fi, and the pairing file was made after your last passcode change or iOS update. (\(detail))"
        case .developerServices(let detail):
            return "Connected, but the developer tools are not loaded on the phone. After every restart they must be loaded once: plug the phone into the PC and open VirtualLocation in desktop 3uTools, then try again here. (\(detail))"
        case .locationService(let detail):
            return "The phone refused the location change. (\(detail))"
        case .notActive:
            return "No simulated location is active."
        }
    }
}

/// Where the pairing file lives and how it gets there.
enum PairingFileStore {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pairing", isDirectory: true)
    }

    static var url: URL { folder.appendingPathComponent("pairingFile.plist") }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static var importedDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Copies a file picked with the document picker into the app's private storage.
    static func importFile(from source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try store(Data(contentsOf: source))
    }

    /// Picks up a pairing file dropped into the app's Documents folder from a computer
    /// (for example with the desktop 3uTools file manager). Returns true if one was adopted.
    @discardableResult
    static func adoptFromDocuments() -> Bool {
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let files = try? manager.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return false
        }
        let extensions: Set<String> = ["plist", "mobiledevicepairing", "mobiledevicepair"]
        let candidates = files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return first > second
            }
        guard let newest = candidates.first, let data = try? Data(contentsOf: newest) else { return false }
        do {
            try store(data)
            // The file holds connection credentials, so it should not stay in the shared folder.
            try? manager.removeItem(at: newest)
            return true
        } catch {
            return false
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    private static func store(_ data: Data) throws {
        guard !data.isEmpty else {
            throw GPSSimulationError.pairingFile("The file is empty.")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }
}

/// Finds the port of the phone's Remote Pairing service, which changes between restarts.
final class RemotePairingPortFinder {
    static let fallbackPort: UInt16 = 49152

    private let queue = DispatchQueue(label: "remote-pairing-port")
    private let done = DispatchSemaphore(value: 0)
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var port: UInt16?
    private var finished = false
    private var picked = false
    private var pickedLoopback = false

    /// Blocks for up to `timeout` seconds. Call it off the main thread.
    static func find(timeout: TimeInterval = 5) -> UInt16 {
        let finder = RemotePairingPortFinder()
        finder.queue.async { finder.start() }
        _ = finder.done.wait(timeout: .now() + timeout)
        return finder.queue.sync {
            finder.finish()
            return finder.port ?? fallbackPort
        }
    }

    private func start() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_remotepairing._tcp", domain: "local."), using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, !self.finished else { return }
            var choice: (endpoint: NWEndpoint, loopback: Bool)?
            for result in results {
                guard case .service = result.endpoint else { continue }
                let loopback = result.interfaces.contains { $0.name.hasPrefix("lo") }
                if loopback {
                    choice = (result.endpoint, true)
                    break
                }
                if choice == nil { choice = (result.endpoint, false) }
            }
            // Prefer the phone's own (loopback) service over other devices on the network.
            guard let choice, !self.picked || (!self.pickedLoopback && choice.loopback) else { return }
            self.picked = true
            self.pickedLoopback = choice.loopback
            self.connect(to: choice.endpoint, using: parameters)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish() }
        }
        browser.start(queue: queue)
    }

    private func connect(to endpoint: NWEndpoint, using parameters: NWParameters) {
        connection?.cancel()
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        connection.pathUpdateHandler = { [weak self, weak connection] path in
            guard let self, let connection, self.connection === connection, !self.finished else { return }
            if path.status == .satisfied { self.record(from: connection) }
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection, !self.finished else { return }
            switch state {
            case .ready, .waiting:
                self.record(from: connection)
            case .failed:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func record(from connection: NWConnection) {
        guard let endpoint = connection.currentPath?.remoteEndpoint,
              case .hostPort(_, let found) = endpoint, found.rawValue != 0 else { return }
        port = found.rawValue
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        browser?.cancel()
        connection?.cancel()
        done.signal()
    }
}

/// Talks to the phone's developer services. All work happens on one serial queue.
final class GPSSimulatorEngine {
    static let shared = GPSSimulatorEngine()
    static let deviceAddress = "10.7.0.1"

    private let queue = DispatchQueue(label: "gps-simulator", qos: .userInitiated)

    #if !targetEnvironment(simulator)
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remoteServer: OpaquePointer?
    private var simulation: OpaquePointer?
    #endif

    private init() {}

    /// Sets the simulated location, connecting first if needed.
    func set(latitude: Double, longitude: Double) async throws {
        try await run { try self.setSync(latitude: latitude, longitude: longitude) }
    }

    /// Returns the phone to its real location and closes the connection.
    func clear() async throws {
        try await run { try self.clearSync() }
    }

    private func run(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    #if targetEnvironment(simulator)

    private func setSync(latitude: Double, longitude: Double) throws {
        throw GPSSimulationError.unsupported
    }

    private func clearSync() throws {
        throw GPSSimulationError.unsupported
    }

    #else

    /// Reads the message out of a library error and frees it.
    private static func describe(_ error: UnsafeMutablePointer<IdeviceFfiError>) -> String {
        let code = error.pointee.code
        let text = error.pointee.message.map { String(cString: $0) } ?? "no detail"
        idevice_error_free(error)
        return "code \(code): \(text)"
    }

    private func setSync(latitude: Double, longitude: Double) throws {
        // Reuse the open connection when there is one.
        if let simulation {
            if let error = location_simulation_set(simulation, latitude, longitude) {
                _ = Self.describe(error)
                teardown()
            } else {
                return
            }
        }

        guard PairingFileStore.exists else { throw GPSSimulationError.noPairingFile }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(RemotePairingPortFinder.find()).bigEndian
        guard Self.deviceAddress.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            throw GPSSimulationError.tunnel("invalid device address")
        }

        var pairing: OpaquePointer?
        if let error = PairingFileStore.url.path.withCString({ rp_pairing_file_read($0, &pairing) }) {
            throw GPSSimulationError.pairingFile(Self.describe(error))
        }
        guard let pairing else { throw GPSSimulationError.pairingFile("nothing was read") }
        defer { rp_pairing_file_free(pairing) }

        var newAdapter: OpaquePointer?
        var newHandshake: OpaquePointer?
        let tunnelError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride),
                                        "3uToolsMobile", pairing, nil, nil,
                                        &newAdapter, &newHandshake)
            }
        }
        adapter = newAdapter
        handshake = newHandshake
        if let tunnelError {
            let detail = Self.describe(tunnelError)
            teardown()
            throw GPSSimulationError.tunnel(detail)
        }

        var newServer: OpaquePointer?
        if let error = remote_server_connect_rsd(adapter, handshake, &newServer) {
            let detail = Self.describe(error)
            teardown()
            throw GPSSimulationError.developerServices(detail)
        }
        remoteServer = newServer

        var newSimulation: OpaquePointer?
        if let error = location_simulation_new(remoteServer, &newSimulation) {
            let detail = Self.describe(error)
            teardown()
            throw GPSSimulationError.locationService(detail)
        }
        simulation = newSimulation
        // The location client now owns the server connection.
        remoteServer = nil

        if let error = location_simulation_set(simulation, latitude, longitude) {
            let detail = Self.describe(error)
            teardown()
            throw GPSSimulationError.locationService(detail)
        }
    }

    private func clearSync() throws {
        guard let simulation else { throw GPSSimulationError.notActive }
        let error = location_simulation_clear(simulation)
        teardown()
        if let error {
            throw GPSSimulationError.locationService(Self.describe(error))
        }
    }

    private func teardown() {
        if let simulation {
            location_simulation_free(simulation)
            self.simulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    #endif
}

/// Keeps the app running while it is in the background, so the connection that holds the
/// simulated location stays open. iOS allows this for apps that are receiving location updates.
final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundKeepAlive()

    private let manager = CLLocationManager()
    private var running = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard !running else { return }
        running = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if running { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix does not matter; the manager only has to be running.
    }
}
