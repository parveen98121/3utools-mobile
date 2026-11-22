import SwiftUI
import UIKit

struct HomeView: View {
    @State private var model = HomeViewModel()
    @State private var diagnostics = DiagnosticsViewModel()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                header

                LazyVGrid(columns: columns, spacing: 12) {
                    NavigationLink { BatteryView() } label: { batteryCard }
                    NavigationLink { StorageView() } label: { storageCard }
                }
                .buttonStyle(.plain)

                NavigationLink { DiagnosticsView() } label: { diagnosticsCard }
                    .buttonStyle(.plain)

                NavigationLink { DeviceInfoView() } label: { deviceCard }
                    .buttonStyle(.plain)

                quickActions
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("3uTools Mobile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { reload() }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in reload() }
    }

    private func reload() {
        model.refresh()
        diagnostics.run()
    }

    // MARK: - Sections

    private var header: some View {
        GradientHeader {
            HStack(spacing: 18) {
                DeviceIllustration(
                    title: model.device?.displayModel ?? "iPhone",
                    subtitle: model.device.map { "\($0.systemName) \($0.systemVersion)" } ?? "",
                    batteryFraction: model.battery?.level
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.device?.name ?? "iPhone")
                        .font(.title2.weight(.bold))
                    Text(model.device?.displayModel ?? "")
                        .font(.headline)
                    if let device = model.device {
                        Text("\(device.systemName) \(device.systemVersion)")
                            .font(.subheadline)
                    }
                    Spacer(minLength: 4)
                    if let storage = model.storage {
                        Label("\(Format.bytes(storage.total)) storage", systemImage: "internaldrive")
                            .font(.footnote)
                    }
                    if let battery = model.battery {
                        Label(battery.state.label, systemImage: battery.state.isPluggedIn ? "bolt.fill" : "battery.100percent")
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
        }
    }

    private var batteryCard: some View {
        InfoCard(title: "Battery", systemImage: "battery.75percent", showsChevron: true) {
            HStack(spacing: 12) {
                RingGauge(progress: model.battery?.level ?? 0, lineWidth: 8) {
                    Image(systemName: model.battery?.state.isPluggedIn == true ? "bolt.fill" : "battery.50percent")
                        .font(.footnote)
                        .foregroundStyle(Theme.gradient)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.batteryText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                    Text(model.battery?.state.label ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Health: not available to apps")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var storageCard: some View {
        InfoCard(title: "Storage", systemImage: "internaldrive.fill", showsChevron: true) {
            HStack(spacing: 12) {
                RingGauge(progress: model.storage?.usedFraction ?? 0, lineWidth: 8) {
                    Text(model.storage.map { Format.percent($0.usedFraction) } ?? "–")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.storageFreeText)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(model.storage.map { "of \(Format.bytes($0.total))" } ?? (model.storageError ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Used space shown in the ring")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var diagnosticsCard: some View {
        let counts = diagnostics.summary
        return InfoCard(title: "Diagnostics", systemImage: "stethoscope", showsChevron: true) {
            HStack(spacing: 16) {
                Label("\(counts.passed) passed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.passed)
                Label("\(counts.warnings) warning", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Label("\(counts.notAvailable) n/a", systemImage: "minus.circle.fill")
                    .foregroundStyle(Theme.unavailable)
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var deviceCard: some View {
        InfoCard(title: "Device information", systemImage: "info.circle.fill", showsChevron: true) {
            if let device = model.device {
                VStack(spacing: 8) {
                    summaryRow("Model", device.displayModel)
                    summaryRow("Identifier", device.modelIdentifier)
                    summaryRow("Memory", Format.bytes(Int64(device.physicalMemory)))
                    summaryRow("Running for", Format.duration(device.uptime))
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            NavigationLink { SpeedTestView() } label: {
                Label("Speed test", systemImage: "speedometer")
            }
            NavigationLink { QRScannerView() } label: {
                Label("QR scanner", systemImage: "qrcode.viewfinder")
            }
        }
        .buttonStyle(GradientButtonStyle())
    }
}
