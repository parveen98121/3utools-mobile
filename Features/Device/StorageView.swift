import SwiftUI
import Charts
import Photos
import Observation

/// Counts photos and videos and adds up their file sizes.
enum PhotoStatsService {
    /// PhotoKit has no public file-size property. The "fileSize" key on PHAssetResource is
    /// undocumented, so the total is shown as an estimate and is nil when the key returns nothing.
    static func compute() async -> PhotoLibraryStats {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let photos = PHAsset.fetchAssets(with: .image, options: nil)
                let videos = PHAsset.fetchAssets(with: .video, options: nil)
                var total: Int64 = 0
                var sawSize = false

                for result in [photos, videos] {
                    result.enumerateObjects { asset, _, _ in
                        for resource in PHAssetResource.assetResources(for: asset) {
                            // Without this check a missing key would crash instead of returning nil.
                            guard resource.responds(to: NSSelectorFromString("fileSize")) else { continue }
                            if let size = resource.value(forKey: "fileSize") as? Int64 {
                                total += size
                                sawSize = true
                            } else if let number = resource.value(forKey: "fileSize") as? NSNumber {
                                total += number.int64Value
                                sawSize = true
                            }
                        }
                    }
                }
                continuation.resume(returning: PhotoLibraryStats(photoCount: photos.count,
                                                                 videoCount: videos.count,
                                                                 estimatedBytes: sawSize ? total : nil))
            }
        }
    }
}

@MainActor
@Observable
final class StorageViewModel {
    private(set) var state: ViewState<StorageSnapshot> = .loading
    private(set) var appSize: Int64 = 0
    private(set) var photoStats: PhotoLibraryStats?
    private(set) var isAnalysingPhotos = false
    private(set) var photoPermission: PermissionState = .notDetermined

    private let storage: StorageProviding

    init(storage: StorageProviding = LiveStorageService()) {
        self.storage = storage
    }

    var snapshot: StorageSnapshot? {
        if case .loaded(let value) = state { return value }
        return nil
    }

    var recommendations: [StorageRecommendation] {
        guard let snapshot else { return [] }
        return StorageMath.recommendations(storage: snapshot, photos: photoStats)
    }

    func load() {
        do {
            state = .loaded(try storage.snapshot())
        } catch {
            state = .failed(error.localizedDescription)
        }
        appSize = storage.appDocumentsSize()
        photoPermission = PermissionService.photos()
    }

    /// Asks for photo access if needed, then counts the library.
    func analysePhotos() async {
        if photoPermission == .notDetermined {
            photoPermission = await PermissionService.requestPhotos()
        }
        guard photoPermission.isUsable, !isAnalysingPhotos else { return }
        isAnalysingPhotos = true
        photoStats = await PhotoStatsService.compute()
        isAnalysingPhotos = false
    }
}

struct StorageView: View {
    @State private var model = StorageViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                switch model.state {
                case .loading:
                    LoadingView().frame(height: 240)
                case .failed(let message):
                    ErrorStateView(message: message) { model.load() }
                case .empty:
                    EmptyStateView(title: "No storage data", systemImage: "internaldrive")
                case .loaded(let snapshot):
                    chartCard(snapshot)
                    photosCard
                    appCard
                    recommendationsCard
                    settingsCard
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { model.load() }
        .onAppear { model.load() }
    }

    private struct Slice: Identifiable {
        let name: String
        let bytes: Int64
        let color: Color
        var id: String { name }
    }

    private func chartCard(_ snapshot: StorageSnapshot) -> some View {
        let slices = [
            Slice(name: "Used", bytes: snapshot.used, color: Theme.brandBlue),
            Slice(name: "Available", bytes: snapshot.available, color: Theme.brandPurple.opacity(0.3))
        ]
        return InfoCard(title: "iPhone storage", systemImage: "internaldrive.fill") {
            Chart(slices) { slice in
                SectorMark(angle: .value("Bytes", Double(slice.bytes)), innerRadius: .ratio(0.68), angularInset: 2)
                    .cornerRadius(6)
                    .foregroundStyle(slice.color)
            }
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(Format.percent(snapshot.usedFraction))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("used").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)

            VStack(spacing: 10) {
                legendRow("Total", Format.bytes(snapshot.total), nil)
                legendRow("Used", Format.bytes(snapshot.used), Theme.brandBlue)
                legendRow("Available", Format.bytes(snapshot.available), Theme.brandPurple.opacity(0.3))
            }
            HStack(alignment: .top) {
                SourceBadge(source: .live)
                Text("“Available” includes space iOS can free automatically, so it can differ slightly from the Settings app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legendRow(_ label: String, _ value: String, _ color: Color?) -> some View {
        HStack {
            if let color {
                Circle().fill(color).frame(width: 10, height: 10)
            }
            Text(label)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var photosCard: some View {
        InfoCard(title: "Photos and videos", systemImage: "photo.on.rectangle") {
            if model.isAnalysingPhotos {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the photo library. Large libraries take a while.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let stats = model.photoStats {
                legendRow("Photos", "\(stats.photoCount)", nil)
                legendRow("Videos", "\(stats.videoCount)", nil)
                HStack {
                    Text("Size on this phone")
                    Spacer()
                    Text(stats.estimatedBytes.map(Format.bytes) ?? "Not available")
                        .fontWeight(.semibold)
                    SourceBadge(source: stats.estimatedBytes == nil ? .unavailable : .estimated)
                }
                .font(.subheadline)
                Text("The size is an estimate: iOS has no official way for apps to read it, and items stored in iCloud may be counted at full size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.photoPermission == .denied || model.photoPermission == .restricted {
                Text("Photo access is turned off, so counts are not available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { AppSettings.open() }
            } else {
                Text("Count your photos and videos and estimate how much space they take.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Analyse photo library") {
                    Task { await model.analysePhotos() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var appCard: some View {
        InfoCard(title: "Documents and files", systemImage: "doc.fill") {
            HStack {
                Text("This app's data")
                Spacer()
                Text(Format.bytes(model.appSize)).fontWeight(.semibold)
                SourceBadge(source: .live)
            }
            .font(.subheadline)
            Text("Apps can only measure their own folders. Sizes of other apps and of the Files app are shown in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recommendationsCard: some View {
        InfoCard(title: "Recommendations", systemImage: "lightbulb.fill") {
            ForEach(model.recommendations) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(for: item.level))
                        .foregroundStyle(color(for: item.level))
                    Text(item.text)
                        .font(.footnote)
                }
            }
        }
    }

    private func icon(for level: StorageRecommendation.Level) -> String {
        switch level {
        case .good: return "checkmark.circle.fill"
        case .advice: return "info.circle.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for level: StorageRecommendation.Level) -> Color {
        switch level {
        case .good: return Theme.passed
        case .advice: return Theme.brandBlue
        case .urgent: return Theme.warning
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 12) {
            RestrictedFeatureView(
                title: "Per-app sizes and clearing space",
                message: "iOS does not let one app see another app's size, or clear caches and system files. Apple's own storage screen lists every app and offers its clean-up suggestions.",
                settingsPath: "Settings > General > iPhone Storage"
            )
            Button("Open Settings") { AppSettings.open() }
                .buttonStyle(GradientButtonStyle())
            Text("The button opens the Settings app. iOS has no supported link straight to the storage page, so follow the path above from there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
