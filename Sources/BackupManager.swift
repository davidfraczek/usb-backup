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

/// One entry of the backup history (kept on the drive, in `.usb-backup-info.json`).
struct RunRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var status: LastRunStatus
    var copiedAssets: Int
    var copiedFiles: Int
    var failedAssets: Int
    var bytesCopied: Int64
    var duration: TimeInterval
    var verifiedFiles: Int?             // optional: older history entries don't have these fields
    var verifyFailed: Int?
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
    var history: [RunRecord] = []       // newest first
}

/// Small JSON file kept on the drive (`.usb-backup-info.json`) – a copy is also kept inside the app.
private struct BackupMarker: Codable {
    var lastRun: Date?
    var status: String?
    var lastCompleted: Date?
    var copiedAssets: Int?
    var failedAssets: Int?
    var lastBackup: Date?               // legacy field written by the first version (= last fully successful run)
    var history: [RunRecord]?           // newest first, at most `BackupEngine.historyLimit` entries

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
    var duration: TimeInterval = 0
    var verifiedFiles = 0               // files whose size on the drive matches the original
    var verifyFailed = 0                // files that failed the check (they are deleted, so the next run copies them again)
    var failedAssetIDs: [String] = []   // PHAsset.localIdentifier of everything that failed – used by "Try again"
    var blockedForSpace = false         // the run was not started because the drive is too small
}

/// The backup would not fit on the drive – the user is asked whether to go ahead anyway.
struct SpaceShortfall: Equatable, Sendable {
    var needed: Int64
    var free: Int64
}

enum BackupEvent: Sendable {
    case scanning(checked: Int, total: Int)
    case planned(PlanInfo)
    case verifying(checked: Int, total: Int)
    case insufficientSpace(needed: Int64, free: Int64)
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
        case verifying(checked: Int, total: Int)
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
    @Published private(set) var folderBytes: Int64?           // size of the chosen backup folder on the drive
    @Published private(set) var isMeasuringFolder = false
    @Published private(set) var spaceShortfall: SpaceShortfall?   // set when a backup would not fit; the UI asks what to do
    @Published var options = BackupOptions.load() {
        didSet { optionsDidChange(oldValue) }
    }

    private static let bookmarkKey = "backupDestinationBookmark"
    private var worker: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isRefreshingDrive = false
    private var measureGeneration = 0
    private var needsReanalysis = false
    private var copyStart: Date?
    private var copiedBytes: Int64 = 0
    private var isRetryRun = false

    var folderName: String? { destinationURL?.lastPathComponent }

    var isRunning: Bool {
        switch phase {
        case .scanning, .copying, .verifying: return true
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
        folderBytes = nil
        isMeasuringFolder = false
        measureGeneration += 1             // drops any measurement of the previous folder still in flight
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
            phase = .failed(tr("Nie udało się zapamiętać folderu: \(error.localizedDescription)",
               "Couldn't remember the folder: \(error.localizedDescription)"))
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
            // The drive was just plugged in: measure the backup folder and analyze automatically
            // (the analysis only if Photos access was already granted).
            if !wasConnected, info.totalBytes != nil {
                self.measureBackupFolder()
                if self.plan == nil { self.autoAnalyzeIfPossible() }
            }
        }
    }

    /// Adds up the size of everything inside the chosen folder, in the background (a big folder on a slow USB drive can take a while).
    func measureBackupFolder() {
        guard let url = destinationURL, !isCopying else { return }
        measureGeneration += 1
        let generation = measureGeneration
        isMeasuringFolder = true
        Task {
            let size = await Task.detached(priority: .utility) {
                BackupEngine.folderSize(root: url)
            }.value
            guard generation == self.measureGeneration else { return }   // a newer measurement (or a backup run) superseded this one
            self.isMeasuringFolder = false
            if url == self.destinationURL, let size { self.folderBytes = size }
        }
    }

    /// Called every few seconds while the app is visible, so plugging in the drive is noticed without any tap.
    func pollDriveIfIdle() {
        if !isRunning { refreshDriveInfo() }
    }

    // MARK: Start / analyze / cancel

    /// Full backup (scans, then copies what is missing).
    /// If an earlier analysis already shows that it won't fit on the drive, nothing starts and the user is asked first.
    func start() {
        guard !isRunning else { return }
        if let plan, let free = drive?.availableBytes, plan.pendingBytes > free {
            spaceShortfall = SpaceShortfall(needed: plan.pendingBytes, free: free)
            return
        }
        launch(dryRun: false)
    }

    /// The user confirmed: copy as much as fits (oldest items first), the run stops cleanly when the drive is full.
    func startAnyway() {
        spaceShortfall = nil
        launch(dryRun: false, force: true)
    }

    func dismissShortfall() { spaceShortfall = nil }

    /// Copies again only the items that failed in the last run (no new scan of the whole library).
    func retryFailed() {
        guard !isRunning, let ids = summary?.failedAssetIDs, !ids.isEmpty else { return }
        launch(dryRun: false, retryIDs: ids)
    }

    /// Only scans and works out how much is still to copy – nothing is written.
    func analyze() { launch(dryRun: true) }

    /// Runs the analysis in the background, but only if Photos access was already granted (never shows a prompt by itself).
    func autoAnalyzeIfPossible() {
        guard !isRunning, destinationURL != nil,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        launch(dryRun: true)
    }

    /// Settings changed: the old estimate no longer applies, so it is recalculated (once nothing else is running).
    private func optionsDidChange(_ old: BackupOptions) {
        guard options != old else { return }
        options.save()
        plan = nil
        needsReanalysis = true
        runPendingReanalysis()
    }

    private func runPendingReanalysis() {
        guard needsReanalysis, !isRunning else { return }
        needsReanalysis = false
        plan = nil
        autoAnalyzeIfPossible()
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        worker?.cancel()
    }

    private func launch(dryRun: Bool, retryIDs: [String]? = nil, force: Bool = false) {
        guard !isRunning, let root = destinationURL else { return }
        if !dryRun { summary = nil }
        isRetryRun = retryIDs != nil
        overallProgress = 0
        iCloudProgress = nil
        etaSeconds = nil
        speedBytesPerSecond = nil
        copiedBytes = 0
        copyStart = nil
        isCancelling = false
        analyzeOnly = dryRun
        if !dryRun {
            measureGeneration += 1          // a measurement started before the run would be outdated
            isMeasuringFolder = false
        }
        phase = .scanning(checked: 0, total: 0)
        if !dryRun { UIApplication.shared.isIdleTimerDisabled = true }   // keep the screen awake while copying
        runTask = Task { [weak self] in
            await self?.runBackup(root: root, dryRun: dryRun, retryIDs: retryIDs, force: force)
        }
    }

    private func runBackup(root: URL, dryRun: Bool, retryIDs: [String]?, force: Bool) async {
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // 1. Photo Library permission (full access is required for a complete backup)
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized else {
            phase = .failed(tr("Potrzebny jest pełny dostęp do Zdjęć. Otwórz Ustawienia › Prywatność i ochrona › Zdjęcia i zezwól tej aplikacji na pełny dostęp.",
                         "Full access to Photos is required. Open Settings › Privacy & Security › Photos and allow full access for this app."))
            return
        }

        // 2. Access to the drive
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        guard (try? root.checkResourceIsReachable()) == true else {
            phase = .failed(tr("Nie można uzyskać dostępu do wybranego folderu. Podłącz dysk i wybierz folder ponownie.",
                         "Can't access the selected folder. Plug in the drive and choose the folder again."))
            return
        }

        // 3. Run the engine off the main thread and listen to its events
        let settings = options
        let (stream, continuation) = AsyncStream.makeStream(of: BackupEvent.self)
        worker = Task.detached(priority: .userInitiated) {
            await BackupEngine.run(root: root, dryRun: dryRun, settings: settings,
                                   retryIDs: retryIDs, force: force, emit: { continuation.yield($0) })
            continuation.finish()
        }

        for await event in stream {
            handle(event)
        }
        if isRunning { phase = dryRun ? .idle : .finished }   // safety net
        isCancelling = false
        refreshDriveInfo()
        if !dryRun { measureBackupFolder() }     // exact size of the backup folder after copying
        if dryRun { runPendingReanalysis() }     // settings changed while the analysis was running
    }

    private func handle(_ event: BackupEvent) {
        switch event {
        case .scanning(let checked, let total):
            phase = .scanning(checked: checked, total: total)

        case .planned(let info):
            plan = info

        case .verifying(let checked, let total):
            phase = .verifying(checked: checked, total: total)
            iCloudProgress = nil

        case .insufficientSpace(let needed, let free):
            spaceShortfall = SpaceShortfall(needed: needed, free: free)

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
            if analyzeOnly || result.blockedForSpace {     // analysis only / not started because of missing space: no result screen
                phase = .idle
                return
            }
            summary = result
            iCloudProgress = nil
            etaSeconds = nil
            if result.copiedFiles > 0 { folderBytes = (folderBytes ?? 0) + result.bytesCopied }   // instant estimate; exact value is measured right after the run
            if let reason = result.abortReason {
                phase = .failed(reason)
                plan = nil
            } else if result.cancelled {
                phase = .cancelled
                plan = nil
            } else {
                overallProgress = 1
                phase = .finished
                if result.failedAssets == 0, !isRetryRun, let p = plan {
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
    let id: String               // PHAsset.localIdentifier
    let displayName: String
    let date: Date?
    let files: [PendingFile]
}

/// A file that was copied and still has to pass the final check.
private struct VerifyItem: Sendable {
    let assetID: String
    let name: String
    let url: URL
    let expectedBytes: Int64
}

/// The file on the drive does not have the same size as the original.
private struct VerificationError: LocalizedError {
    let expected: Int64
    let actual: Int64

    var errorDescription: String? {
        tr("Rozmiar pliku na dysku (\(actual) B) różni się od oryginału (\(expected) B).",
           "The file size on the drive (\(actual) B) differs from the original (\(expected) B).")
    }
}

/// Receives the data of one photo/video from iOS in chunks and writes it to the drive,
/// counting the bytes – that count is the exact size of the original.
private final class StreamSink: @unchecked Sendable {
    private let handle: FileHandle
    private(set) var written: Int64 = 0
    private(set) var error: Error?

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    func append(_ data: Data) {
        guard error == nil else { return }          // after the first write error the rest is ignored
        do {
            try handle.write(contentsOf: data)
            written += Int64(data.count)
        } catch {
            self.error = error
        }
    }

    /// Flushes everything to the drive and closes the file.
    func finish() throws {
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func abort() { try? handle.close() }
}

/// Remembers which folders exist, so the "already backed up under another layout" check stays cheap on a slow USB drive.
private final class FolderCache {
    private var known: [String: Bool] = [:]

    func exists(_ url: URL, fm: FileManager) -> Bool {
        if let cached = known[url.path] { return cached }
        var isDirectory: ObjCBool = false
        let result = fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        known[url.path] = result
        return result
    }
}

enum BackupEngine {

    /// FAT/exFAT drives store timestamps with ~2 s resolution.
    nonisolated private static let dateTolerance: TimeInterval = 3
    nonisolated private static let markerName = ".usb-backup-info.json"
    nonisolated static let historyLimit = 30

    // MARK: Main entry

    /// `dryRun == true`: only scan and report what is missing (`.planned`), copy nothing.
    /// `retryIDs != nil`: only those library items are processed (used by "Try again").
    /// `force == true`: copy even if the estimate says the drive is too small.
    nonisolated static func run(root: URL,
                                dryRun: Bool,
                                settings: BackupOptions,
                                retryIDs: [String]?,
                                force: Bool,
                                emit: @escaping @Sendable (BackupEvent) -> Void) async {
        var summary = BackupSummary()
        let fm = FileManager.default

        // ---- 1. Fetch every photo & video in the library
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        switch settings.media {
        case .all:
            options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                            PHAssetMediaType.image.rawValue,
                                            PHAssetMediaType.video.rawValue)
        case .photos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }
        let fetch: PHFetchResult<PHAsset>
        if let retryIDs {
            fetch = PHAsset.fetchAssets(withLocalIdentifiers: retryIDs, options: options)
        } else {
            fetch = PHAsset.fetchAssets(with: options)
        }
        let total = fetch.count

        // ---- 2. Plan: work out which files are not on the drive yet
        var pending: [PendingAsset] = []
        var reserved = Set<String>()
        let folderCache = FolderCache()
        var info = PlanInfo()
        info.totalAssets = total
        var checked = 0
        emit(.scanning(checked: 0, total: total))

        fetch.enumerateObjects { asset, _, stop in
            if Task.isCancelled { stop.pointee = true; return }

            let plan = planFiles(for: asset, root: root, fm: fm, settings: settings, cache: folderCache, reserved: &reserved)
            if plan.missing.isEmpty {
                if plan.existing > 0 { summary.alreadyBackedUp += 1 }
            } else {
                pending.append(PendingAsset(id: asset.localIdentifier, displayName: plan.name,
                                            date: asset.creationDate, files: plan.missing))
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

        // Not enough room on the drive: don't start, let the user decide (see `BackupManager.startAnyway`).
        // Only sizes iOS reports are counted, so the real need can be slightly higher.
        if !force, info.pendingBytes > 0, let free = availableBytes(root: root), info.pendingBytes > free {
            emit(.insufficientSpace(needed: info.pendingBytes, free: free))
            summary.blockedForSpace = true
            emit(.finished(summary))
            return
        }

        // Mark the run as started: if the app is closed mid-way, the drive still shows when it was last touched.
        if !pending.isEmpty {
            _ = saveMarker(root: root, status: .inProgress, summary: summary, isRetry: retryIDs != nil)
        }

        // ---- 3. Copy
        let runStart = Date()
        var verifyList: [VerifyItem] = []
        var consecutiveFailures = 0
        for (i, item) in pending.enumerated() {
            if Task.isCancelled { summary.cancelled = true; break }

            guard (try? root.checkResourceIsReachable()) == true else {
                summary.abortReason = tr("Dysk został odłączony. Skopiowano \(summary.copiedAssets) elementów, zanim kopia się zatrzymała. Podłącz go ponownie i uruchom kopię jeszcze raz – wznowi od miejsca przerwania.",
                                              "The drive was disconnected. \(summary.copiedAssets) items were copied before the backup stopped. Plug it back in and run the backup again – it will resume where it stopped.")
                break
            }

            emit(.copying(index: i + 1, total: pending.count, name: item.displayName))

            do {
                let folder = item.files[0].destination.deletingLastPathComponent()
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)

                for (j, file) in item.files.enumerated() {
                    let bytes = try await copy(file, date: item.date, fm: fm) { emit(.iCloud($0)) }
                    verifyList.append(VerifyItem(assetID: item.id,
                                                 name: file.destination.lastPathComponent,
                                                 url: file.destination,
                                                 expectedBytes: bytes))
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
                if summary.failedAssetIDs.count < 5000 { summary.failedAssetIDs.append(item.id) }
                if summary.errors.count < 50 {
                    summary.errors.append("\(item.displayName): \(error.localizedDescription)")
                }
                if isOutOfSpace(error) {
                    summary.abortReason = tr("Na dysku skończyło się miejsce. Skopiowano \(summary.copiedAssets) elementów. Zwolnij miejsce lub wybierz większy dysk i uruchom kopię ponownie.",
                                             "The drive is full. \(summary.copiedAssets) items were copied. Free up space or use a larger drive, then run the backup again.")
                    break
                }
                if consecutiveFailures >= 10 {
                    summary.abortReason = tr("Przerwano po 10 błędach z rzędu. Ostatni błąd: \(error.localizedDescription)",
                                                  "Stopped after 10 failures in a row. Last error: \(error.localizedDescription)")
                    break
                }
            }
        }

        // ---- 4. Verify: every copied file must still be on the drive with exactly the size of the original.
        // A file that fails is deleted, so the next run copies it again (otherwise it would count as "already backed up").
        if !verifyList.isEmpty, (try? root.checkResourceIsReachable()) == true {
            var badAssets = Set<String>()
            for (n, item) in verifyList.enumerated() {
                let actual = (try? fm.attributesOfItem(atPath: item.url.path))
                    .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? -1
                if actual == item.expectedBytes {
                    summary.verifiedFiles += 1
                } else {
                    summary.verifyFailed += 1
                    badAssets.insert(item.assetID)
                    try? fm.removeItem(at: item.url)
                    if summary.errors.count < 50 {
                        summary.errors.append("\(item.name): " + VerificationError(expected: item.expectedBytes, actual: max(actual, 0)).localizedDescription)
                    }
                }
                if (n + 1) % 200 == 0 { emit(.verifying(checked: n + 1, total: verifyList.count)) }
            }
            emit(.verifying(checked: verifyList.count, total: verifyList.count))

            // Items with a failed check count as failed, not as copied
            for id in badAssets {
                if !summary.failedAssetIDs.contains(id) { summary.failedAssetIDs.append(id) }
                summary.failedAssets += 1
                summary.copiedAssets = max(summary.copiedAssets - 1, 0)
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
        summary.duration = Date().timeIntervalSince(runStart)
        summary.markerWarning = saveMarker(root: root, status: status, summary: summary, isRetry: retryIDs != nil)

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
            info.history = marker.history ?? []
        }
        return info
    }

    /// Total size of all files inside `root` (nil if the folder can't be read).
    nonisolated static func folderSize(root: URL) -> Int64? {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard (try? root.checkResourceIsReachable()) == true else { return nil }     // drive unplugged: don't report 0

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: keys,
                                                              options: [],
                                                              errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
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

        // History: union of both copies (matched by id), newest first
        var seen = Set<UUID>()
        newest.history = found.flatMap { $0.history ?? [] }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
            .prefix(historyLimit)
            .map { $0 }
        return newest
    }

    /// Saves the run result in the app and on the drive. Returns a warning text if writing to the drive failed.
    /// `isRetry`: a "Try again" run only looked at the items that failed before, so on its own it proves
    /// the whole backup is complete only if the previous run had finished (with errors) and nothing else was missing.
    nonisolated private static func saveMarker(root: URL, status: LastRunStatus, summary: BackupSummary, isRetry: Bool) -> String? {
        let previous = loadMarker(root: root)
        let now = Date()

        // History: a run is recorded when it actually did something (copied files, had errors, was cancelled or aborted).
        // A run that found nothing to copy only refreshes the "last backup" date, so the list isn't flooded.
        var history = previous?.history ?? []
        let didSomething = summary.copiedAssets > 0 || summary.failedAssets > 0 || status != .completed
        if status != .inProgress, didSomething {
            history.insert(RunRecord(date: now,
                                     status: status,
                                     copiedAssets: summary.copiedAssets,
                                     copiedFiles: summary.copiedFiles,
                                     failedAssets: summary.failedAssets,
                                     bytesCopied: summary.bytesCopied,
                                     duration: summary.duration,
                                     verifiedFiles: summary.verifiedFiles,
                                     verifyFailed: summary.verifyFailed), at: 0)
            history = Array(history.prefix(historyLimit))
        }

        let marker = BackupMarker(lastRun: now,
                                  status: status.rawValue,
                                  lastCompleted: (status == .completed && (!isRetry || previous?.statusValue == .completedWithErrors))
                                      ? now : previous?.completed,
                                  copiedAssets: summary.copiedAssets,
                                  failedAssets: summary.failedAssets,
                                  history: history)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(marker) else { return tr("Nie udało się zakodować daty kopii.", "Couldn't encode the backup date.") }

        UserDefaults.standard.set(data, forKey: defaultsKey(for: root))
        do {
            // Plain (non-atomic) write: atomic writes can fail on exFAT/FAT drives.
            try data.write(to: root.appendingPathComponent(markerName))
            return nil
        } catch {
            return tr("Nie udało się zapisać daty kopii na dysku (\(error.localizedDescription)). Zapisano ją tylko w aplikacji.",
                      "Couldn't write the backup date to the drive (\(error.localizedDescription)). It was saved in the app only.")
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
                                              settings: BackupOptions,
                                              cache: FolderCache,
                                              reserved: inout Set<String>) -> (missing: [PendingFile], existing: Int, name: String) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first else {
            return ([], 0, "")
        }
        let stem = (primary.originalFilename as NSString).deletingPathExtension
        let folder = folderURL(root: root, date: asset.creationDate, layout: settings.layout)
        // Files backed up earlier under another folder layout still count as "already on the drive".
        let alternateFolders = FolderLayout.allCases
            .filter { $0 != settings.layout }
            .map { folderURL(root: root, date: asset.creationDate, layout: $0) }
            .filter { $0 != folder && cache.exists($0, fm: fm) }

        var missing: [PendingFile] = []
        var existing = 0

        for resource in resources {
            guard let name = targetName(for: resource, stem: stem, includeEdited: settings.includeEdited) else { continue }
            let resolved = resolve(name: name, folder: folder, alternateFolders: alternateFolders,
                                   date: asset.creationDate, fm: fm, reserved: &reserved)
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
    nonisolated private static func targetName(for resource: PHAssetResource, stem: String, includeEdited: Bool) -> String? {
        let ext = (resource.originalFilename as NSString).pathExtension
        switch resource.type {
        case .photo, .video, .alternatePhoto:          // originals (alternatePhoto = RAW of a RAW+JPEG pair)
            return resource.originalFilename
        case .pairedVideo:                             // Live Photo video
            return stem + "." + (ext.isEmpty ? "MOV" : ext)
        case .fullSizePhoto:
            return includeEdited ? "\(stem)_edited." + (ext.isEmpty ? "jpg" : ext) : nil
        case .fullSizeVideo, .fullSizePairedVideo:
            return includeEdited ? "\(stem)_edited." + (ext.isEmpty ? "mov" : ext) : nil
        default:                                       // adjustment data, thumbnails, audio …
            return nil
        }
    }

    /// Returns the destination URL and whether this exact file is already on the drive.
    /// A same-named file counts as "already backed up" only if its date matches the asset's creation date;
    /// otherwise (e.g. IMG_0001 from a different phone) we pick `IMG_0001_1.HEIC`, and so on.
    nonisolated private static func resolve(name: String,
                                            folder: URL,
                                            alternateFolders: [URL],
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

            // Not in the current layout: maybe it was backed up earlier under another folder layout.
            for alternate in alternateFolders {
                let other = alternate.appendingPathComponent(candidate)
                if fm.fileExists(atPath: other.path), looksLikeSameFile(other, date: date, fm: fm) {
                    reserved.insert(key)
                    return (other, true)
                }
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

    nonisolated private static func folderURL(root: URL, date: Date?, layout: FolderLayout) -> URL {
        var url = root
        for part in layout.pathComponents(for: date) {
            url.appendPathComponent(part, isDirectory: true)
        }
        return url
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
            // `expected` = number of bytes iOS delivered = the exact size of the original
            let expected = try await writeResource(file.resource, to: temp, onDownload: onDownload)

            // Check 1: what landed on the drive must have exactly that size
            let onDrive = (try? fm.attributesOfItem(atPath: temp.path))
                .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? -1
            guard onDrive == expected else { throw VerificationError(expected: expected, actual: max(onDrive, 0)) }

            if let date {
                try? fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: temp.path)
            }
            try fm.moveItem(at: temp, to: file.destination)
            return expected
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    /// Streams the original data of the resource to `url` (downloading it from iCloud if necessary),
    /// flushes it to the drive and returns the number of bytes received.
    nonisolated private static func writeResource(_ resource: PHAssetResource,
                                                  to url: URL,
                                                  onDownload: @escaping @Sendable (Double) -> Void) async throws -> Int64 {
        let sink = try StreamSink(url: url)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true            // fetch full-resolution original from iCloud
        options.progressHandler = { progress in onDownload(progress) }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { chunk in sink.append(chunk) },
                    completionHandler: { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    })
            }
        } catch {
            sink.abort()
            throw error
        }

        if let writeError = sink.error {        // e.g. the drive is full
            sink.abort()
            throw writeError
        }
        try sink.finish()
        return sink.written
    }

    // MARK: Helpers

    nonisolated private static func availableBytes(root: URL) -> Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey,
                                                        .volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacity.map { Int64($0) } ?? values?.volumeAvailableCapacityForImportantUsage
    }

    /// "No space left on the device" – as a Cocoa error (640) or a POSIX error (ENOSPC), also when wrapped inside another error.
    nonisolated private static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError { return true }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}
