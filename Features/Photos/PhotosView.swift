import SwiftUI
import Photos
import UIKit

struct PhotosView: View {
    @State private var model = PhotosViewModel()
    @State private var previewItem: AssetItem?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if model.permission.isUsable {
                library
            } else {
                PermissionPromptView(
                    title: "Photo library",
                    message: "Allow access to browse your photos, videos and albums here. Nothing leaves your phone.",
                    systemImage: "photo.on.rectangle.angled",
                    state: model.permission
                ) {
                    Task { await model.requestAccess() }
                }
            }
        }
        .navigationTitle("Photos")
        .onAppear { model.start() }
    }

    private var library: some View {
        VStack(spacing: 0) {
            Picker("Kind", selection: $model.kind) {
                ForEach(MediaKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                Text("\(model.photoCount) photos · \(model.videoCount) videos")
                if model.permission == .limited {
                    Text("· limited access")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if model.kind == .albums || !model.searchText.isEmpty {
                albumList
            } else if model.items.isEmpty {
                EmptyStateView(title: "Nothing to show",
                               systemImage: model.kind == .videos ? "video.slash" : "photo",
                               message: "No items match the current filter.")
            } else {
                ScrollView {
                    AssetGrid(items: model.items,
                              isSelecting: model.isSelecting,
                              selection: model.selection) { item in
                        if model.isSelecting {
                            model.toggle(item)
                        } else {
                            previewItem = item
                        }
                    }
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "Search albums")
        .toolbar { toolbar }
        .onChange(of: model.kind) { _, _ in
            model.endSelecting()
            model.reload()
        }
        .onChange(of: model.filter) { _, _ in model.reload() }
        .onChange(of: model.period) { _, _ in model.reload() }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(item: item)
        }
        .confirmationDialog("Delete \(model.selection.count) selected item(s)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteSelection(from: model.items) }
            }
        } message: {
            Text("They move to Recently Deleted in the Photos app, where iOS keeps them for 30 days. iOS will ask you to confirm once more.")
        }
        .alert("Delete failed", isPresented: Binding(get: { model.errorMessage != nil },
                                                     set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.kind != .albums {
                Menu {
                    Picker("Show", selection: $model.filter) {
                        ForEach(availableFilters) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Period", selection: $model.period) {
                        ForEach(MediaPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Filter", systemImage: model.filter == .all && model.period == .allTime
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.kind != .albums {
                if model.isSelecting {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.selection.isEmpty)
                }
                Button(model.isSelecting ? "Done" : "Select") {
                    if model.isSelecting {
                        model.endSelecting()
                    } else {
                        model.isSelecting = true
                    }
                }
            }
        }
    }

    private var availableFilters: [MediaFilter] {
        model.kind == .videos ? [.all, .favourites] : MediaFilter.allCases
    }

    private var albumList: some View {
        Group {
            if model.kind != .albums && model.albums.isEmpty {
                // Searching from the Photos or Videos segment: albums have not been fetched yet.
                Color.clear.onAppear { model.kind = .albums }
            } else if model.filteredAlbums.isEmpty {
                EmptyStateView(title: "No albums found", systemImage: "rectangle.stack",
                               message: model.searchText.isEmpty ? nil : "No album title contains “\(model.searchText)”.")
            } else {
                List(model.filteredAlbums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let cover = album.cover {
                                    AssetThumbnail(asset: cover)
                                } else {
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading) {
                                Text(album.title)
                                Text("\(album.count) items").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

/// Square thumbnail grid shared by the library and album screens.
struct AssetGrid: View {
    let items: [AssetItem]
    let isSelecting: Bool
    let selection: Set<String>
    let onTap: (AssetItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 2)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(items) { item in
                AssetThumbnail(asset: item.asset)
                    .overlay(alignment: .bottomLeading) {
                        if item.asset.mediaType == .video {
                            Label(Format.duration(item.asset.duration), systemImage: "video.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .shadow(radius: 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelecting {
                            Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(.white, Theme.brandBlue)
                                .padding(5)
                                .shadow(radius: 2)
                        }
                    }
                    .opacity(isSelecting && selection.contains(item.id) ? 0.7 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(item) }
            }
        }
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: asset.localIdentifier) { load() }
    }

    private func load() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: CGSize(width: 300, height: 300),
                                              contentMode: .aspectFill,
                                              options: options) { result, _ in
            guard let result else { return }
            DispatchQueue.main.async { image = result }
        }
    }
}

struct AlbumDetailView: View {
    let album: AlbumItem
    @State private var items: [AssetItem] = []
    @State private var previewItem: AssetItem?

    var body: some View {
        ScrollView {
            if items.isEmpty {
                EmptyStateView(title: "Empty album", systemImage: "rectangle.stack")
            } else {
                AssetGrid(items: items, isSelecting: false, selection: []) { previewItem = $0 }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { items = PhotosViewModel.assets(in: album.collection) }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(item: item)
        }
    }
}
