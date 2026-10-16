import SwiftUI

/// Colour themes, chosen in Settings. The classic theme is the original blue/indigo look.
enum AppTheme: String, CaseIterable, Identifiable {
    case classic, sunset, forest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return tr("Klasyczny", "Classic")
        case .sunset: return tr("Zachód słońca", "Sunset")
        case .forest: return tr("Las", "Forest")
        }
    }

    /// Main accent (tints, icons, progress bars).
    var accent: Color {
        switch self {
        case .classic: return .indigo
        case .sunset: return .pink
        case .forest: return .green
        }
    }

    /// Buttons and the header icon.
    var gradient: [Color] {
        switch self {
        case .classic: return [.blue, .indigo]
        case .sunset: return [.pink, .purple]
        case .forest: return [.green, .teal]
        }
    }

    /// The "new backup" segment of the capacity bar.
    var barNew: [Color] {
        switch self {
        case .classic: return [.cyan, .blue]
        case .sunset: return [.yellow, .orange]
        case .forest: return [.mint, .teal]
        }
    }

    /// The circular progress ring.
    var ring: [Color] {
        switch self {
        case .classic: return [.blue, .indigo, .purple, .blue]
        case .sunset: return [.orange, .pink, .purple, .orange]
        case .forest: return [.mint, .green, .teal, .mint]
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .classic
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

enum ThemeStore {
    static let storageKey = "appTheme"
}

/// Wraps the main screen so that every view (and sheet) sees the chosen theme.
struct RootView: View {
    @AppStorage(ThemeStore.storageKey) private var themeRaw = AppTheme.classic.rawValue

    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let theme = AppTheme(rawValue: themeRaw) ?? .classic
        let locked = lock.isEnabled && lock.isLocked
        ZStack {
            ContentView()
                .environmentObject(lock)
                .accessibilityHidden(locked)
            if locked {
                LockScreenView(lock: lock)
                    .zIndex(1)
            } else if lock.isEnabled && scenePhase != .active {
                // hides the content in the app switcher
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay(Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary))
                    .zIndex(1)
            }
        }
        .environment(\.appTheme, theme)
        .tint(theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lockIfEnabled() }
        }
    }
}
