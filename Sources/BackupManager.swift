import SwiftUI
import Photos

// MARK: - Models

/// Result of the analysis: what is still missing on the drive.
struct PlanInfo: Sendable, Equatable {
    var totalAssets = 0
    var pendingAssets = 0
    var pendingFiles = 0
    var pendingBytes: Int64 = 0
    var unknownSizeFiles = 0     // files whose size iOS did not report (estimate is then a lower bound)
    var alreadyBackedUp = 0
}

/// How the most recent backup run ended.
enum LastRunStatus: String, Codable, Sendable {
    case inProgress            // marker says "started" but never finished (app closed / killed)
    case completed
    case completedWithErrors
    case cancelled
    case aborted
}

/// What we know about the selected drive.
struct DriveInfo: Sendable, Equatable {
    var volumeName: String?
    var totalBytes: Int64?
    var availableBytes: Int64?
    var lastRun: Date?                  // most recent run of any kind
    var lastRunStatus: LastRunStatus?
    var lastRunFailed = 0
    var lastCompleted: Date?            // most recent run that finished without any problem
}

/// Small JSON file kept on the drive (`.usb-backup-info.json`) – a copy is also kept inside the app.
private struct BackupMarker: Codable {
    var lastRun: Date?
    var status: String?
    var lastCompleted: Date?
    var copiedAssets: Int?
    var failedAssets: Int?
    var lastBackup: Date?               // legacy field written by the first version (= last fully successful run)

    var run: Date? { lastRun ?? lastBackup }
    var completed: Date? { lastCompleted ?? lastBackup }
    var statusValue: LastRunStatus { status.flatMap { LastRunStatus(rawValue: $0) } ?? .completed }
}

struct BackupSummary: Sendable {
    var copiedAssets = 0
    var copiedFiles = 0
    var alreadyBackedUp = 0
    var failedAssets = 0
    var bytesCopied: Int64 = 0
    var errors: [String] = []
    var cancelled = false
    var abortReason: String?
    var markerWarning: String?          // set when the "last backup" date could not be written to the drive
}

enum BackupEvent: Sendable {
    case scanning(checked: Int, total: Int)
    case planned(PlanInfo)
    case copying(index: Int, total: Int, name: String)
    case assetFraction(Double)      // 0...1 – files finished within the current asset
    case bytesCopied(Int64)         // bytes copied so far in this run
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
    @Published private(set) var plan: PlanInfo?
    @Published private(set) var drive: DriveInfo?
    @Published private(set) var etaSeconds: TimeInterval?
    @Published private(set) var speedBytesPerSecond: Double?
    @Published private(set) var analyzeOnly = false

    private static let bookmarkKey = "backupDestinationBookmark"
    private var worker: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isRefreshingDrive = false
    private var copyStart: Date?
    private var copiedBytes: Int64 = 0

    var folderName: String? { destinationURL?.lastPathComponent }

    var isRunning: Bool {
        switch phase {
        case .scanning, .copying: return true
        default: return false
        }
    }
    var isAnalyzing: Bool { isRunning && analyzeOnly }
    var isCopying: Bool { isRunning && !analyzeOnly }

    init() {
        restoreDestination()
    }

    // MARK: Destination

    /// Called with the folder URL returned by `.fileImporter`.
    func setDestination(_ url: URL) {
        phase = .idle
        summary = nil
        plan = nil
        drive = nil
        store(url)
        refreshDriveInfo()
        autoAnalyzeIfPossible()
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
            phase = .failed("Nie udało się zapamiętać folderu: \(error.localizedDescription)")
        }
        destinationURL = url
    }

    private func restoreDestination() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        store(url)
    }

    // MARK: Drive info (free space, last backup)

    func refreshDriveInfo() {
        guard let url = destinationURL else { drive = nil; return }
        guard !isRefreshingDrive else { return }          // a read is already in flight (USB can be slow)
        isRefreshingDrive = true
        refreshTask = Task {
            let info = await Task.detached(priority: .utility) {
                BackupEngine.readDriveInfo(root: url)
            }.value
            self.isRefreshingDrive = false
            guard url == self.destinationURL else { return }   // folder was changed meanwhile

            let wasConnected = self.drive?.totalBytes != nil
            if self.drive != info { self.drive = info }
            // The drive was just plugged in: analyze automatically (only if Photos access was already granted).
            if !wasConnected, info.totalBytes != nil, self.plan == nil {
                self.autoAnalyzeIfPossible()
            }
        }
    }

    /// Called every few seconds while the app is visible, so plugging in the drive is noticed without any tap.
    func pollDriveIfIdle() {
        if !isRunning { refreshDriveInfo() }
    }

    // MARK: Start / analyze / cancel

    /// Full backup (scans, then copies what is missing).
    func start() { launch(dryRun: false) }

    /// Only scans and works out how much is still to copy – nothing is written.
    func analyze() { launch(dryRun: true) }

    /// Runs the analysis in the background, but only if Photos access was already granted (never shows a prompt by itself).
    func autoAnalyzeIfPossible() {
        guard !isRunning, destinationURL != nil,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        launch(dryRun: true)
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        worker?.cancel()
    }

    private func launch(dryRun: Bool) {
        guard !isRunning, let root = destinationURL else { return }
        if !dryRun { summary = nil }
        overallProgress = 0
        iCloudProgress = nil
        etaSeconds = nil
        speedBytesPerSecond = nil
        copiedBytes = 0
        copyStart = nil
        isCancelling = false
        analyzeOnly = dryRun
        phase = .scanning(checked: 0, total: 0)
        if !dryRun { UIApplication.shared.isIdleTimerDisabled = true }   // keep the screen awake while copying
        runTask = Task { [weak self] in
            await self?.runBackup(root: root, dryRun: dryRun)
        }
    }

    private func runBackup(root: URL, dryRun: Bool) async {
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // 1. Photo Library permission (full access is required for a complete backup)
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized else {
            phase = .failed("Potrzebny jest pełny dostęp do Zdjęć. Otwórz Ustawienia › Prywatność i ochrona › Zdjęcia i zezwól tej aplikacji na pełny dostęp.")
            return
        }

        // 2. Access to the drive
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        guard (try? root.checkResourceIsReachable()) == true else {
            phase = .failed("Nie można uzyskać dostępu do wybranego folderu. Podłącz dysk i wybierz folder ponownie.")
            return
        }

        // 3. Run the engine off the main thread and listen to its events
        let (stream, continuation) = AsyncStream.makeStream(of: BackupEvent.self)
        worker = Task.detached(priority: .userInitiated) {
            await BackupEngine.run(root: root, dryRun: dryRun, emit: { continuation.yield($0) })
            continuation.finish()
        }

        for await event in stream {
            handle(event)
        }
        if isRunning { phase = dryRun ? .idle : .finished }   // safety net
        isCancelling = false
        refreshDriveInfo()
    }

    private func handle(_ event: BackupEvent) {
        switch event {
        case .scanning(let checked, let total):
            phase = .scanning(checked: checked, total: total)

        case .planned(let info):
            plan = info

        case .copying(let index, let total, let name):
            if copyStart == nil { copyStart = Date() }
            phase = .copying(index: index, total: total, fileName: name)
            overallProgress = Double(index - 1) / Double(max(total, 1))
            iCloudProgress = nil
            updateETA()

        case .assetFraction(let fraction):
            if case .copying(let index, let total, _) = phase {
                overallProgress = (Double(index - 1) + fraction) / Double(max(total, 1))
            }

        case .bytesCopied(let bytes):
            copiedBytes = bytes
            updateETA()

        case .iCloud(let fraction):
            if let fraction, fraction < 1 { iCloudProgress = fraction } else { iCloudProgress = nil }

        case .finished(let result):
            if analyzeOnly {                 // analysis only: no result screen
                phase = .idle
                return
            }
            summary = result
            iCloudProgress = nil
            etaSeconds = nil
            if let reason = result.abortReason {
                phase = .failed(reason)
                plan = nil
            } else if result.cancelled {
                phase = .cancelled
                plan = nil
            } else {
                overallProgress = 1
                phase = .finished
                if result.failedAssets == 0, let p = plan {
                    plan = PlanInfo(totalAssets: p.totalAssets, alreadyBackedUp: p.totalAssets)
                } else {
                    plan = nil
                }
            }
        }
    }

    private func updateETA() {
        guard let start = copyStart, case .copying(let index, let total, _) = phase else { return }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 5 else { return }

        if copiedBytes > 0 {
            speedBytesPerSecond = Double(copiedBytes) / elapsed
        }
        if let plan, plan.pendingBytes > 0, copiedBytes > 0 {
            let remaining = max(plan.pendingBytes - copiedBytes, 0)
            etaSeconds = Double(remaining) / (Double(copiedBytes) / elapsed)
        } else if index > 1 {
            etaSeconds = elapsed / Double(index - 1) * Double(total - index + 1)
        }
    }
}

// MARK: - Engine (runs off the main actor)

private struct PendingFile: @unchecked Sendable {
    let resource: PHAssetResource
    let destination: URL
    let size: Int64              // 0 = unknown
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
    nonisolated private static let markerName = ".usb-backup-info.json"

    // MARK: Main entry

    /// `dryRun == true`: only scan and report what is missing (`.planned`), copy nothing.
    nonisolated static func run(root: URL, dryRun: Bool, emit: @escaping @Sendable (BackupEvent) -> Void) async {
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
        var info = PlanInfo()
        info.totalAssets = total
        var checked = 0
        emit(.scanning(checked: 0, total: total))

        fetch.enumerateObjects { asset, _, stop in
            if Task.isCancelled { stop.pointee = true; return }

            let plan = planFiles(for: asset, root: root, fm: fm, reserved: &reserved)
            if plan.missing.isEmpty {
                if plan.existing > 0 { summary.alreadyBackedUp += 1 }
            } else {
                pending.append(PendingAsset(displayName: plan.name, date: asset.creationDate, files: plan.missing))
                info.pendingAssets += 1
                info.pendingFiles += plan.missing.count
                for file in plan.missing {
                    if file.size > 0 { info.pendingBytes += file.size } else { info.unknownSizeFiles += 1 }
                }
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

        info.alreadyBackedUp = summary.alreadyBackedUp
        emit(.planned(info))

        if dryRun {
            emit(.finished(summary))
            return
        }

        // Mark the run as started: if the app is closed mid-way, the drive still shows when it was last touched.
        if !pending.isEmpty {
            _ = saveMarker(root: root, status: .inProgress, summary: summary)
        }

        // ---- 3. Copy
        var consecutiveFailures = 0
        for (i, item) in pending.enumerated() {
            if Task.isCancelled { summary.cancelled = true; break }

            guard (try? root.checkResourceIsReachable()) == true else {
                summary.abortReason = "Dysk został odłączony. Skopiowano \(summary.copiedAssets) elementów, zanim kopia się zatrzymała. Podłącz go ponownie i uruchom kopię jeszcze raz – wznowi od miejsca przerwania."
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
                    emit(.bytesCopied(summary.bytesCopied))
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
                    summary.abortReason = "Przerwano po 10 błędach z rzędu. Ostatni błąd: \(error.localizedDescription)"
                    break
                }
            }
        }

        // Remember how and when this run ended (also when it was cancelled or had errors)
        let status: LastRunStatus
        if summary.abortReason != nil {
            status = .aborted
        } else if summary.cancelled {
            status = .cancelled
        } else if summary.failedAssets > 0 {
            status = .completedWithErrors
        } else {
            status = .completed
        }
        summary.markerWarning = saveMarker(root: root, status: status, summary: summary)

        emit(.iCloud(nil))
        emit(.finished(summary))
    }

    // MARK: Drive info & last backup

    nonisolated static func readDriveInfo(root: URL) -> DriveInfo {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        var info = DriveInfo()
        let keys: Set<URLResourceKey> = [.volumeNameKey,
                                         .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? root.resourceValues(forKeys: keys) {
            info.volumeName = values.volumeName
            info.totalBytes = values.volumeTotalCapacity.map { Int64($0) }
            info.availableBytes = values.volumeAvailableCapacity.map { Int64($0) }
                ?? values.volumeAvailableCapacityForImportantUsage
        }

        // Last run: marker file on the drive (survives reinstalling the app) merged with the copy kept by the app.
        if info.totalBytes != nil, let marker = loadMarker(root: root) {
            info.lastRun = marker.run
            info.lastRunStatus = marker.statusValue
            info.lastRunFailed = marker.failedAssets ?? 0
            info.lastCompleted = marker.completed
        }
        return info
    }

    /// Reads the marker from the drive and from the app's own copy and merges them (newest run wins).
    nonisolated private static func loadMarker(root: URL) -> BackupMarker? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [BackupMarker] = []

        if let data = try? Data(contentsOf: root.appendingPathComponent(markerName)),
           let marker = try? decoder.decode(BackupMarker.self, from: data) {
            found.append(marker)
        }
        if let data = UserDefaults.standard.data(forKey: defaultsKey(for: root)),
           let marker = try? decoder.decode(BackupMarker.self, from: data) {
            found.append(marker)
        }

        guard var newest = found.max(by: { ($0.run ?? .distantPast) < ($1.run ?? .distantPast) }) else { return nil }
        newest.lastCompleted = found.compactMap { $0.completed }.max()
        return newest
    }

    /// Saves the run result in the app and on the drive. Returns a warning text if writing to the drive failed.
    nonisolated private static func saveMarker(root: URL, status: LastRunStatus, summary: BackupSummary) -> String? {
        let previous = loadMarker(root: root)
        let now = Date()
        let marker = BackupMarker(lastRun: now,
                                  status: status.rawValue,
                                  lastCompleted: status == .completed ? now : previous?.completed,
                                  copiedAssets: summary.copiedAssets,
                                  failedAssets: summary.failedAssets)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(marker) else { return "Nie udało się zakodować daty kopii." }

        UserDefaults.standard.set(data, forKey: defaultsKey(for: root))
        do {
            // Plain (non-atomic) write: atomic writes can fail on exFAT/FAT drives.
            try data.write(to: root.appendingPathComponent(markerName))
            return nil
        } catch {
            return "Nie udało się zapisać daty kopii na dysku (\(error.localizedDescription)). Zapisano ją tylko w aplikacji."
        }
    }

    nonisolated private static func defaultsKey(for root: URL) -> String {
        let volume = (try? root.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "?"
        return "lastRunMarker.\(volume)/\(root.lastPathComponent)"
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
                missing.append(PendingFile(resource: resource, destination: resolved.url, size: fileSize(of: resource)))
            }
        }
        return (missing, existing, primary.originalFilename)
    }

    /// iOS has no public API for a resource's size. `fileSize` is an undocumented but long-stable property;
    /// it is guarded so nothing breaks if it ever disappears (the estimate then shows "~" / unknown).
    nonisolated private static func fileSize(of resource: PHAssetResource) -> Int64 {
        guard resource.responds(to: NSSelectorFromString("fileSize")) else { return 0 }
        return (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
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
