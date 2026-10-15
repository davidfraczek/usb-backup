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
        allowCellular = try c.decodeIfPresent(Bool.self, forKey: .allowCellular) ?? false
        notifyOnFinish = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFinish) ?? true
        warnOnLowPower = try c.decodeIfPresent(Bool.self, forKey: .warnOnLowPower) ?? true
    }

    /// Only these three change *what* is copied (and where), so only they make the old estimate invalid.
    func sameContent(as other: BackupOptions) -> Bool {
        includeEdited == other.includeEdited && media == other.media && source == other.source && layout == other.layout
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
