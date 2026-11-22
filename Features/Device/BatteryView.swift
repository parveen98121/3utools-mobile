import SwiftUI
import SwiftData
import Charts
import UIKit

enum BatteryRange: String, CaseIterable, Identifiable {
    case day = "24 hours"
    case week = "7 days"
    case month = "30 days"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }
}

struct BatteryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BatterySample.date) private var samples: [BatterySample]

    @State private var reading = BatteryReading(level: nil, state: .unknown)
    @State private var lowPowerMode = false
    @State private var range: BatteryRange = .day
    @State private var selectedDate: Date?
    @State private var confirmClear = false

    private var points: [BatteryPoint] {
        BatteryMath.points(samples.map(\.point), within: range.interval, endingAt: Date())
    }

    private var sessions: [ChargingSession] {
        BatteryMath.chargingSessions(from: samples.map(\.point)).reversed()
    }

    private var selectedPoint: BatteryPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                gaugeCard
                historyCard
                sessionsCard
                RestrictedFeatureView(
                    title: "Battery health",
                    message: "Maximum capacity, cycle count and charging history from before this app was opened are not shared with apps. Nothing on this screen is a health estimate.",
                    settingsPath: "Settings > Battery > Battery Health"
                )
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Battery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink("Export history as CSV", item: csv)
                    Button("Clear history", role: .destructive) { confirmClear = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(samples.isEmpty)
            }
        }
        .confirmationDialog("Delete all recorded battery samples?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) {
                for sample in samples { context.delete(sample) }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in refresh() }
    }

    private func refresh() {
        reading = LiveBatteryService().current()
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var csv: String {
        let formatter = ISO8601DateFormatter()
        let rows = samples.map { "\(formatter.string(from: $0.date)),\(Int(($0.level * 100).rounded())),\($0.state.label)" }
        return (["date,level_percent,state"] + rows).joined(separator: "\n")
    }

    // MARK: - Cards

    private var gaugeCard: some View {
        VStack(spacing: 16) {
            RingGauge(progress: reading.level ?? 0, lineWidth: 16) {
                VStack(spacing: 4) {
                    Text(reading.level.map(Format.percent) ?? "–")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Label(reading.state.label, systemImage: reading.state.isPluggedIn ? "bolt.fill" : "battery.75percent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            .padding(.top, 8)

            HStack {
                SourceBadge(source: reading.level == nil ? .unavailable : .live)
                Text(reading.level == nil
                     ? "iOS did not report a level (this is normal in the simulator)."
                     : "Read from the phone just now. iOS reports the level in steps of 1 to 5%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if lowPowerMode {
                Label("Low Power Mode is on", systemImage: "leaf.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var historyCard: some View {
        InfoCard(title: "Level history", systemImage: "chart.xyaxis.line") {
            Picker("Range", selection: $range) {
                ForEach(BatteryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if points.count < 2 {
                EmptyStateView(title: "Not enough history yet",
                               systemImage: "chart.line.uptrend.xyaxis",
                               message: "A reading is saved each time you open the app and whenever the level changes while it is open.")
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(points, id: \.date) { point in
                        AreaMark(x: .value("Time", point.date), y: .value("Level", point.level * 100))
                            .foregroundStyle(Theme.softGradient)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", point.date), y: .value("Level", point.level * 100))
                            .foregroundStyle(Theme.brandBlue)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    if let selectedPoint {
                        RuleMark(x: .value("Selected", selectedPoint.date))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 2) {
                                    Text(Format.percent(selectedPoint.level)).font(.caption.weight(.bold))
                                    Text(selectedPoint.date, format: .dateTime.day().month().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(selectedPoint.state.label).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                            }
                        PointMark(x: .value("Time", selectedPoint.date), y: .value("Level", selectedPoint.level * 100))
                            .foregroundStyle(Theme.brandPurple)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Int.self) { Text("\(number)%") }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 220)
            }

            HStack(alignment: .top) {
                SourceBadge(source: .live)
                Text("Recorded readings only. The chart covers the times the app was open; gaps are not filled in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionsCard: some View {
        InfoCard(title: "Charging sessions seen by this app", systemImage: "bolt.fill") {
            if sessions.isEmpty {
                Text("No charging has been recorded while the app was open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(10)) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.start, format: .dateTime.day().month().hour().minute())
                                .font(.subheadline.weight(.medium))
                            Text("Observed for \(Format.duration(session.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Format.percent(session.startLevel)) → \(Format.percent(session.endLevel))")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                    if session.id != sessions.prefix(10).last?.id { Divider() }
                }
            }
        }
    }
}
