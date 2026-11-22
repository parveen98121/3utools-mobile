import SwiftUI

/// Colours, gradients and metrics shared by every screen.
enum Theme {
    static let brandBlue = Color(red: 0.184, green: 0.420, blue: 1.0)
    static let brandPurple = Color(red: 0.541, green: 0.302, blue: 1.0)

    static let gradient = LinearGradient(
        colors: [brandBlue, brandPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softGradient = LinearGradient(
        colors: [brandBlue.opacity(0.35), brandPurple.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    static let cornerRadius: CGFloat = 20
    static let spacing: CGFloat = 16

    static let passed = Color.green
    static let warning = Color.orange
    static let unavailable = Color.gray
}

private struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// Wraps the view in the app's standard rounded card.
    func cardStyle(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Standard screen background.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// Button style used for primary actions.
struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}
