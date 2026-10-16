import SwiftUI
import Photos

private struct AlbumInfo: Identifiable {
    let id: String          // PHAssetCollection.localIdentifier
    let title: String
    let count: Int
}

/// Lets the user tick albums for the "only selected" / "skip selected" album filter.
struct AlbumPickerView: View {
    @ObservedObject var manager: BackupManager
    @State private var userAlbums: [AlbumInfo] = []
    @State private var systemAlbums: [AlbumInfo] = []
    @State private var denied = false
    @State private var loaded = false

    var body: some View {
        List {
            if denied {
                Section {
                    Text(tr("Brak dostępu do Zdjęć. Zezwól na dostęp w Ustawieniach iOS › USB Backup › Zdjęcia.",
                            "No access to Photos. Allow it in iOS Settings › USB Backup › Photos."))
                        .foregroundStyle(.secondary)
                }
            } else if loaded && userAlbums.isEmpty && systemAlbums.isEmpty {
                Section {
                    Text(tr("Nie znaleziono albumów.", "No albums found."))
                        .foregroundStyle(.secondary)
                }
            } else {
                if !userAlbums.isEmpty {
                    Section(tr("Twoje albumy", "Your albums")) {
                        ForEach(userAlbums) { row($0) }
                    }
                }
                if !systemAlbums.isEmpty {
                    Section(tr("Albumy systemowe", "System albums")) {
                        ForEach(systemAlbums) { row($0) }
                    }
                }
            }
        }
        .navigationTitle(tr("Albumy", "Albums"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ album: AlbumInfo) -> some View {
        let selected = manager.options.albumIDs.contains(album.id)
        return Button {
            if selected {
                manager.options.albumIDs.removeAll { $0 == album.id }
            } else {
                manager.options.albumIDs.append(album.id)
            }
        } label: {
            HStack {
                Text(album.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(album.count)")
                    .foregroundStyle(.secondary)
                if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func load() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            denied = true
            loaded = true
            return
        }

        var user: [AlbumInfo] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, _ in
                user.append(AlbumInfo(id: collection.localIdentifier,
                                      title: collection.localizedTitle ?? "—",
                                      count: Self.count(of: collection)))
            }

        let smartTypes: [PHAssetCollectionSubtype] = [.smartAlbumScreenshots, .smartAlbumFavorites, .smartAlbumSelfPortraits,
                                                      .smartAlbumLivePhotos, .smartAlbumPanoramas, .smartAlbumVideos]
        var system: [AlbumInfo] = []
        for type in smartTypes {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: type, options: nil)
                .enumerateObjects { collection, _, _ in
                    let n = Self.count(of: collection)
                    if n > 0 {
                        system.append(AlbumInfo(id: collection.localIdentifier,
                                                title: collection.localizedTitle ?? "—",
                                                count: n))
                    }
                }
        }
        userAlbums = user.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        systemAlbums = system
        loaded = true
    }

    private static func count(of collection: PHAssetCollection) -> Int {
        let estimate = collection.estimatedAssetCount
        if estimate != NSNotFound { return estimate }
        return PHAsset.fetchAssets(in: collection, options: nil).count
    }
}
