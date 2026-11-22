import SwiftUI

/// Where a displayed value comes from.
enum DataSource: String, Equatable {
    case live = "Live"
    case estimated = "Estimated"
    case unavailable = "Not available"
}

struct SourceBadge: View {
    let source: DataSource

    private var tint: Color {
        switch source {
        case .live: return Theme.passed
        case .estimated: return Theme.warning
        case .unavailable: return Theme.unavailable
        }
    }

    var body: some View {
        Text(source.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Result of one diagnostic check.
enum DiagnosticStatus: String, Equatable {
    case passed = "Passed"
    case warning = "Warning"
    case notAvailable = "Not Available"

    var color: Color {
        switch self {
        case .passed: return Theme.passed
        case .warning: return Theme.warning
        case .notAvailable: return Theme.unavailable
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .notAvailable: return "minus.circle.fill"
        }
    }
}

struct StatusBadge: View {
    let status: DiagnosticStatus

    var body: some View {
        Label(status.rawValue, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}
