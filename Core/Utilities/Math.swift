import Foundation

// Pure logic with no device access, so it can all be unit tested.

// MARK: - Battery

enum BatteryState: Int, Codable, Equatable {
    case unknown = 0
    case unplugged = 1
    case charging = 2
    case full = 3

    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .unplugged: return "On battery"
        case .charging: return "Charging"
        case .full: return "Fully charged"
        }
    }

    var isPluggedIn: Bool { self == .charging || self == .full }
}

/// One recorded battery reading. `level` runs from 0 to 1.
struct BatteryPoint: Equatable {
    let date: Date
    let level: Double
    let state: BatteryState
}

struct ChargingSession: Equatable, Identifiable {
    let start: Date
    let end: Date
    let startLevel: Double
    let endLevel: Double

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var gained: Double { endLevel - startLevel }
}

enum BatteryMath {
    /// Skip a sample that repeats the previous one within a minute.
    static func shouldRecord(last: BatteryPoint?, new: BatteryPoint) -> Bool {
        guard let last else { return true }
        if last.state != new.state { return true }
        if abs(last.level - new.level) >= 0.005 { return true }
        return new.date.timeIntervalSince(last.date) >= 60
    }

    /// Groups consecutive plugged-in samples into sessions.
    /// A gap longer than `maxGap` between samples ends the session, because the app was closed
    /// and nothing is known about what happened in between.
    static func chargingSessions(from points: [BatteryPoint], maxGap: TimeInterval = 3600) -> [ChargingSession] {
        let sorted = points.sorted { $0.date < $1.date }
        var sessions: [ChargingSession] = []
        var first: BatteryPoint?
        var latest: BatteryPoint?

        func close() {
            if let first, let latest, latest.date > first.date {
                sessions.append(ChargingSession(start: first.date, end: latest.date,
                                                startLevel: first.level, endLevel: latest.level))
            }
            first = nil
            latest = nil
        }

        for point in sorted {
            if point.state.isPluggedIn {
                if let previous = latest, point.date.timeIntervalSince(previous.date) > maxGap {
                    close()
                }
                if first == nil { first = point }
                latest = point
            } else {
                close()
            }
        }
        close()
        return sessions
    }

    static func points(_ points: [BatteryPoint], within interval: TimeInterval, endingAt now: Date) -> [BatteryPoint] {
        let cutoff = now.addingTimeInterval(-interval)
        return points.filter { $0.date >= cutoff && $0.date <= now }.sorted { $0.date < $1.date }
    }
}

// MARK: - Storage

struct StorageSnapshot: Equatable {
    let total: Int64
    let available: Int64

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var availableFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }
}

struct PhotoLibraryStats: Equatable {
    let photoCount: Int
    let videoCount: Int
    /// Sum of file sizes, read through an undocumented key. Nil when iOS returns nothing.
    let estimatedBytes: Int64?
}

struct StorageRecommendation: Equatable, Identifiable {
    enum Level: Equatable { case good, advice, urgent }
    let level: Level
    let text: String
    var id: String { text }
}

enum StorageMath {
    static func recommendations(storage: StorageSnapshot, photos: PhotoLibraryStats?) -> [StorageRecommendation] {
        var result: [StorageRecommendation] = []
        let free = storage.availableFraction

        if free < 0.10 {
            result.append(.init(level: .urgent,
                                text: "Less than 10% of storage is free. iOS updates and the camera may stop working until you free some space."))
        } else if free < 0.20 {
            result.append(.init(level: .advice,
                                text: "Less than 20% of storage is free. Consider removing large videos or unused apps."))
        }

        if let photos {
            if let bytes = photos.estimatedBytes, storage.total > 0,
               Double(bytes) / Double(storage.total) > 0.30 {
                result.append(.init(level: .advice,
                                    text: "Photos and videos take about \(Format.bytes(bytes)), more than 30% of the phone. Turning on Optimise iPhone Storage in Settings > Photos can reduce this."))
            }
            if photos.videoCount > 200 {
                result.append(.init(level: .advice,
                                    text: "You have \(photos.videoCount) videos. Videos are usually the largest items; review them in the Photos tab."))
            }
        }

        if result.isEmpty {
            result.append(.init(level: .good, text: "Storage looks healthy. No action needed."))
        }
        return result
    }
}

// MARK: - Coordinates

struct Coordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

enum CoordinateParser {
    /// Accepts "28.6139, 77.2090" or "28.6139 77.2090". Returns nil when out of range or malformed.
    static func parse(_ text: String) -> Coordinate? {
        let parts = text
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else { return nil }
        return validated(latitude: latitude, longitude: longitude)
    }

    static func validated(latitude: Double, longitude: Double) -> Coordinate? {
        guard latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Speed

enum SpeedMath {
    /// Megabits per second from a byte count and elapsed time.
    static func megabitsPerSecond(bytes: Int64, seconds: TimeInterval) -> Double {
        guard seconds > 0, bytes > 0 else { return 0 }
        return Double(bytes) * 8 / seconds / 1_000_000
    }
}
