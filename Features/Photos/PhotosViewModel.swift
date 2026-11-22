import Foundation
import Photos
import Observation

enum MediaKind: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case videos = "Videos"
    case albums = "Albums"
    var id: String { rawValue }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case favourites = "Favourites"
    case screenshots = "Screenshots"
    case livePhotos = "Live Photos"
    var id: String { rawValue }
}

enum MediaPeriod: String, CaseIterable, Identifiable {
    case allTime = "All time"
    case week = "Last 7 days"
    case month = "Last 30 days"
    case year = "Last 12 months"
    var id: String { rawValue }

    func startDate(now: Date = Date()) -> Date? {
        switch self {
        case .allTime: return nil
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return now.addingTimeInterval(-30 * 86_400)
        case .year: return now.addingTimeInterval(-365 * 86_400)
        }
    }
}

struct AssetItem: Identifiable, Hashable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct AlbumItem: Identifiable, Hashable {
    let collection: PHAssetCollection
    let title: String
    let count: Int
    let cover: PHAsset?
    var id: String { collection.localIdentifier }
}

/// Reads the photo library. Not main-actor bound because PhotoKit calls the change observer on its own queue;
/// all state changes are pushed to the main queue.
@Observable
final class PhotosViewModel: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var permission: PermissionState = PermissionService.photos()
    private(set) var items: [AssetItem] = []
    private(set) var albums: [AlbumItem] = []
    private(set) var photoCount = 0
    private(set) var videoCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    // The view calls reload() when kind, filter or period change.
    var kind: MediaKind = .photos
    var filter: MediaFilter = .all
    var period: MediaPeriod = .allTime
    var searchText = ""

    var isSelecting = false
    var selection: Set<String> = []

    func endSelecting() {
        isSelecting = false
        selection.removeAll()
    }

    @ObservationIgnored private var isObserving = false

    deinit {
        if isObserving { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    var filteredAlbums: [AlbumItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func start() {
        permission = PermissionService.photos()
        guard permission.isUsable else { return }
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        reload()
    }

    func requestAccess() async {
        let result = await PermissionService.requestPhotos()
        await MainActor.run {
            self.permission = result
            self.start()
        }
    }

    func reload() {
        guard permission.isUsable else { return }
        isLoading = true
        photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
        videoCount = PHAsset.fetchAssets(with: .video, options: nil).count

        switch kind {
        case .photos:
            items = Self.fetch(mediaType: .image, filter: filter, period: period)
        case .videos:
            items = Self.fetch(mediaType: .video, filter: filter, period: period)
        case .albums:
            albums = Self.fetchAlbums()
        }
        isLoading = false
    }

    static func fetch(mediaType: PHAssetMediaType, filter: MediaFilter, period: MediaPeriod) -> [AssetItem] {
        var predicates: [NSPredicate] = [NSPredicate(format: "mediaType == %d", mediaType.rawValue)]
        switch filter {
        case .all:
            break
        case .favourites:
            predicates.append(NSPredicate(format: "favorite == YES"))
        case .screenshots:
            predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue)))
        case .livePhotos:
            predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", Int(PHAssetMediaSubtype.photoLive.rawValue)))
        }
        if let start = period.startDate() {
            predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
        }

        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return assets(from: PHAsset.fetchAssets(with: options))
    }

    static func assets(in collection: PHAssetCollection) -> [AssetItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return assets(from: PHAsset.fetchAssets(in: collection, options: options))
    }

    private static func assets(from result: PHFetchResult<PHAsset>) -> [AssetItem] {
        var list: [AssetItem] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            list.append(AssetItem(asset: asset))
        }
        return list
    }

    static func fetchAlbums() -> [AlbumItem] {
        var list: [AlbumItem] = []
        let sources = [
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil),
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        ]
        for source in sources {
            source.enumerateObjects { collection, _, _ in
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let assets = PHAsset.fetchAssets(in: collection, options: options)
                guard assets.count > 0 else { return }
                list.append(AlbumItem(collection: collection,
                                      title: collection.localizedTitle ?? "Untitled",
                                      count: assets.count,
                                      cover: assets.firstObject))
            }
        }
        return list
    }

    func toggle(_ item: AssetItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    /// Deletes the selected items. iOS shows its own confirmation as well; cancelling it throws.
    func deleteSelection(from source: [AssetItem]) async {
        let assets = source.filter { selection.contains($0.id) }.map(\.asset)
        guard !assets.isEmpty else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            await MainActor.run {
                self.endSelecting()
                self.reload()
            }
        } catch {
            let cancelled = (error as NSError).code == PHPhotosError.Code.userCancelled.rawValue
            await MainActor.run {
                self.errorMessage = cancelled ? nil : "The items could not be deleted: \(error.localizedDescription)"
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.reload()
        }
    }
}
