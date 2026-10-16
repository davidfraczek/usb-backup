import Foundation

// MARK: - Language (Polish / English, chosen in Settings)

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, polish, english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return tr("Systemowy", "System")
        case .polish: return "Polski"
        case .english: return "English"
        }
    }
}

enum Lang {
    nonisolated static let storageKey = "appLanguage"

    /// True when the UI should be in Polish (explicit choice, or system language is Polish).
    nonisolated static var isPolish: Bool {
        isPolishCode(UserDefaults.standard.string(forKey: storageKey))
    }

    nonisolated static func isPolishCode(_ raw: String?) -> Bool {
        switch AppLanguage(rawValue: raw ?? "") ?? .system {
        case .polish: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") ?? false
        }
    }

    nonisolated static var locale: Locale {
        localeForCode(UserDefaults.standard.string(forKey: storageKey))
    }

    nonisolated static func localeForCode(_ raw: String?) -> Locale {
        Locale(identifier: isPolishCode(raw) ? "pl_PL" : "en_US")
    }
}

/// Picks the Polish or the English text according to the language chosen in the app.
nonisolated func tr(_ pl: String, _ en: String) -> String {
    Lang.isPolish ? pl : en
}

// MARK: - Backup options (Settings)

enum MediaFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, photos, videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Wszystko", "Everything")
        case .photos: return tr("Zdjęcia", "Photos")
        case .videos: return tr("Filmy", "Videos")
        }
    }
}

/// Which part of the library is copied.
enum MediaSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Cała biblioteka", "Whole library")
        case .camera: return tr("Tylko z aparatu", "Camera only")
        }
    }
}

/// Only items from a time range.
enum DateRangeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, last30, last90, lastYear, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Wszystkie", "Everything")
        case .last30: return tr("Ostatnie 30 dni", "Last 30 days")
        case .last90: return tr("Ostatnie 90 dni", "Last 90 days")
        case .lastYear: return tr("Ostatni rok", "Last year")
        case .custom: return tr("Własny zakres", "Custom range")
        }
    }
}

/// Which albums are copied.
enum AlbumMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, only, exclude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Wszystkie", "All")
        case .only: return tr("Tylko wybrane", "Only selected")
        case .exclude: return tr("Pomiń wybrane", "Skip selected")
        }
    }
}

/// What kind of item a photo/video is, judged from what iOS tells us (see `assetKind`).
enum AssetKind: String, Sendable {
    case camera = "Camera"
    case screenshot = "Screenshots"
    case other = "Other"          // saved from the internet / messengers, AirDrop, synced from a computer …

    static let allFolderNames = [camera.rawValue, screenshot.rawValue, other.rawValue]
}

/// Optional sorting into sub-folders by kind. The folder names are fixed (not translated) so that
/// changing the app language never creates a second set of folders.
enum FolderSplit: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, screenshots, byKind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return tr("Wszystko razem", "All together")
        case .screenshots: return tr("Zrzuty ekranu osobno", "Screenshots separately")
        case .byKind: return tr("Aparat / zrzuty / inne", "Camera / screenshots / other")
        }
    }

    var detail: String {
        switch self {
        case .off: return "2026-10/IMG_1234.HEIC"
        case .screenshots: return "2026-10/IMG_1234.HEIC  ·  Screenshots/2026-10/IMG_5678.PNG"
        case .byKind: return "Camera/2026-10/…  ·  Screenshots/2026-10/…  ·  Other/2026-10/…"
        }
    }

    /// Top-level folder for an item of the given kind (nil = no extra folder).
    nonisolated func folder(for kind: AssetKind) -> String? {
        switch self {
        case .off: return nil
        case .screenshots: return kind == .screenshot ? AssetKind.screenshot.rawValue : nil
        case .byKind: return kind.rawValue
        }
    }
}

enum FolderLayout: String, CaseIterable, Identifiable, Codable, Sendable {
    case yearMonth, yearSlashMonth, yearMonthDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yearMonth: return tr("Rok-miesiąc", "Year-month")
        case .yearSlashMonth: return tr("Rok / miesiąc", "Year / month")
        case .yearMonthDay: return tr("Rok / miesiąc / dzień", "Year / month / day")
        }
    }

    /// Example for 14 October 2026.
    var example: String {
        switch self {
        case .yearMonth: return "2026-10"
        case .yearSlashMonth: return "2026/10"
        case .yearMonthDay: return "2026/10/14"
        }
    }

    /// Folder names (relative to the chosen folder) for a capture date.
    nonisolated func pathComponents(for date: Date?) -> [String] {
        guard let date else { return ["Unknown-Date"] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", c.year ?? 0)
        let month = String(format: "%02d", c.month ?? 0)
        let day = String(format: "%02d", c.day ?? 0)
        switch self {
        case .yearMonth: return ["\(year)-\(month)"]
        case .yearSlashMonth: return [year, month]
        case .yearMonthDay: return [year, month, day]
        }
    }
}

struct BackupOptions: Codable, Equatable, Sendable {
    var includeEdited = true
    var media: MediaFilter = .all
    var source: MediaSource = .all      // whole library, or only what was shot with the camera
    var layout: FolderLayout = .yearMonth
    var dateMode: DateRangeMode = .all
    var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var dateTo: Date = Date()
    var albumMode: AlbumMode = .all
    var albumIDs: [String] = []         // PHAssetCollection local identifiers
    var reminderDays = 14               // remind about a backup after this many days (0 = off)
    var saveAlbumInfo = true            // write albums.json (albums, favorites, hidden) next to the backup
    var split: FolderSplit = .off       // sort into Camera / Screenshots / Other sub-folders
    var allowCellular = false           // download iCloud originals over cellular / personal hotspot
    var notifyOnFinish = true           // local notification when a backup ends, fails or is paused by iOS
    var warnOnLowPower = true           // ask before starting on a low battery / in Low Power Mode

    init() {}

    // Settings saved by older versions don't contain the newer keys – missing keys keep their defaults,
    // so updating the app never resets what was already chosen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeEdited = try c.decodeIfPresent(Bool.self, forKey: .includeEdited) ?? true
        media = try c.decodeIfPresent(MediaFilter.self, forKey: .media) ?? .all
        source = try c.decodeIfPresent(MediaSource.self, forKey: .source) ?? .all
        layout = try c.decodeIfPresent(FolderLayout.self, forKey: .layout) ?? .yearMonth
        split = try c.decodeIfPresent(FolderSplit.self, forKey: .split) ?? .off
        dateMode = try c.decodeIfPresent(DateRangeMode.self, forKey: .dateMode) ?? .all
        dateFrom = try c.decodeIfPresent(Date.self, forKey: .dateFrom) ?? dateFrom
        dateTo = try c.decodeIfPresent(Date.self, forKey: .dateTo) ?? dateTo
        albumMode = try c.decodeIfPresent(AlbumMode.self, forKey: .albumMode) ?? .all
        albumIDs = try c.decodeIfPresent([String].self, forKey: .albumIDs) ?? []
        saveAlbumInfo = try c.decodeIfPresent(Bool.self, forKey: .saveAlbumInfo) ?? true
        reminderDays = try c.decodeIfPresent(Int.self, forKey: .reminderDays) ?? 14
        allowCellular = try c.decodeIfPresent(Bool.self, forKey: .allowCellular) ?? false
        notifyOnFinish = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFinish) ?? true
        warnOnLowPower = try c.decodeIfPresent(Bool.self, forKey: .warnOnLowPower) ?? true
    }

    /// Only these three change *what* is copied (and where), so only they make the old estimate invalid.
    func sameContent(as other: BackupOptions) -> Bool {
        includeEdited == other.includeEdited && media == other.media && source == other.source && layout == other.layout && split == other.split
            && dateMode == other.dateMode && albumMode == other.albumMode && albumIDs == other.albumIDs
            && (dateMode != .custom || (dateFrom == other.dateFrom && dateTo == other.dateTo))
    }

    /// Start and end of the chosen time range (nil = no limit on that side), relative to `now`.
    nonisolated func dateBounds(now: Date = Date()) -> (from: Date?, to: Date?) {
        let cal = Calendar.current
        switch dateMode {
        case .all: return (nil, nil)
        case .last30: return (cal.date(byAdding: .day, value: -30, to: now), nil)
        case .last90: return (cal.date(byAdding: .day, value: -90, to: now), nil)
        case .lastYear: return (cal.date(byAdding: .year, value: -1, to: now), nil)
        case .custom:
            let start = cal.startOfDay(for: min(dateFrom, dateTo))
            let endDay = cal.startOfDay(for: max(dateFrom, dateTo))
            let end = cal.date(byAdding: .day, value: 1, to: endDay).map { $0.addingTimeInterval(-1) }
            return (start, end)
        }
    }

    private static let storageKey = "backupOptions"

    static func load() -> BackupOptions {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(BackupOptions.self, from: data) else {
            return BackupOptions()
        }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
