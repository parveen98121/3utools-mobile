import SwiftUI
import Photos
import AVKit
import UIKit

/// Full-screen preview with zoom for photos, playback for videos, and an information sheet.
struct MediaPreviewView: View {
    let item: AssetItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var showInfo = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showInfo) {
                MediaInfoSheet(asset: item.asset)
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if failed {
            EmptyStateView(title: "Could not load this item", systemImage: "exclamationmark.triangle",
                           message: "It may be stored in iCloud and the phone is offline.")
                .foregroundStyle(.white)
        } else if item.asset.mediaType == .video {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring) {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
        } else {
            ProgressView().tint(.white)
        }
    }

    private func load() {
        let asset = item.asset
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                DispatchQueue.main.async {
                    if let playerItem {
                        player = AVPlayer(playerItem: playerItem)
                    } else {
                        failed = true
                    }
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            let side = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFit,
                                                  options: options) { result, _ in
                DispatchQueue.main.async {
                    if let result {
                        image = result
                    } else {
                        failed = true
                    }
                }
            }
        }
    }
}

struct MediaInfoSheet: View {
    let asset: PHAsset

    private var resource: PHAssetResource? {
        PHAssetResource.assetResources(for: asset).first
    }

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    InfoRow("Name", resource?.originalFilename)
                    InfoRow("Type", resource?.uniformTypeIdentifier)
                    InfoRow("Kind", asset.mediaType == .video ? "Video" : "Photo")
                }
                Section("Details") {
                    InfoRow("Created", asset.creationDate?.formatted(date: .abbreviated, time: .shortened))
                    InfoRow("Modified", asset.modificationDate?.formatted(date: .abbreviated, time: .shortened))
                    InfoRow("Dimensions", "\(asset.pixelWidth) × \(asset.pixelHeight) pixels")
                    if asset.mediaType == .video {
                        InfoRow("Duration", Format.duration(asset.duration))
                    }
                    InfoRow("Favourite", asset.isFavorite ? "Yes" : "No")
                    if asset.mediaSubtypes.contains(.photoLive) {
                        InfoRow("Live Photo", "Yes")
                    }
                    if asset.mediaSubtypes.contains(.photoScreenshot) {
                        InfoRow("Screenshot", "Yes")
                    }
                }
                Section("Location") {
                    if let location = asset.location {
                        InfoRow("Latitude", Format.coordinate(location.coordinate.latitude))
                        InfoRow("Longitude", Format.coordinate(location.coordinate.longitude))
                    } else {
                        Text("No location saved with this item.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Information")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
