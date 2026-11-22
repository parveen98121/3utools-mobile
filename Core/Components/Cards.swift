import SwiftUI

/// A titled card with an icon and arbitrary content.
struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    var showsChevron = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gradient)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
        .cardStyle()
    }
}

/// A small tile with a big value and a caption.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = Theme.brandBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle(padding: 14)
    }
}

/// A label/value row for detail lists.
struct InfoRow: View {
    let label: String
    let value: String?
    var source: DataSource?
    var note: String?

    init(_ label: String, _ value: String?, source: DataSource? = nil, note: String? = nil) {
        self.label = label
        self.value = value
        self.source = source
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer(minLength: 12)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                } else {
                    Text("Not available")
                        .foregroundStyle(.tertiary)
                }
                if let source {
                    SourceBadge(source: value == nil ? .unavailable : source)
                }
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Animated circular gauge. `progress` runs from 0 to 1.
struct RingGauge<Label: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 12
    @ViewBuilder var label: () -> Label

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { shown = clamped(progress) }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.4)) { shown = clamped(newValue) }
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Gradient banner used at the top of main screens.
struct GradientHeader<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Theme.brandPurple.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}
