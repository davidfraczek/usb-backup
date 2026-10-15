import UIKit

/// Builds a plain-text report of the last backup run (for sending it to someone who helps with a problem).
/// It contains file names and error messages, but no photo content and no location data.
enum LogExport {

    @MainActor
    static func write(summary: BackupSummary,
                      outcome: String,
                      drive: DriveInfo?,
                      plan: PlanInfo?,
                      options: BackupOptions,
                      folderName: String?,
                      folderBytes: Int64?) -> URL? {
        var lines: [String] = []
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current

        lines.append("USB Backup – log")
        lines.append("Date: \(iso.string(from: Date()))")
        lines.append("App: \(appVersion())")
        lines.append("Device: \(deviceModel()), iOS \(UIDevice.current.systemVersion)")
        lines.append("Language: \(Lang.isPolish ? "pl" : "en")")
        lines.append("")

        lines.append("== Drive ==")
        lines.append("Folder: \(folderName ?? "-")")
        lines.append("Volume: \(drive?.volumeName ?? "-")")
        if let total = drive?.totalBytes { lines.append("Capacity: \(formatBytes(total))") }
        if let free = drive?.availableBytes { lines.append("Free: \(formatBytes(free))") }
        if let folderBytes { lines.append("Backup folder size: \(formatBytes(folderBytes))") }
        lines.append("")

        lines.append("== Settings ==")
        lines.append("Media: \(options.media.rawValue)")
        lines.append("Edited versions: \(options.includeEdited)")
        lines.append("Folder layout: \(options.layout.rawValue)")
        lines.append("iCloud over cellular: \(options.allowCellular)")
        lines.append("")

        lines.append("== Result ==")
        lines.append("Outcome: \(outcome)")
        lines.append("Duration: \(Int(summary.duration)) s")
        lines.append("Copied: \(summary.copiedAssets) items, \(summary.copiedFiles) files, \(formatBytes(summary.bytesCopied))")
        lines.append("Already on drive: \(summary.alreadyBackedUp)")
        lines.append("Failed items: \(summary.failedAssets)")
        lines.append("Verified files: \(summary.verifiedFiles), failed verification: \(summary.verifyFailed)")
        lines.append("Skipped (iCloud over cellular): \(summary.skippedCellular)")
        if let plan {
            lines.append("Library items scanned: \(plan.totalAssets), missing on drive at start: \(plan.pendingAssets) (\(formatBytes(plan.pendingBytes)))")
        }
        if let reason = summary.abortReason { lines.append("Stopped because: \(reason)") }
        if let warning = summary.markerWarning { lines.append("Warning: \(warning)") }
        lines.append("")

        lines.append("== Errors (\(summary.errors.count)\(summary.failedAssets > summary.errors.count ? " of \(summary.failedAssets)" : "")) ==")
        if summary.errors.isEmpty {
            lines.append("none")
        } else {
            for (index, error) in summary.errors.enumerated() {
                lines.append("\(index + 1). \(error)")
            }
        }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("USB-Backup-log-\(stamp.string(from: Date())).txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func deviceModel() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
