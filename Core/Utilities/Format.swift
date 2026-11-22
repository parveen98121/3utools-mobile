import Foundation

/// Text formatting that does not depend on the phone's locale, so it can be unit tested.
enum Format {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Decimal units, the same convention the Settings app uses: 1 GB = 1,000,000,000 bytes.
    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(max(value, 0))
        var index = 0
        while amount >= 1000, index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        if index == 0 || amount >= 100 {
            return String(format: "%.0f %@", locale: posix, amount, units[index])
        }
        return String(format: "%.1f %@", locale: posix, amount, units[index])
    }

    /// 0.823 becomes "82%".
    static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// 93784 seconds becomes "1d 2h".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    static func speed(_ megabitsPerSecond: Double) -> String {
        String(format: "%.1f Mbps", locale: posix, megabitsPerSecond)
    }

    static func milliseconds(_ seconds: TimeInterval) -> String {
        String(format: "%.0f ms", locale: posix, seconds * 1000)
    }

    static func coordinate(_ value: Double) -> String {
        String(format: "%.5f", locale: posix, value)
    }
}
