import SwiftUI
import UniformTypeIdentifiers

// MARK: - Helpers (localized formatting)

func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var index = 0
    while value >= 1000 && index < units.count - 1 {
        value /= 1000
        index += 1
    }
    let digits: ClosedRange<Int> = index == 0 ? 0...0 : (value < 10 ? 0...2 : 0...1)
    let number = value.formatted(.number.precision(.fractionLength(digits)).locale(Lang.locale))
    return number + " " + units[index]
}

private func relativeText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Lang.locale
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    return formatter.localizedString(for: date, relativeTo: Date())
}

func formatDate(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Lang.locale))
}

func durationText(_ seconds: TimeInterval) -> String {
    var calendar = Calendar.current
    calendar.locale = Lang.locale
    let formatter = DateComponentsFormatter()
    formatter.calendar = calendar
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: max(seconds, 1)) ?? "—"
}

// MARK: - Main screen

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @StateObject private var manager = BackupManager()
    @State private var showingPicker = false
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showErrors = true
    private let errorListLimit = 50
    @AppStorage(Lang.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    driveCard
                    if manager.destinationURL != nil {
                        statsGrid
                        historyButton
                        spaceWarning
                    }
                    statusCard
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            // Attached to a different view than the "not enough space" alert, so the two never compete.
            .alert(manager.powerWarning?.title ?? "",
                   isPresented: Binding(get: { manager.powerWarning != nil },
                                        set: { if !$0 { manager.dismissPowerWarning() } }),
                   presenting: manager.powerWarning) { _ in
                Button(tr("Kopiuj mimo to", "Copy anyway")) { manager.startAfterPowerWarning() }
                Button(tr("Anuluj", "Cancel"), role: .cancel) { }
            } message: { warning in
                Text(warning.message)
            }
        }
        .environment(\.locale, Lang.localeForCode(languageRaw))
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(manager: manager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(tr("Za mało miejsca na dysku", "Not enough space on the drive"),
               isPresented: Binding(get: { manager.spaceShortfall != nil },
                                    set: { if !$0 { manager.dismissShortfall() } }),
               presenting: manager.spaceShortfall) { _ in
            Button(tr("Kopiuj mimo to", "Copy anyway")) { manager.startAnyway() }
            Button(tr("Anuluj", "Cancel"), role: .cancel) { }
        } message: { shortfall in
            Text(tr("Do skopiowania jest ok. \(formatBytes(shortfall.needed)), a na dysku wolne jest \(formatBytes(shortfall.free)) (brakuje ok. \(formatBytes(shortfall.needed - shortfall.free))). Zwolnij miejsce albo wybierz większy dysk.\n\nMożesz też skopiować mimo to: pliki są zapisywane od najstarszych, a kopia zatrzyma się, gdy skończy się miejsce.",
                    "About \(formatBytes(shortfall.needed)) needs to be copied, but only \(formatBytes(shortfall.free)) is free on the drive (about \(formatBytes(shortfall.needed - shortfall.free)) short). Free up space or use a larger drive.\n\nYou can also copy anyway: files are written oldest first, and the backup stops when the drive is full."))
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(manager: manager)
                .environment(\.locale, Lang.localeForCode(languageRaw))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: lock.isLocked) { _, locked in
            // sheets would stay on top of the lock screen
            if locked {
                showingSettings = false
                showingHistory = false
            }
        }
        .onAppear {
            manager.refreshDriveInfo()
            manager.autoAnalyzeIfPossible()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background: manager.appDidEnterBackground()
            case .active: manager.appDidBecomeActive()
            default: break
            }
        }
        .task(id: scenePhase) {
            // While the app is visible, re-check the drive every few seconds,
            // so plugging it in (or removing it) is noticed without any tap.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await manager.pollDriveIfIdle()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .sensoryFeedback(trigger: manager.phase) { _, newPhase in
            feedback(for: newPhase)
        }
        .animation(.smooth, value: manager.plan)
        .animation(.smooth, value: manager.isRunning)
    }

    private func feedback(for phase: BackupManager.Phase) -> SensoryFeedback? {
        switch phase {
        case .finished: return .success
        case .failed: return .error
        default: return nil
        }
    }

    // MARK: Background & header

    private var background: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [theme.accent.opacity(0.35), theme.gradient[0].opacity(0.12), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(height: 460)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: theme.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                )
                .shadow(color: .indigo.opacity(0.4), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("USB Backup")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(tr("Kopia zdjęć i filmów na pendrive", "Back up photos and videos to a USB drive"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .disabled(manager.isCopying)
            .accessibilityLabel(tr("Ustawienia", "Settings"))
        }
        .padding(.top, 8)
    }

    // MARK: Drive card

    private var driveSubtitle: String {
        if let name = manager.drive?.volumeName { return tr("Dysk: \(name)", "Drive: \(name)") }
        return manager.destinationURL == nil
            ? tr("Podłącz pendrive lub dysk SSD i wybierz folder", "Plug in a USB drive or SSD and choose a folder")
            : tr("Brak połączenia z dyskiem", "Drive not connected")
    }

    private var driveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: manager.destinationURL == nil ? "externaldrive.badge.plus" : "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                        .frame(width: 46, height: 46)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(manager.folderName ?? tr("Nie wybrano folderu", "No folder selected"))
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                        Text(driveSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(manager.destinationURL == nil ? tr("Wybierz", "Choose") : tr("Zmień", "Change")) {
                        showingPicker = true
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(manager.isRunning)
                }

                if let drive = manager.drive, let total = drive.totalBytes, let available = drive.availableBytes, total > 0 {
                    let used = max(total - available, 0)
                    let folder = min(manager.folderBytes ?? 0, used)
                    let planned = manager.plan?.pendingBytes ?? 0

                    VStack(alignment: .leading, spacing: 10) {
                        CapacityBar(total: total, available: available, folder: folder, planned: planned)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)],
                                  alignment: .leading, spacing: 6) {
                            if manager.folderBytes != nil {
                                LegendDot(color: .indigo,
                                          text: tr("Folder kopii \(formatBytes(folder))",
                                                   "Backup folder \(formatBytes(folder))"))
                            } else if manager.isMeasuringFolder {
                                LegendDot(color: .indigo,
                                          text: tr("Folder kopii: liczę…", "Backup folder: counting…"))
                            }
                            LegendDot(color: .gray.opacity(0.55),
                                      text: tr("Inne pliki \(formatBytes(max(used - folder, 0)))",
                                               "Other files \(formatBytes(max(used - folder, 0)))"))
                            if planned > 0 {
                                LegendDot(color: planned > available ? .red : .cyan,
                                          text: tr("Nowa kopia \(formatBytes(planned))",
                                                   "New backup \(formatBytes(planned))"))
                            }
                            LegendDot(color: Color(.systemFill),
                                      text: tr("Wolne \(formatBytes(available))", "Free \(formatBytes(available))"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                } else if manager.destinationURL != nil {
                    Label(tr("Nie można odczytać dysku. Podłącz go i dotknij „Sprawdź, ile zostało”.",
                             "Can't read the drive. Plug it in and tap “Check what's left”."),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Stats

    private var statsGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                freeSpaceTile
                backupSizeTile
            }
            GridRow {
                lastBackupTile.gridCellColumns(2)
            }
        }
    }

    private var historyButton: some View {
        Button {
            showingHistory = true
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.title3)
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Historia kopii", "Backup history"))
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(historySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var historySubtitle: String {
        let count = manager.drive?.history.count ?? 0
        if manager.drive?.totalBytes == nil { return tr("Podłącz dysk, aby zobaczyć historię", "Plug in the drive to see the history") }
        if count == 0 { return tr("Brak zapisanych przebiegów", "No runs recorded yet") }
        return tr("Zapisanych przebiegów: \(count)", "Recorded runs: \(count)")
    }

    private var freeSpaceTile: some View {
        let available = manager.drive?.availableBytes
        let total = manager.drive?.totalBytes
        return StatTile(icon: "internaldrive",
                        title: tr("Wolne miejsce", "Free space"),
                        value: available.map { formatBytes($0) } ?? "—",
                        subtitle: total.map { tr("z \(formatBytes($0))", "of \(formatBytes($0))") },
                        tint: .green)
    }

    private var backupSizeTile: some View {
        var value = "—"
        var subtitle: String? = tr("Dotknij „Sprawdź, ile zostało”", "Tap “Check what's left”")
        var tint: Color = .blue

        if manager.isAnalyzing {
            value = tr("Liczę…", "Counting…")
            subtitle = tr("Analiza biblioteki", "Analyzing library")
        } else if let plan = manager.plan {
            if plan.pendingAssets == 0 {
                value = "0 B"
                subtitle = tr("Wszystko już skopiowane", "Everything is already backed up")
                tint = .green
            } else {
                value = (plan.unknownSizeFiles > 0 ? "~" : "") + formatBytes(plan.pendingBytes)
                subtitle = tr("\(plan.pendingAssets) nowych elementów", "\(plan.pendingAssets) new items")
                    + (plan.unknownSizeFiles > 0 ? tr(" (część rozmiarów nieznana)", " (some sizes unknown)") : "")
                if let free = manager.drive?.availableBytes, plan.pendingBytes > free { tint = .red }
            }
        }
        return StatTile(icon: "arrow.down.doc",
                        title: tr("Rozmiar kopii", "Backup size"),
                        value: value,
                        subtitle: subtitle,
                        tint: tint)
    }

    private var lastBackupTile: some View {
        var value = tr("Brak", "None")
        var subtitle: String? = tr("Na tym dysku nie wykonano jeszcze kopii", "No backup has been made on this drive yet")
        var tint: Color = .purple
        let drive = manager.drive

        if manager.isCopying {
            value = tr("W toku…", "In progress…")
            subtitle = tr("Kopia właśnie trwa", "A backup is running")
            tint = .blue
        } else if drive?.totalBytes == nil {
            value = "—"
            subtitle = tr("Podłącz dysk, aby zobaczyć datę", "Plug in the drive to see the date")
        } else if let run = drive?.lastRun, let status = drive?.lastRunStatus {
            let when = formatDate(run)
            value = relativeText(run)
            switch status {
            case .completed:
                subtitle = when
            case .completedWithErrors:
                let failed = drive?.lastRunFailed ?? 0
                subtitle = tr("Z błędami (\(failed)) · \(when)", "With errors (\(failed)) · \(when)")
                tint = .orange
            case .cancelled:
                subtitle = tr("Anulowana · \(when)", "Cancelled · \(when)")
                tint = .orange
            case .aborted:
                subtitle = tr("Przerwana · \(when)", "Interrupted · \(when)")
                tint = .orange
            case .inProgress:
                subtitle = tr("Przerwana nagle · \(when)", "Stopped unexpectedly · \(when)")
                tint = .orange
            }
            if status != .completed {
                if let done = drive?.lastCompleted {
                    subtitle = (subtitle ?? "") + "\n" + tr("Ostatnia pełna: \(relativeText(done))",
                                                            "Last complete: \(relativeText(done))")
                } else {
                    subtitle = (subtitle ?? "") + "\n" + tr("Nie było jeszcze pełnej kopii", "No complete backup yet")
                }
            }
        }
        return StatTile(icon: "clock.arrow.circlepath",
                        title: tr("Ostatnia kopia", "Last backup"),
                        value: value,
                        subtitle: subtitle,
                        tint: tint)
    }

    @ViewBuilder
    private var spaceWarning: some View {
        if let plan = manager.plan, let free = manager.drive?.availableBytes, plan.pendingBytes > free {
            messageCard(icon: "exclamationmark.triangle.fill",
                        tint: .red,
                        title: tr("Za mało miejsca na dysku", "Not enough space on the drive"),
                        text: tr("Potrzeba ok. \(formatBytes(plan.pendingBytes)), wolne jest \(formatBytes(free)). Zwolnij miejsce lub wybierz większy dysk.",
                                 "About \(formatBytes(plan.pendingBytes)) needed, \(formatBytes(free)) free. Free up space or use a larger drive."))
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusCard: some View {
        switch manager.phase {
        case .idle:
            EmptyView()
        case .scanning(let checked, let total):
            scanningCard(checked: checked, total: total)
        case .copying(let index, let total, let name):
            copyingCard(index: index, total: total, name: name)
        case .verifying(let checked, let total):
            verifyingCard(checked: checked, total: total)
        case .finished:
            VStack(spacing: 12) {
                messageCard(icon: "checkmark.circle.fill", tint: .green,
                            title: finishedTitle, text: nil)
                summaryCard
            }
        case .cancelled:
            VStack(spacing: 12) {
                messageCard(icon: "stop.circle.fill", tint: .orange,
                            title: tr("Kopia anulowana", "Backup cancelled"),
                            text: tr("Uruchom ją ponownie – wznowi od miejsca przerwania.",
                                     "Run it again – it will resume where it stopped."))
                summaryCard
            }
        case .failed(let message):
            VStack(spacing: 12) {
                messageCard(icon: "exclamationmark.triangle.fill", tint: .red,
                            title: tr("Coś poszło nie tak", "Something went wrong"), text: message)
                summaryCard
            }
        }
    }

    private var finishedTitle: String {
        guard let s = manager.summary else { return tr("Kopia zakończona", "Backup complete") }
        if s.skippedCellular > 0 && s.skippedCellular == s.failedAssets {
            return tr("Kopia niekompletna: część plików czeka w iCloud", "Backup incomplete: some files are waiting in iCloud")
        }
        if s.failedAssets > 0 { return tr("Kopia zakończona z błędami", "Backup finished with errors") }
        if s.copiedAssets == 0 { return tr("Wszystko już skopiowane", "Everything is already backed up") }
        return s.verifiedFiles > 0
            ? tr("Skopiowano i zweryfikowano", "Copied and verified")
            : tr("Kopia zakończona", "Backup complete")
    }

    private func verifyingCard(checked: Int, total: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(tr("Weryfikuję kopię…", "Verifying the backup…"))
                        .font(.system(.headline, design: .rounded))
                }
                ProgressView(value: Double(checked), total: Double(max(total, 1)))
                    .tint(.green)
                Text(tr("Sprawdzono \(checked) z \(total) plików (porównanie rozmiaru z oryginałem)",
                        "Checked \(checked) of \(total) files (size compared with the original)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scanningCard(checked: Int, total: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(manager.analyzeOnly
                         ? tr("Analizuję bibliotekę i dysk…", "Analyzing library and drive…")
                         : tr("Przygotowuję kopię…", "Preparing backup…"))
                        .font(.system(.headline, design: .rounded))
                }
                if total > 0 {
                    ProgressView(value: Double(checked), total: Double(max(total, 1)))
                        .tint(theme.accent)
                    Text(tr("Sprawdzono \(checked) z \(total)", "Checked \(checked) of \(total)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copyingCard(index: Int, total: Int, name: String) -> some View {
        Card {
            VStack(spacing: 16) {
                ProgressRing(progress: manager.overallProgress)
                    .frame(width: 190, height: 190)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    if manager.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text(tr("Wstrzymano (\(index) z \(total))", "Paused (\(index) of \(total))"))
                            .font(.system(.headline, design: .rounded))
                    } else {
                        ProgressView()
                        Text(manager.isPauseRequested
                             ? tr("Wstrzymuję po bieżącym pliku…", "Pausing after the current file…")
                             : tr("Kopiowanie \(index) z \(total)", "Copying \(index) of \(total)"))
                            .font(.system(.headline, design: .rounded))
                    }
                }

                ProgressView(value: manager.overallProgress)
                    .tint(theme.accent)

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    if let speed = manager.speedBytesPerSecond {
                        Label("\(formatBytes(Int64(speed)))/s", systemImage: "speedometer")
                    }
                    Spacer()
                    if let eta = manager.etaSeconds, !manager.isPaused {
                        Label(tr("Pozostało ok. \(durationText(eta)) (koniec ok. \(finishTime(eta)))",
                                 "About \(durationText(eta)) left (done around \(finishTime(eta)))"),
                              systemImage: "clock")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if let f = manager.iCloudProgress {
                    Label(tr("Pobieranie z iCloud… \(Int(f * 100))%", "Downloading from iCloud… \(Int(f * 100))%"),
                          systemImage: "icloud.and.arrow.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let s = manager.summary {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Podsumowanie", "Summary"))
                        .font(.system(.headline, design: .rounded))
                    summaryRow(tr("Skopiowano", "Copied"),
                               tr("\(s.copiedAssets) elementów · \(formatBytes(s.bytesCopied))",
                                  "\(s.copiedAssets) items · \(formatBytes(s.bytesCopied))"))
                    summaryRow(tr("Już na dysku", "Already on drive"), "\(s.alreadyBackedUp)")
                    if s.verifiedFiles > 0 || s.verifyFailed > 0 {
                        summaryRow(tr("Weryfikacja", "Verification"),
                                   s.verifyFailed == 0
                                   ? tr("✓ \(s.verifiedFiles) plików zgodnych", "✓ \(s.verifiedFiles) files match")
                                   : tr("\(s.verifyFailed) niezgodnych z \(s.verifiedFiles + s.verifyFailed)",
                                        "\(s.verifyFailed) of \(s.verifiedFiles + s.verifyFailed) don't match"),
                                   tint: s.verifyFailed == 0 ? .green : .red)
                    }
                    if let warning = s.markerWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if s.skippedCellular > 0 {
                        summaryRow(tr("Pominięte (iCloud, sieć komórkowa)", "Skipped (iCloud, cellular)"),
                                   "\(s.skippedCellular)", tint: .orange)
                    }
                    if s.failedAssets > 0 {
                        summaryRow(tr("Błędy", "Errors"), "\(s.failedAssets - s.skippedCellular)",
                                   tint: s.failedAssets > s.skippedCellular ? .red : .secondary)
                        DisclosureGroup(isExpanded: $showErrors) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(s.errors.prefix(errorListLimit).enumerated()), id: \.offset) { _, message in
                                    Text(message).font(.caption)
                                }
                                if s.errors.count > errorListLimit {
                                    Text(tr("…i kolejne (lista pokazuje pierwsze \(errorListLimit), pełna jest w logu)",
                                            "…and more (the list shows the first \(errorListLimit); the full list is in the log)"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text(tr("Szczegóły błędów", "Error details"))
                        }
                        .font(.subheadline)
                    }
                    if !s.failedAssetIDs.isEmpty {
                        Button {
                            manager.retryFailed()
                        } label: {
                            Label(tr("Spróbuj ponownie (\(s.failedAssetIDs.count))", "Try again (\(s.failedAssetIDs.count))"),
                                  systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(manager.isRunning)
                        .padding(.top, 4)
                    }
                    if let logURL = manager.logURL {
                        ShareLink(item: logURL,
                                  subject: Text("USB Backup – log"),
                                  message: Text(tr("Log ostatniej kopii (nazwy plików i komunikaty błędów, bez zdjęć i lokalizacji).",
                                                   "Log of the last backup (file names and error messages, no photos or location)."))) {
                            Label(tr("Udostępnij log", "Share log"), systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)

                        Button(role: .destructive) {
                            manager.clearLog()
                        } label: {
                            Label(tr("Usuń log", "Delete log"), systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(tint).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func messageCard(icon: String, tint: Color, title: String, text: String?) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    if let text {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Buttons

    private var pauseButtonTitle: String {
        if manager.isPaused { return tr("Wznów kopię", "Resume backup") }
        if manager.isPauseRequested { return tr("Cofnij wstrzymanie", "Cancel pause") }
        return tr("Wstrzymaj kopię", "Pause backup")
    }

    private func finishTime(_ secondsLeft: TimeInterval) -> String {
        Date().addingTimeInterval(secondsLeft)
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Lang.locale))
    }

    private var isVerifying: Bool {
        if case .verifying = manager.phase { return true }
        return false
    }

    /// The last analysis says the backup is bigger than the free space on the drive.
    private var notEnoughSpace: Bool {
        guard let plan = manager.plan, let free = manager.drive?.availableBytes else { return false }
        return plan.pendingBytes > free
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if manager.isCopying {
                Button {
                    manager.togglePause()
                } label: {
                    Label(pauseButtonTitle, systemImage: manager.isPauseRequested ? "play.fill" : "pause.fill")
                }
                .buttonStyle(PrimaryButtonStyle(colors: theme.gradient))
                .disabled(manager.isCancelling || isVerifying)

                Button(role: .destructive) {
                    manager.cancel()
                } label: {
                    Label(manager.isCancelling ? tr("Anulowanie…", "Cancelling…") : tr("Anuluj kopię", "Cancel backup"),
                          systemImage: "xmark")
                }
                .buttonStyle(PrimaryButtonStyle(colors: [.red, .orange]))
                .disabled(manager.isCancelling || isVerifying)
            } else if manager.isAnalyzing {
                Button {
                } label: {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(tr("Analizuję…", "Analyzing…"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(colors: theme.gradient))
                .disabled(true)

                Button(tr("Anuluj analizę", "Cancel analysis")) { manager.cancel() }
                    .font(.subheadline)
            } else {
                Button {
                    manager.start()
                } label: {
                    Label(notEnoughSpace ? tr("Rozpocznij kopię (za mało miejsca)", "Start backup (not enough space)")
                                         : tr("Rozpocznij kopię", "Start backup"),
                          systemImage: notEnoughSpace ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(colors: notEnoughSpace ? [.orange, .red] : theme.gradient))
                .disabled(manager.destinationURL == nil)

                Button {
                    manager.analyze()
                } label: {
                    Label(tr("Sprawdź, ile zostało", "Check what's left"), systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(manager.destinationURL == nil)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Components

private struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String?
    var tint: Color

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(title).foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))

                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

/// Other files | existing backup folder | new backup (planned) | free space, drawn as one capsule.
private struct CapacityBar: View {
    @Environment(\.appTheme) private var theme
    let total: Int64
    let available: Int64
    let folder: Int64
    let planned: Int64

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalValue = CGFloat(max(total, 1))
            let used = max(total - available, 0)
            let other = CGFloat(max(used - folder, 0))
            let folderValue = CGFloat(min(folder, used))
            let plannedClamped = CGFloat(min(planned, available))
            let overflow = planned > available

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.gray.opacity(0.55))
                    .frame(width: width * other / totalValue)
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: width * folderValue / totalValue)
                Rectangle()
                    .fill(overflow
                          ? AnyShapeStyle(Color.red)
                          : AnyShapeStyle(LinearGradient(colors: theme.barNew, startPoint: .leading, endPoint: .trailing)))
                    .frame(width: width * plannedClamped / totalValue)
                Spacer(minLength: 0)
            }
            .frame(height: 12)
            .background(Color(.systemFill))
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }
}

private struct ProgressRing: View {
    @Environment(\.appTheme) private var theme
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemFill), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(progress, 0.005))
                .stroke(
                    AngularGradient(colors: theme.ring, center: .center),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: progress))
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var colors: [Color] = [.blue, .indigo]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(colors: isEnabled ? colors : [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: (isEnabled ? colors[0] : Color.clear).opacity(0.35), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
