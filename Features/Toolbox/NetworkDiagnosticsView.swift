import SwiftUI
import Observation

@MainActor
@Observable
final class NetworkDiagnosticsViewModel {
    var host = "apple.com"
    private(set) var status = NetworkMonitor.shared.current
    private(set) var wifiAddress: String?
    private(set) var cellularAddress: String?
    private(set) var dnsTime: TimeInterval?
    private(set) var httpsTime: TimeInterval?
    private(set) var failure: String?
    private(set) var isRunning = false
    private(set) var hasRun = false

    func refresh() {
        status = NetworkMonitor.shared.current
        wifiAddress = NetworkTools.wifiAddress()
        cellularAddress = NetworkTools.cellularAddress()
    }

    func runLatencyTest() async {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        guard !target.isEmpty, !isRunning else { return }
        isRunning = true
        failure = nil
        dnsTime = await NetworkTools.dnsLookupTime(host: target)
        do {
            httpsTime = try await NetworkTools.httpsRoundTrip(host: target)
        } catch {
            httpsTime = nil
            failure = error.localizedDescription
        }
        hasRun = true
        isRunning = false
    }
}

struct NetworkDiagnosticsView: View {
    @State private var model = NetworkDiagnosticsViewModel()

    var body: some View {
        List {
            Section("Connection") {
                InfoRow("Status", model.status.isConnected ? "Connected" : "Not connected", source: .live)
                InfoRow("Type", model.status.interface)
                InfoRow("Metered connection", model.status.isExpensive ? "Yes" : "No",
                        note: "Mobile data and personal hotspots count as metered.")
                InfoRow("Low Data Mode", model.status.isConstrained ? "On" : "Off")
                InfoRow("IPv4", model.status.supportsIPv4 ? "Supported" : "Not supported")
                InfoRow("IPv6", model.status.supportsIPv6 ? "Supported" : "Not supported")
            }

            Section("Addresses") {
                InfoRow("Wi-Fi IP address", model.wifiAddress)
                InfoRow("Mobile data IP address", model.cellularAddress)
            }

            Section {
                TextField("Host name", text: $model.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await model.runLatencyTest() }
                } label: {
                    if model.isRunning {
                        HStack { ProgressView(); Text("Testing…") }
                    } else {
                        Text("Run test")
                    }
                }
                .disabled(model.isRunning)

                if model.hasRun {
                    InfoRow("Name lookup time", model.dnsTime.map(Format.milliseconds), source: .live,
                            note: model.dnsTime == nil ? "The host name could not be resolved." : "Can be near zero when iOS already has the answer cached.")
                    InfoRow("HTTPS round trip", model.httpsTime.map(Format.milliseconds), source: .live,
                            note: model.failure ?? "Time for one secure request to complete, including connection setup.")
                }
            } header: {
                Text("Response time")
            } footer: {
                Text("iOS does not let apps send ping (ICMP) packets without special handling, so this measures a normal web request instead.")
            }
        }
        .navigationTitle("Network")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { model.refresh() }
        .onAppear { model.refresh() }
        .onChange(of: NetworkMonitor.shared.status) { _, _ in model.refresh() }
    }
}

struct WiFiInfoView: View {
    @State private var status = NetworkMonitor.shared.current
    @State private var address: String?

    var body: some View {
        List {
            Section("Available") {
                InfoRow("Connected over Wi-Fi", status.interface == "Wi-Fi" ? "Yes" : "No", source: .live)
                InfoRow("Wi-Fi IP address", address)
                InfoRow("Low Data Mode", status.isConstrained ? "On" : "Off")
            }
            Section("Not available") {
                InfoRow("Network name (SSID)", nil)
                InfoRow("Router address (BSSID)", nil)
                InfoRow("Signal strength", nil)
                RestrictedFeatureView(
                    title: "Why these are missing",
                    message: "The network name needs Apple's “Access Wi-Fi Information” capability, which is not included when an app is signed with a free Apple ID. Signal strength and nearby networks are never shared with apps.",
                    settingsPath: "Settings > Wi-Fi"
                )
            }
        }
        .navigationTitle("Wi-Fi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: NetworkMonitor.shared.status) { _, _ in refresh() }
    }

    private func refresh() {
        status = NetworkMonitor.shared.current
        address = NetworkTools.wifiAddress()
    }
}
