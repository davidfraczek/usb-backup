import SwiftUI

/// List of the most recent backup runs (stored on the drive, so it survives reinstalling the app).
struct HistoryView: View {
    @ObservedObject var manager: BackupManager
    @Environment(\.dismiss) private var dismiss

    private var runs: [RunRecord] { manager.drive?.history ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    emptyState
                } else {
                    List(runs) { run in
                        RunRow(run: run)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(tr("Historia kopii", "Backup history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Gotowe", "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(manager.drive?.totalBytes == nil
                 ? tr("Podłącz dysk, aby zobaczyć historię", "Plug in the drive to see the history")
                 : tr("Brak zapisanych przebiegów", "No runs recorded yet"))
                .font(.headline)
            Text(tr("Po każdej kopii pojawi się tu wpis: data, ile skopiowano i ile było błędów. Historia jest zapisana na dysku (ostatnie \(BackupEngine.historyLimit) przebiegów).",
                    "After each backup an entry appears here: date, how much was copied and how many errors there were. The history is stored on the drive (last \(BackupEngine.historyLimit) runs)."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

private struct RunRow: View {
    let run: RunRecord

    private var statusInfo: (icon: String, color: Color, text: String) {
        switch run.status {
        case .completed:
            return ("checkmark.circle.fill", .green, tr("Zakończona", "Completed"))
        case .completedWithErrors:
            return ("exclamationmark.circle.fill", .orange, tr("Z błędami", "With errors"))
        case .cancelled:
            return ("stop.circle.fill", .orange, tr("Anulowana", "Cancelled"))
        case .aborted:
            return ("xmark.octagon.fill", .red, tr("Przerwana", "Interrupted"))
        case .inProgress:
            return ("questionmark.circle.fill", .orange, tr("Przerwana nagle", "Stopped unexpectedly"))
        }
    }

    var body: some View {
        let info = statusInfo
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: info.icon)
                .font(.title3)
                .foregroundStyle(info.color)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatDate(run.date))
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Text(info.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(info.color)
                }

                Text(tr("Skopiowano: \(run.copiedAssets) elementów · \(formatBytes(run.bytesCopied))",
                        "Copied: \(run.copiedAssets) items · \(formatBytes(run.bytesCopied))"))
                    .font(.subheadline)

                HStack(spacing: 12) {
                    Label(tr("Błędy: \(run.failedAssets)", "Errors: \(run.failedAssets)"),
                          systemImage: run.failedAssets > 0 ? "exclamationmark.triangle" : "checkmark")
                        .foregroundStyle(run.failedAssets > 0 ? Color.red : Color.secondary)
                    if run.duration >= 1 {
                        Label(durationText(run.duration), systemImage: "clock")
                    }
                    Label(tr("\(run.copiedFiles) plików", "\(run.copiedFiles) files"), systemImage: "doc")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let verified = run.verifiedFiles {
                    let failed = run.verifyFailed ?? 0
                    Label(failed == 0
                          ? tr("Zweryfikowano: \(verified) plików", "Verified: \(verified) files")
                          : tr("Weryfikacja: \(failed) niezgodnych z \(verified + failed)", "Verification: \(failed) of \(verified + failed) don't match"),
                          systemImage: failed == 0 ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(failed == 0 ? Color.green : Color.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
