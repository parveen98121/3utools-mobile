import SwiftUI
import Observation
import UniformTypeIdentifiers
import UIKit

@MainActor
@Observable
final class GPSSimulationViewModel {
    enum State: Equatable {
        case idle
        case connecting
        case active(latitude: Double, longitude: Double)
        case failed(String)
    }

    static let shared = GPSSimulationViewModel()

    private(set) var state: State = .idle
    private(set) var hasPairingFile = PairingFileStore.exists
    private(set) var pairingDate = PairingFileStore.importedDate
    private(set) var vpnConnected = false
    var setupMessage: String?

    private var resendTimer: Timer?

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var isConnecting: Bool { state == .connecting }

    /// LocalDevVPN gives the phone an address in 10.7.0.x while it is connected.
    func refreshStatus() {
        do {
            if try PairingFileStore.adoptFromDocuments() {
                setupMessage = "A pairing file was found in the app's Documents folder and imported."
            }
        } catch {
            setupMessage = error.localizedDescription
        }
        // A file stored by an earlier version was not checked; drop it if it is not a pairing file.
        if PairingFileStore.exists, let data = try? Data(contentsOf: PairingFileStore.url) {
            do {
                try PairingFileStore.validate(data)
            } catch {
                PairingFileStore.remove()
                setupMessage = "The pairing file added earlier was removed. \(error.localizedDescription)"
            }
        }
        hasPairingFile = PairingFileStore.exists
        pairingDate = PairingFileStore.importedDate
        vpnConnected = NetworkTools.localAddresses().values.contains { $0.hasPrefix("10.7.0.") }
    }

    func importPairingFile(from url: URL) {
        do {
            try PairingFileStore.importFile(from: url)
            setupMessage = "Pairing file imported."
        } catch {
            setupMessage = "The file could not be imported: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    func removePairingFile() {
        PairingFileStore.remove()
        setupMessage = "Pairing file removed."
        refreshStatus()
    }

    /// Makes every app on the phone see this location.
    func start(latitude: Double, longitude: Double) async {
        guard CoordinateParser.validated(latitude: latitude, longitude: longitude) != nil else {
            state = .failed("The coordinates are out of range.")
            return
        }
        refreshStatus()
        guard hasPairingFile else {
            state = .failed(GPSSimulationError.noPairingFile.localizedDescription)
            return
        }
        stopResending()
        state = .connecting
        do {
            try await GPSSimulatorEngine.shared.set(latitude: latitude, longitude: longitude)
            state = .active(latitude: latitude, longitude: longitude)
            BackgroundKeepAlive.shared.start()
            startResending(latitude: latitude, longitude: longitude)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Returns the phone to its real location.
    func stop() async {
        stopResending()
        BackgroundKeepAlive.shared.stop()
        guard isActive else {
            state = .idle
            return
        }
        do {
            try await GPSSimulatorEngine.shared.clear()
            state = .idle
        } catch {
            state = .failed("The real location may not be restored yet: \(error.localizedDescription) Restarting the phone always restores it.")
        }
    }

    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    /// iOS drops a simulated location that is not refreshed, so it is sent again every few seconds.
    private func startResending(latitude: Double, longitude: Double) {
        let timer = Timer(timeInterval: 4, repeats: true) { _ in
            Task {
                try? await GPSSimulatorEngine.shared.set(latitude: latitude, longitude: longitude)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        resendTimer = timer
    }

    private func stopResending() {
        resendTimer?.invalidate()
        resendTimer = nil
    }
}

/// One-time setup for changing the phone's GPS location.
struct GPSSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = GPSSimulationViewModel.shared
    @State private var showImporter = false

    private let pairingTypes: [UTType] = [.propertyList, .data, .item]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Changing the GPS for every app works by connecting this app to the phone's own developer service. That needs the three things below. Steps 1 and 2 are done once; step 3 after every restart of the phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("1. LocalDevVPN") {
                    statusRow("VPN connected", ok: model.vpnConnected,
                              detail: model.vpnConnected
                                  ? "The phone can reach its developer service."
                                  : "Install LocalDevVPN from the App Store, open it and tap Connect. Keep it connected while a fake location is active.")
                    Button("Get LocalDevVPN on the App Store") {
                        if let url = URL(string: "https://apps.apple.com/app/id6755608044") {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    statusRow("Pairing file", ok: model.hasPairingFile,
                              detail: model.hasPairingFile
                                  ? "Imported \(model.pairingDate?.formatted(date: .abbreviated, time: .shortened) ?? "")."
                                  : "Not added yet.")
                    Button("Import pairing file") { showImporter = true }
                    if model.hasPairingFile {
                        Button("Remove pairing file", role: .destructive) { model.removePairingFile() }
                    }
                } header: {
                    Text("2. Pairing file")
                } footer: {
                    Text("""
                    Make it on the PC with the phone plugged in: run idevice_pair (free, from github.com/jkcoxson/idevice_pair), choose Remote pairing (RPPairing), click Create and save the file.

                    Then get the file onto the phone, either way:
                    • In desktop 3uTools open Files > Apps > 3uTools Mobile and copy the file into Documents. This app imports it automatically.
                    • Or send the file to yourself, save it in the Files app, and tap Import above.

                    Keep the file private. A new one is needed after a passcode change or iOS update.
                    """)
                }

                Section {
                    Text("After each restart of the phone, plug it into the PC and open VirtualLocation in desktop 3uTools once. That loads Apple's developer tools onto the phone, which stay loaded until the next restart.")
                        .font(.footnote)
                } header: {
                    Text("3. Developer tools loaded")
                } footer: {
                    Text("Developer Mode must also be on (Settings > Privacy & Security > Developer Mode). It already is if you installed this app with Sideloadly.")
                }

                if let message = model.setupMessage {
                    Section {
                        Text(message).font(.footnote)
                    }
                }

                Section("Good to know") {
                    Text("Every app sees the fake location while it is active, including this app's own blue dot. Some apps and games detect fake locations and can restrict accounts. Stop the simulation, or restart the phone, to return to the real location.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GPS setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refreshStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: pairingTypes, allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { model.importPairingFile(from: url) }
                case .failure(let error):
                    model.setupMessage = error.localizedDescription
                }
            }
            .onAppear { model.refreshStatus() }
        }
    }

    private func statusRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Theme.passed : Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
