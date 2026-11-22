import SwiftUI
import SwiftData
import UIKit

// MARK: - Settings shortcuts

struct SettingsShortcutsView: View {
    private let paths: [(title: String, path: String, image: String)] = [
        ("Battery health", "Settings > Battery > Battery Health", "battery.100percent"),
        ("iPhone storage", "Settings > General > iPhone Storage", "internaldrive"),
        ("Software update", "Settings > General > Software Update", "arrow.down.circle"),
        ("About this iPhone", "Settings > General > About", "info.circle"),
        ("Wi-Fi", "Settings > Wi-Fi", "wifi"),
        ("Mobile data", "Settings > Mobile Service", "antenna.radiowaves.left.and.right"),
        ("Privacy and permissions", "Settings > Privacy & Security", "hand.raised"),
        ("Screen Time", "Settings > Screen Time", "hourglass"),
        ("iCloud backup", "Settings > [your name] > iCloud > iCloud Backup", "icloud")
    ]

    var body: some View {
        List {
            Section {
                Button {
                    AppSettings.open()
                } label: {
                    Label("Open this app's page in Settings", systemImage: "gearshape.fill")
                }
            } footer: {
                Text("This is where you change the app's camera, photos and location permissions. iOS offers apps no supported link to any other Settings page, so the paths below are written out.")
            }

            Section("Where to find things") {
                ForEach(paths, id: \.title) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.image)
                            .frame(width: 28)
                            .foregroundStyle(Theme.gradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(entry.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Backup and export

/// The device report that can be exported. It contains no serial number, IMEI or vendor identifier.
struct DeviceReport: Codable, Equatable {
    var generatedAt: Date
    var installIdentifier: String
    var model: String
    var modelIdentifier: String
    var system: String
    var build: String?
    var storageTotalBytes: Int64?
    var storageAvailableBytes: Int64?
    var batteryLevelPercent: Int?
    var batteryState: String
    var memoryBytes: UInt64
    var processorCores: Int
    var diagnostics: [Entry]

    struct Entry: Codable, Equatable {
        var check: String
        var status: String
        var detail: String
    }

    static func make(device: DeviceSnapshot, battery: BatteryReading, storage: StorageSnapshot?,
                     checks: [DiagnosticCheck], installIdentifier: String, now: Date = Date()) -> DeviceReport {
        DeviceReport(
            generatedAt: now,
            installIdentifier: installIdentifier,
            model: device.displayModel,
            modelIdentifier: device.modelIdentifier,
            system: "\(device.systemName) \(device.systemVersion)",
            build: device.buildVersion,
            storageTotalBytes: storage?.total,
            storageAvailableBytes: storage?.available,
            batteryLevelPercent: battery.level.map { Int(($0 * 100).rounded()) },
            batteryState: battery.state.label,
            memoryBytes: device.physicalMemory,
            processorCores: device.processorCount,
            diagnostics: checks.map { Entry(check: $0.title, status: $0.result.status.rawValue, detail: $0.result.detail) }
        )
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

struct BackupExportView: View {
    @Query(sort: \BatterySample.date) private var samples: [BatterySample]
    @State private var reportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                RestrictedFeatureView(
                    title: "Device backups",
                    message: "iOS does not let apps read when the phone was last backed up, or start or restore a backup. Backups are made by iCloud, or by a computer over a cable.",
                    settingsPath: "Settings > [your name] > iCloud > iCloud Backup"
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if let reportURL {
                    ShareLink(item: reportURL) {
                        Label("Share device report (JSON)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        buildReport()
                    } label: {
                        Label("Create device report", systemImage: "doc.badge.plus")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.warning)
                }
            } header: {
                Text("Device report")
            } footer: {
                Text("Contains the model, iOS version, storage, battery reading and diagnostic results. It does not contain a serial number, IMEI or the vendor identifier.")
            }

            Section {
                if samples.isEmpty {
                    Text("No battery history has been recorded yet.").foregroundStyle(.secondary)
                } else {
                    ShareLink(item: batteryCSV) {
                        Label("Share battery history (\(samples.count) readings)", systemImage: "chart.xyaxis.line")
                    }
                }
            } header: {
                Text("Battery history")
            }
        }
        .navigationTitle("Backup & export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var batteryCSV: String {
        let formatter = ISO8601DateFormatter()
        let rows = samples.map { "\(formatter.string(from: $0.date)),\(Int(($0.level * 100).rounded())),\($0.state.label)" }
        return (["date,level_percent,state"] + rows).joined(separator: "\n")
    }

    private func buildReport() {
        let diagnostics = DiagnosticsViewModel()
        diagnostics.run()
        let report = DeviceReport.make(
            device: LiveDeviceInfoService().snapshot(),
            battery: LiveBatteryService().current(),
            storage: try? LiveStorageService().snapshot(),
            checks: diagnostics.checks,
            installIdentifier: KeychainStore().installIdentifier()
        )
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("device-report.json")
            try report.json().write(to: url, options: .atomic)
            reportURL = url
            errorMessage = nil
        } catch {
            errorMessage = "The report could not be created: \(error.localizedDescription)"
        }
    }
}

// MARK: - Usage statistics

struct UsageStatsView: View {
    @State private var uptime = ProcessInfo.processInfo.systemUptime
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section("Available") {
                InfoRow("Awake time since last restart", Format.duration(uptime), source: .live,
                        note: "Counts only the time the phone has been awake, so it runs slower than a clock.")
            }
            Section("Not available") {
                InfoRow("Screen time", nil)
                InfoRow("App usage", nil)
                InfoRow("Pickups and notifications", nil)
                RestrictedFeatureView(
                    title: "Why these are missing",
                    message: "Usage figures are protected by Apple's Screen Time system. Reading them needs the Family Controls capability, which is not included when an app is signed with a free Apple ID.",
                    settingsPath: "Settings > Screen Time"
                )
            }
        }
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in uptime = ProcessInfo.processInfo.systemUptime }
    }
}

// MARK: - About and privacy

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.gradient)
                    Text("3uTools Mobile").font(.title3.weight(.bold))
                    Text("Version \(version)").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Privacy") {
                point("Nothing is collected", "The app has no account, no analytics and no server. Battery history, saved places, speed results and recent files stay on this phone.")
                point("When the app uses the internet", "Only when you ask: the Apps screen asks Apple's App Store lookup for names and icons, the speed and network tests contact the servers they measure, and the map loads tiles and search results from Apple.")
                point("Permissions", "Photos, camera, location and microphone are requested the first time you use the feature that needs them. You can change them at any time in Settings.")
                point("Identifiers", "The app never reads the serial number or IMEI. Exported reports use a random identifier created for this install and kept in the Keychain.")
            }

            Section("What iOS does not allow") {
                point("Changing GPS without setup", "The Location tab can change the GPS location for all apps, but only through the phone's developer service. That needs LocalDevVPN, a pairing file made on a computer, and Developer Mode. The pairing file is kept in the app's private storage and never leaves the phone.")
                point("Battery health and hardware tests", "Apps cannot read maximum capacity or cycle count, or test the screen, speakers or sensors.")
                point("Other apps", "Apps cannot list installed apps, see their sizes, or clear their caches.")
                point("Locks and security", "The app does nothing with Activation Lock, iCloud accounts or passcodes.")
            }

            Section {
                Text("This is a personal project. It is not made by or affiliated with the makers of the desktop 3uTools program.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About & privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
