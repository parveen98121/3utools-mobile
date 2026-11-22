import SwiftUI

struct ToolboxView: View {
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                tool("Diagnostics", "Checks with pass or warning", "stethoscope") { DiagnosticsView() }
                tool("Network", "Connection, IP and latency", "network") { NetworkDiagnosticsView() }
                tool("Speed test", "Download and upload", "speedometer") { SpeedTestView() }
                tool("QR scanner", "QR codes and barcodes", "qrcode.viewfinder") { QRScannerView() }
                tool("Files", "Open and preview files", "folder.fill") { FilesView() }
                tool("Wi-Fi", "What iOS shares about Wi-Fi", "wifi") { WiFiInfoView() }
                tool("Settings", "Shortcuts and paths", "gearshape.fill") { SettingsShortcutsView() }
                tool("Backup & export", "Device report and history", "square.and.arrow.up.fill") { BackupExportView() }
                tool("Usage", "Uptime and Screen Time", "hourglass") { UsageStatsView() }
                tool("About & privacy", "What this app does with data", "hand.raised.fill") { AboutView() }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Toolbox")
    }

    private func tool<Destination: View>(_ title: String, _ subtitle: String, _ image: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: image)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}
