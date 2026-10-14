import SwiftUI
import UniformTypeIdentifiers

// MARK: - Helpers

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func relativeText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func durationText(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: max(seconds, 1)) ?? "—"
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var manager = BackupManager()
    @State private var showingPicker = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    driveCard
                    if manager.destinationURL != nil {
                        statsGrid
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
        .onAppear {
            manager.refreshDriveInfo()
            manager.autoAnalyzeIfPossible()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, !manager.isRunning { manager.refreshDriveInfo() }
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
            LinearGradient(colors: [Color.indigo.opacity(0.35), Color.blue.opacity(0.12), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(height: 460)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                Text("Kopia zdjęć i filmów na pendrive")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: Drive card

    private var driveSubtitle: String {
        if let name = manager.drive?.volumeName { return "Dysk: \(name)" }
        return manager.destinationURL == nil
            ? "Podłącz pendrive lub dysk SSD i wybierz folder"
            : "Brak połączenia z dyskiem"
    }

    private var driveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: manager.destinationURL == nil ? "externaldrive.badge.plus" : "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 46, height: 46)
                        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(manager.folderName ?? "Nie wybrano folderu")
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                        Text(driveSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(manager.destinationURL == nil ? "Wybierz" : "Zmień") {
                        showingPicker = true
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(manager.isRunning)
                }

                if let drive = manager.drive, let total = drive.totalBytes, let available = drive.availableBytes, total > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        CapacityBar(total: total, available: available, planned: manager.plan?.pendingBytes ?? 0)
                        HStack(spacing: 14) {
                            LegendDot(color: .gray.opacity(0.55), text: "Zajęte \(formatBytes(max(total - available, 0)))")
                            if let planned = manager.plan?.pendingBytes, planned > 0 {
                                LegendDot(color: planned > available ? .red : .indigo, text: "Kopia \(formatBytes(planned))")
                            }
                            LegendDot(color: Color(.systemFill), text: "Wolne \(formatBytes(available))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                } else if manager.destinationURL != nil {
                    Label("Nie można odczytać dysku. Podłącz go i dotknij „Sprawdź, ile zostało”.",
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

    private var freeSpaceTile: some View {
        let available = manager.drive?.availableBytes
        let total = manager.drive?.totalBytes
        return StatTile(icon: "internaldrive",
                        title: "Wolne miejsce",
                        value: available.map { formatBytes($0) } ?? "—",
                        subtitle: total.map { "z \(formatBytes($0))" },
                        tint: .green)
    }

    private var backupSizeTile: some View {
        var value = "—"
        var subtitle: String? = "Dotknij „Sprawdź, ile zostało”"
        var tint: Color = .blue

        if manager.isAnalyzing {
            value = "Liczę…"
            subtitle = "Analiza biblioteki"
        } else if let plan = manager.plan {
            if plan.pendingAssets == 0 {
                value = "0 B"
                subtitle = "Wszystko już skopiowane"
                tint = .green
            } else {
                value = (plan.unknownSizeFiles > 0 ? "~" : "") + formatBytes(plan.pendingBytes)
                subtitle = "\(plan.pendingAssets) nowych elementów" + (plan.unknownSizeFiles > 0 ? " (część rozmiarów nieznana)" : "")
                if let free = manager.drive?.availableBytes, plan.pendingBytes > free { tint = .red }
            }
        }
        return StatTile(icon: "arrow.down.doc", title: "Rozmiar kopii", value: value, subtitle: subtitle, tint: tint)
    }

    private var lastBackupTile: some View {
        let date = manager.drive?.lastBackup
        return StatTile(icon: "clock.arrow.circlepath",
                        title: "Ostatnia kopia",
                        value: date.map { relativeText($0) } ?? "Brak",
                        subtitle: date.map { $0.formatted(date: .abbreviated, time: .shortened) }
                            ?? "Na tym dysku nie wykonano jeszcze kopii",
                        tint: .purple)
    }

    @ViewBuilder
    private var spaceWarning: some View {
        if let plan = manager.plan, let free = manager.drive?.availableBytes, plan.pendingBytes > free {
            messageCard(icon: "exclamationmark.triangle.fill",
                        tint: .red,
                        title: "Za mało miejsca na dysku",
                        text: "Potrzeba ok. \(formatBytes(plan.pendingBytes)), wolne jest \(formatBytes(free)). Zwolnij miejsce lub wybierz większy dysk.")
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
        case .finished:
            VStack(spacing: 12) {
                messageCard(icon: "checkmark.circle.fill", tint: .green,
                            title: finishedTitle, text: nil)
                summaryCard
            }
        case .cancelled:
            VStack(spacing: 12) {
                messageCard(icon: "stop.circle.fill", tint: .orange,
                            title: "Kopia anulowana",
                            text: "Uruchom ją ponownie – wznowi od miejsca przerwania.")
                summaryCard
            }
        case .failed(let message):
            VStack(spacing: 12) {
                messageCard(icon: "exclamationmark.triangle.fill", tint: .red,
                            title: "Coś poszło nie tak", text: message)
                summaryCard
            }
        }
    }

    private var finishedTitle: String {
        guard let s = manager.summary else { return "Kopia zakończona" }
        if s.failedAssets > 0 { return "Kopia zakończona z błędami" }
        return s.copiedAssets == 0 ? "Wszystko już skopiowane" : "Kopia zakończona"
    }

    private func scanningCard(checked: Int, total: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(manager.analyzeOnly ? "Analizuję bibliotekę i dysk…" : "Przygotowuję kopię…")
                        .font(.system(.headline, design: .rounded))
                }
                if total > 0 {
                    ProgressView(value: Double(checked), total: Double(max(total, 1)))
                        .tint(.indigo)
                    Text("Sprawdzono \(checked) z \(total)")
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
                    ProgressView()
                    Text("Kopiowanie \(index) z \(total)")
                        .font(.system(.headline, design: .rounded))
                }

                ProgressView(value: manager.overallProgress)
                    .tint(.indigo)

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    if let speed = manager.speedBytesPerSecond {
                        Label("\(formatBytes(Int64(speed)))/s", systemImage: "speedometer")
                    }
                    Spacer()
                    if let eta = manager.etaSeconds {
                        Label("Pozostało ok. \(durationText(eta))", systemImage: "clock")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if let f = manager.iCloudProgress {
                    Label("Pobieranie z iCloud… \(Int(f * 100))%", systemImage: "icloud.and.arrow.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let s = manager.summary {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Podsumowanie")
                        .font(.system(.headline, design: .rounded))
                    summaryRow("Skopiowano", "\(s.copiedAssets) elementów · \(formatBytes(s.bytesCopied))")
                    summaryRow("Już na dysku", "\(s.alreadyBackedUp)")
                    if s.failedAssets > 0 {
                        summaryRow("Błędy", "\(s.failedAssets)", tint: .red)
                        DisclosureGroup("Pokaż szczegóły błędów") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(s.errors, id: \.self) { Text($0).font(.caption) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline)
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

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if manager.isCopying {
                Button(role: .destructive) {
                    manager.cancel()
                } label: {
                    Label(manager.isCancelling ? "Anulowanie…" : "Anuluj kopię", systemImage: "xmark")
                }
                .buttonStyle(PrimaryButtonStyle(colors: [.red, .orange]))
                .disabled(manager.isCancelling)
            } else if manager.isAnalyzing {
                Button {
                } label: {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Analizuję…")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)

                Button("Anuluj analizę") { manager.cancel() }
                    .font(.subheadline)
            } else {
                Button {
                    manager.start()
                } label: {
                    Label("Rozpocznij kopię", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(manager.destinationURL == nil)

                Button {
                    manager.analyze()
                } label: {
                    Label("Sprawdź, ile zostało", systemImage: "magnifyingglass")
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
                        .lineLimit(2)
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

/// Used space | planned backup | free space, drawn as one capsule.
private struct CapacityBar: View {
    let total: Int64
    let available: Int64
    let planned: Int64

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalValue = CGFloat(max(total, 1))
            let used = CGFloat(max(total - available, 0))
            let plannedClamped = CGFloat(min(planned, available))
            let overflow = planned > available

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.gray.opacity(0.55))
                    .frame(width: width * used / totalValue)
                Rectangle()
                    .fill(overflow
                          ? AnyShapeStyle(Color.red)
                          : AnyShapeStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)))
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
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemFill), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(progress, 0.005))
                .stroke(
                    AngularGradient(colors: [.blue, .indigo, .purple, .blue], center: .center),
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
