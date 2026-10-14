import SwiftUI
import Photos

// MARK: - Events & summary (produced by the engine, consumed by the manager)

struct BackupSummary: Sendable {
    var copiedAssets = 0
    var copiedFiles = 0
    var alreadyBackedUp = 0
    var failedAssets = 0
    var bytesCopied: Int64 = 0
    var errors: [String] = []
    var cancelled = false
    var abortReason: String?
}

enum BackupEvent: Sendable {
    case scanning(checked: Int, total: Int)
    case copying(index: Int, total: Int, name: String)
    case assetFraction(Double)      // 0...1 – files finished within the current asset
    case iCloud(Double?)            // iCloud download progress for the current file, nil = none
    case finished(BackupSummary)
}

// MARK: - Manager (UI-facing state, runs on the main actor)

@MainActor
final class BackupManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case scanning(checked: Int, total: Int)
        case copying(index: Int, total: Int, fileName: String)
        case finished
        case cancelled
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var overallProgress: Double = 0
    @Published private(set) var iCloudProgress: Double?
    @Published private(set) var summary: BackupSummary?
    @Published private(set) var isCancelling = false
    @Published private(set) var destinationURL: URL?
    @Published private(set) var destinationLabel: String?

    private static let bookmarkKey = "backupDestinationBookmark"
    private var worker: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .scanning, .copying: return true
        default: return false
        }
    }

    init() {
        restoreDestination()
    }

    // MARK: Destination

    /// Called with the folder URL returned by `.fileImporter`.
    func setDestination(_ url: URL) {
        store(url)
        phase = .idle
        summary = nil
    }

    func reportError(_ error: Error) {
        phase = .failed(error.localizedDescription)
    }

    private func store(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        } catch {
            phase = .failed("Could not remember the folder: \(error.localizedDescription)")
        }
        destinationURL = url
        let volume = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        destinationLabel = [url.lastPathComponent, volume].compactMap { $0 }.joined(separator: " · ")
    }

    private func restoreDestination() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        store(url)
    }

    // MARK: Start / cancel

    func start() {
        guard !isRunning, let root = destinationURL else { return }
        summary = nil
        overallProgress = 0
        iCloudProgress = nil
        isCancelling = false
        phase = .scanning(checked: 0, total: 0)
        UIApplication.shared.isIdleTimerDisabled = true   // keep the screen awake while copying
        runTask = Task { [weak self] in
            await self?.runBackup(root: root)
        }
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        worker?.cancel()
    }

    private func runBackup(root: URL) async {
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // 1. Photo Library permission (full access is required for a complete backup)
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized else {
            phase = .failed("Full Photos access is required. Open Settings › Privacy › Photos and allow Full Access for this app.")
            return
        }

        // 2. Access to the drive
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        guard (try? root.checkResourceIsReachable()) == true else {
            phase = .failed("Can't reach the selected folder. Reconnect the drive and select the folder again.")
            return
        }

        // 3. Run the engine off the main thread and listen to its events
        let (stream, continuation) = AsyncStream.makeStream(of: BackupEvent.self)
        worker = Task.detached(priority: .userInitiated) {
            await BackupEngine.run(root: root, emit: { continuation.yield($0) })
            continuation.finish()
        }

        for await event in stream {
            handle(event)
        }
        if isRunning { phase = .finished }   // safety net
        isCancelling = false
    }

    private func handle(_ event: BackupEvent) {
        switch event {
        case .scanning(let checked, let total):
            phase = .scanning(checked: checked, total: total)

        case .copying(let index, let total, let name):
            phase = .copying(index: index, total: total, fileName: name)
            overallProgress = Double(index - 1) / Double(max(total, 1))
            iCloudProgress = nil

        case .assetFraction(let fraction):
            if case .copying(let index, let total, _) = phase {
                overallProgress = (Double(index - 1) + fraction) / Double(max(total, 1))
            }

        case .iCloud(let fraction):
            if let fraction, fraction < 1 { iCloudProgress = fraction } else { iCloudProgress = nil }

        case .finished(let result):
            summary = result
            iCloudProgress = nil
            if let reason = result.abortReason {
                phase = .failed(reason)
            } else if result.cancelled {
                phase = .cancelled
            } else {
                overallProgress = 1
                phase = .finished
            }
        }
    }
}

// MARK: - Engine (runs off the main actor)

private struct PendingFile: @unchecked Sendable {
    let resource: PHAssetResource
    let destination: URL
}

private struct PendingAsset: @unchecked Sendable {
    let displayName: String
    let date: Date?
    let files: [PendingFile]
}

enum BackupEngine {

    /// Also back up the edited (adjusted) version next to the original, named `<name>_edited.<ext>`.
    nonisolated static let includeEditedVersions = true
    /// FAT/exFAT drives store timestamps with ~2 s resolution.
    nonisolated private static let dateTolerance: TimeInterval = 3

    nonisolated static func run(root: URL, emit: @escaping @Sendable (BackupEvent) -> Void) async {
        var summary = BackupSummary()
        let fm = FileManager.default

        // ---- 1. Fetch every photo & video in the library
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                        PHAssetMediaType.image.rawValue,
                                        PHAssetMediaType.video.rawValue)
        let fetch = PHAsset.fetchAssets(with: options)
        let total = fetch.count

        // ---- 2. Plan: work out which files are not on the drive yet
        var pending: [PendingAsset] = []
        var reserved = Set<String>()
        var checked = 0
        emit(.scanning(checked: 0, total: total))

        fetch.enumerateObjects { asset, _, stop in
            if Task.isCancelled { stop.pointee = true; return }

            let plan = planFiles(for: asset, root: root, fm: fm, reserved: &reserved)
            if plan.missing.isEmpty {
                if plan.existing > 0 { summary.alreadyBackedUp += 1 }
            } else {
                pending.append(PendingAsset(displayName: plan.name, date: asset.creationDate, files: plan.missing))
            }
            checked += 1
            if checked % 100 == 0 { emit(.scanning(checked: checked, total: total)) }
        }
        emit(.scanning(checked: checked, total: total))

        if Task.isCancelled {
            summary.cancelled = true
            emit(.finished(summary))
            return
        }

        // ---- 3. Copy
        var consecutiveFailures = 0
        for (i, item) in pending.enumerated() {
            if Task.isCancelled { summary.cancelled = true; break }

            guard (try? root.checkResourceIsReachable()) == true else {
                summary.abortReason = "The drive was disconnected. \(summary.copiedAssets) item(s) were copied before it stopped. Reconnect it and run the backup again – it will continue where it left off."
                break
            }

            emit(.copying(index: i + 1, total: pending.count, name: item.displayName))

            do {
                let folder = item.files[0].destination.deletingLastPathComponent()
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)

                for (j, file) in item.files.enumerated() {
                    let bytes = try await copy(file, date: item.date, fm: fm) { emit(.iCloud($0)) }
                    summary.copiedFiles += 1
                    summary.bytesCopied += bytes
                    emit(.assetFraction(Double(j + 1) / Double(item.files.count)))
                }
                summary.copiedAssets += 1
                consecutiveFailures = 0
            } catch {
                summary.failedAssets += 1
                consecutiveFailures += 1
                if summary.errors.count < 50 {
                    summary.errors.append("\(item.displayName): \(error.localizedDescription)")
                }
                if consecutiveFailures >= 10 {
                    summary.abortReason = "Stopped after 10 failures in a row. Last error: \(error.localizedDescription)"
                    break
                }
            }
        }

        emit(.iCloud(nil))
        emit(.finished(summary))
    }

    // MARK: Planning

    nonisolated private static func planFiles(for asset: PHAsset,
                                              root: URL,
                                              fm: FileManager,
                                              reserved: inout Set<String>) -> (missing: [PendingFile], existing: Int, name: String) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first else {
            return ([], 0, "")
        }
        let stem = (primary.originalFilename as NSString).deletingPathExtension
        let folder = root.appendingPathComponent(monthFolderName(for: asset.creationDate), isDirectory: true)

        var missing: [PendingFile] = []
        var existing = 0

        for resource in resources {
            guard let name = targetName(for: resource, stem: stem) else { continue }
            let resolved = resolve(name: name, folder: folder, date: asset.creationDate, fm: fm, reserved: &reserved)
            if resolved.exists {
                existing += 1
            } else {
                missing.append(PendingFile(resource: resource, destination: resolved.url))
            }
        }
        return (missing, existing, primary.originalFilename)
    }

    /// Which resources we save and what they are called. Live Photos get the same base name for HEIC/JPG + MOV.
    nonisolated private static func targetName(for resource: PHAssetResource, stem: String) -> String? {
        let ext = (resource.originalFilename as NSString).pathExtension
        switch resource.type {
        case .photo, .video, .alternatePhoto:          // originals (alternatePhoto = RAW of a RAW+JPEG pair)
            return resource.originalFilename
        case .pairedVideo:                             // Live Photo video
            return stem + "." + (ext.isEmpty ? "MOV" : ext)
        case .fullSizePhoto:
            return includeEditedVersions ? "\(stem)_edited." + (ext.isEmpty ? "jpg" : ext) : nil
        case .fullSizeVideo, .fullSizePairedVideo:
            return includeEditedVersions ? "\(stem)_edited." + (ext.isEmpty ? "mov" : ext) : nil
        default:                                       // adjustment data, thumbnails, audio …
            return nil
        }
    }

    /// Returns the destination URL and whether this exact file is already on the drive.
    /// A same-named file counts as "already backed up" only if its date matches the asset's creation date;
    /// otherwise (e.g. IMG_0001 from a different phone) we pick `IMG_0001_1.HEIC`, and so on.
    nonisolated private static func resolve(name: String,
                                            folder: URL,
                                            date: Date?,
                                            fm: FileManager,
                                            reserved: inout Set<String>) -> (url: URL, exists: Bool) {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 0
        while true {
            let candidate = n == 0 ? name : (ext.isEmpty ? "\(stem)_\(n)" : "\(stem)_\(n).\(ext)")
            n += 1
            let url = folder.appendingPathComponent(candidate)
            let key = url.path.lowercased()

            if reserved.contains(key) { continue }

            if fm.fileExists(atPath: url.path) {
                if looksLikeSameFile(url, date: date, fm: fm) {
                    reserved.insert(key)
                    return (url, true)
                }
                continue
            }
            reserved.insert(key)
            return (url, false)
        }
    }

    nonisolated private static func looksLikeSameFile(_ url: URL, date: Date?, fm: FileManager) -> Bool {
        guard let date else { return true }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return false }
        for key in [FileAttributeKey.creationDate, .modificationDate] {
            if let d = attrs[key] as? Date, abs(d.timeIntervalSince(date)) <= dateTolerance { return true }
        }
        return false
    }

    nonisolated private static func monthFolderName(for date: Date?) -> String {
        guard let date else { return "Unknown-Date" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    // MARK: Copying

    /// Writes the ORIGINAL bytes of the resource (all EXIF/GPS/ProRes/RAW intact), downloading from iCloud if needed.
    /// Writes to `<name>.partial` first so an interrupted copy is never mistaken for a finished file.
    nonisolated private static func copy(_ file: PendingFile,
                                         date: Date?,
                                         fm: FileManager,
                                         onDownload: @escaping @Sendable (Double) -> Void) async throws -> Int64 {
        let temp = file.destination.appendingPathExtension("partial")
        try? fm.removeItem(at: temp)

        do {
            try await writeResource(file.resource, to: temp, onDownload: onDownload)
            if let date {
                try? fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: temp.path)
            }
            try fm.moveItem(at: temp, to: file.destination)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }

        let attrs = try? fm.attributesOfItem(atPath: file.destination.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    nonisolated private static func writeResource(_ resource: PHAssetResource,
                                                  to url: URL,
                                                  onDownload: @escaping @Sendable (Double) -> Void) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true            // fetch full-resolution original from iCloud
        options.progressHandler = { progress in onDownload(progress) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
