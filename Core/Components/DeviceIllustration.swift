import SwiftUI

/// An iPhone outline drawn with shapes. It shows real text passed in by the caller,
/// never a mock screenshot.
struct DeviceIllustration: View {
    var title: String
    var subtitle: String
    var batteryFraction: Double?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.85))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(4)
            VStack(spacing: 6) {
                Capsule()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: 34, height: 9)
                    .padding(.top, 9)
                Spacer()
                Image(systemName: "apple.logo")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                if let batteryFraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: geo.size.width * min(max(batteryFraction, 0), 1))
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(width: 96, height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Device illustration for \(title), \(subtitle)")
    }
}
