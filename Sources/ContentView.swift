import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var manager = BackupManager()
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    destinationCard
                    startButton
                    progressSection
                    summarySection
                }
                .padding()
            }
            .navigationTitle("USB Photo Backup")
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { manager.setDestination(url) }
            case .failure(let error):
                manager.reportError(error)
            }
        }
    }

    // MARK: - Destination

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Backup destination", systemImage: "externaldrive.fill")
                .font(.headline)

            if let label = manager.destinationLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No folder selected. Connect your USB drive or SSD, then choose a folder on it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showingPicker = true
            } label: {
                Label(manager.destinationURL == nil ? "Select USB Folder" : "Change Folder",
                      systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(manager.isRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Start / Cancel

    @ViewBuilder
    private var startButton: some View {
        if manager.isRunning {
            Button(role: .destructive) {
                manager.cancel()
            } label: {
                Text(manager.isCancelling ? "Cancelling…" : "Cancel Backup")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(manager.isCancelling)
        } else {
            Button {
                manager.start()
            } label: {
                Label("Start Backup", systemImage: "arrow.up.doc.on.clipboard")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.destinationURL == nil)
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        switch manager.phase {
        case .scanning(let checked, let total):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning library and drive…").font(.headline)
                }
                if total > 0 {
                    ProgressView(value: Double(checked), total: Double(total))
                    Text("Checked \(checked) of \(total)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .copying(let index, let total, let name):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: manager.overallProgress)
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Copying \(index) of \(total)").font(.headline)
                    Spacer()
                    Text(manager.overallProgress, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(name)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let f = manager.iCloudProgress {
                    Label("Downloading from iCloud… \(Int(f * 100))%", systemImage: "icloud.and.arrow.down")
                        .font(.caption).foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .cancelled:
            Label("Backup cancelled. Run it again to continue where it stopped.", systemImage: "stop.circle")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .finished:
            Label(finishedMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .idle:
            EmptyView()
        }
    }

    private var finishedMessage: String {
        guard let s = manager.summary else { return "Backup complete." }
        return s.copiedAssets == 0 && s.failedAssets == 0
            ? "Everything is already backed up."
            : "Backup complete."
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if let s = manager.summary, !manager.isRunning {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last run").font(.headline)
                Text("Copied: \(s.copiedAssets) items (\(s.copiedFiles) files, \(ByteCountFormatter.string(fromByteCount: s.bytesCopied, countStyle: .file)))")
                Text("Already on drive: \(s.alreadyBackedUp)")
                if s.failedAssets > 0 {
                    Text("Failed: \(s.failedAssets)").foregroundStyle(.red)
                    DisclosureGroup("Show errors") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(s.errors, id: \.self) { Text($0).font(.caption) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    ContentView()
}
