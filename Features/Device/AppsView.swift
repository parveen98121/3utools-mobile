import SwiftUI
import UIKit
import Observation

/// An app the phone can be asked about by its URL scheme.
struct KnownApp: Identifiable, Equatable {
    let name: String
    let scheme: String
    let storeID: String

    var id: String { scheme }
    var launchURL: URL? { URL(string: "\(scheme)://") }
    var storeURL: URL? { URL(string: "https://apps.apple.com/app/id\(storeID)") }

    /// Every scheme here must also be listed under LSApplicationQueriesSchemes in project.yml.
    static let catalog: [KnownApp] = [
        KnownApp(name: "WhatsApp", scheme: "whatsapp", storeID: "310633997"),
        KnownApp(name: "Instagram", scheme: "instagram", storeID: "389801252"),
        KnownApp(name: "Facebook", scheme: "fb", storeID: "284882215"),
        KnownApp(name: "Messenger", scheme: "fb-messenger", storeID: "454638411"),
        KnownApp(name: "YouTube", scheme: "youtube", storeID: "544007664"),
        KnownApp(name: "Telegram", scheme: "tg", storeID: "686449807"),
        KnownApp(name: "X", scheme: "twitter", storeID: "333903271"),
        KnownApp(name: "Spotify", scheme: "spotify", storeID: "324684580"),
        KnownApp(name: "Google Maps", scheme: "comgooglemaps", storeID: "585027354"),
        KnownApp(name: "Chrome", scheme: "googlechrome", storeID: "535886823"),
        KnownApp(name: "Gmail", scheme: "googlegmail", storeID: "422689480"),
        KnownApp(name: "Google Drive", scheme: "googledrive", storeID: "507874739"),
        KnownApp(name: "Snapchat", scheme: "snapchat", storeID: "447188370"),
        KnownApp(name: "Netflix", scheme: "nflx", storeID: "363590051"),
        KnownApp(name: "TikTok", scheme: "snssdk1233", storeID: "835599320"),
        KnownApp(name: "Zoom", scheme: "zoomus", storeID: "546505307"),
        KnownApp(name: "Uber", scheme: "uber", storeID: "368677368"),
        KnownApp(name: "LinkedIn", scheme: "linkedin", storeID: "288429040"),
        KnownApp(name: "Pinterest", scheme: "pinterest", storeID: "429047995"),
        KnownApp(name: "Amazon", scheme: "com.amazon.mobile.shopping", storeID: "297606951"),
        KnownApp(name: "VLC", scheme: "vlc", storeID: "650377962"),
        KnownApp(name: "Microsoft Teams", scheme: "msteams", storeID: "1113153706"),
        KnownApp(name: "Outlook", scheme: "ms-outlook", storeID: "951937596"),
        KnownApp(name: "PayPal", scheme: "paypal", storeID: "283646709"),
        KnownApp(name: "Paytm", scheme: "paytmmp", storeID: "473941634"),
        KnownApp(name: "PhonePe", scheme: "phonepe", storeID: "1170055821"),
        KnownApp(name: "Google Pay", scheme: "tez", storeID: "1193357041"),
        KnownApp(name: "Truecaller", scheme: "truecaller", storeID: "448142450"),
        KnownApp(name: "Discord", scheme: "discord", storeID: "985746746"),
        KnownApp(name: "Reddit", scheme: "reddit", storeID: "1064216828"),
        KnownApp(name: "Signal", scheme: "sgnl", storeID: "874139669")
    ]
}

/// Public details about an app from Apple's iTunes lookup service.
struct StoreDetails: Decodable, Equatable {
    let trackName: String?
    let sellerName: String?
    let primaryGenreName: String?
    let version: String?
    let artworkUrl100: String?
    let fileSizeBytes: String?

    var downloadSize: Int64? { fileSizeBytes.flatMap { Int64($0) } }
    var artworkURL: URL? { artworkUrl100.flatMap { URL(string: $0) } }
}

private struct StoreLookupResponse: Decodable {
    let results: [StoreDetails]
}

enum StoreLookupService {
    static func details(for storeID: String) async throws -> StoreDetails? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(storeID)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(StoreLookupResponse.self, from: data).results.first
    }
}

@MainActor
@Observable
final class AppsViewModel {
    private(set) var state: ViewState<[KnownApp]> = .loading
    private(set) var details: [String: StoreDetails] = [:]
    private(set) var lookupFailed = false

    func load() async {
        let installed = KnownApp.catalog.filter { app in
            guard let url = app.launchURL else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
        state = installed.isEmpty ? .empty : .loaded(installed)

        lookupFailed = false
        for app in installed where details[app.id] == nil {
            do {
                if let found = try await StoreLookupService.details(for: app.storeID) {
                    details[app.id] = found
                }
            } catch {
                lookupFailed = true
            }
        }
    }
}

struct AppsView: View {
    @State private var model = AppsViewModel()

    var body: some View {
        List {
            Section {
                RestrictedFeatureView(
                    title: "Why this is not a full list",
                    message: "iOS does not let an app list the apps installed on the phone, or see their sizes. This screen can only ask about a fixed set of well-known apps, one by one, and shows the ones that answer.",
                    settingsPath: "Settings > General > iPhone Storage (full list with sizes)"
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch model.state {
            case .loading:
                Section { LoadingView(text: "Checking known apps…") }
            case .empty:
                Section {
                    EmptyStateView(title: "None of the known apps were found",
                                   systemImage: "square.grid.2x2",
                                   message: "The app checked \(KnownApp.catalog.count) well-known apps.")
                }
            case .failed(let message):
                Section { ErrorStateView(message: message) }
            case .loaded(let apps):
                Section {
                    ForEach(apps) { app in
                        row(app)
                    }
                } header: {
                    Text("Found on this phone (\(apps.count) of \(KnownApp.catalog.count) checked)")
                } footer: {
                    Text(model.lookupFailed
                         ? "Some App Store details could not be loaded. Check the internet connection and pull to refresh."
                         : "Names, icons and download sizes come from Apple's public App Store lookup. Download size is the App Store figure, not the space the app uses on this phone.")
                }
            }
        }
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func row(_ app: KnownApp) -> some View {
        let details = model.details[app.id]
        return HStack(spacing: 12) {
            AsyncImage(url: details?.artworkURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.gradient.opacity(0.3))
                    .overlay(Image(systemName: "app.fill").foregroundStyle(.white))
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(details?.trackName ?? app.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let details {
                    Text([details.sellerName, details.primaryGenreName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text([details.version.map { "Store version \($0)" },
                          details.downloadSize.map { "download \(Format.bytes($0))" }].compactMap { $0 }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button("Open") {
                    if let url = app.launchURL { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Store") {
                    if let url = app.storeURL { UIApplication.shared.open(url) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
