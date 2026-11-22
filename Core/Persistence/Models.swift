import Foundation
import SwiftData

@Model
final class BatterySample {
    var date: Date
    var level: Double
    var stateRaw: Int

    init(date: Date, level: Double, state: BatteryState) {
        self.date = date
        self.level = level
        self.stateRaw = state.rawValue
    }

    var state: BatteryState { BatteryState(rawValue: stateRaw) ?? .unknown }
    var point: BatteryPoint { BatteryPoint(date: date, level: level, state: state) }
}

@Model
final class SavedLocation {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var isFavorite: Bool
    var date: Date

    init(name: String, address: String, latitude: Double, longitude: Double, isFavorite: Bool = false, date: Date = Date()) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.date = date
    }
}

@Model
final class SpeedTestResult {
    var date: Date
    var downloadMbps: Double
    var uploadMbps: Double
    var latencySeconds: Double
    var connection: String

    init(date: Date = Date(), downloadMbps: Double, uploadMbps: Double, latencySeconds: Double, connection: String) {
        self.date = date
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.latencySeconds = latencySeconds
        self.connection = connection
    }
}

@Model
final class RecentFile {
    var name: String
    var bookmark: Data
    var date: Date

    init(name: String, bookmark: Data, date: Date = Date()) {
        self.name = name
        self.bookmark = bookmark
        self.date = date
    }
}

/// Writes battery samples, skipping repeats.
enum BatteryRecorder {
    @MainActor
    static func record(_ reading: BatteryReading, in context: ModelContext, now: Date = Date()) {
        guard let level = reading.level else { return }
        var descriptor = FetchDescriptor<BatterySample>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        let last = (try? context.fetch(descriptor))?.first
        let point = BatteryPoint(date: now, level: level, state: reading.state)
        guard BatteryMath.shouldRecord(last: last?.point, new: point) else { return }
        context.insert(BatterySample(date: now, level: level, state: reading.state))
    }
}
