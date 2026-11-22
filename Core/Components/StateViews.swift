import SwiftUI
import UIKit

/// Loading, loaded, empty or failed: the four states an async screen can be in.
enum ViewState<Value> {
    case loading
    case loaded(Value)
    case empty
    case failed(String)
}

struct LoadingView: View {
    var text = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        }
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Shown before a permission is requested, or after it was denied.
struct PermissionPromptView: View {
    let title: String
    let message: String
    let systemImage: String
    let state: PermissionState
    let request: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(state == .notDetermined
                 ? message
                 : "Access is turned off. You can turn it on in Settings.")
        } actions: {
            if state == .notDetermined {
                Button("Allow access", action: request)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open Settings") { AppSettings.open() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Explains a feature iOS does not let apps provide.
struct RestrictedFeatureView: View {
    let title: String
    let message: String
    var settingsPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let settingsPath {
                Text("Find it in: \(settingsPath)")
                    .font(.footnote.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.unavailable.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The only public link into Settings: it opens this app's page in the Settings app.
enum AppSettings {
    @MainActor
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
