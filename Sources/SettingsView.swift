import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: BackupManager
    @AppStorage(Lang.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsDenied = false
    @AppStorage(ThemeStore.storageKey) private var themeRaw = AppTheme.classic.rawValue

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                themeSection
                contentSection
                layoutSection
                safetySection
            }
            .task { notificationsDenied = await Notifier.isDenied() }
            .onChange(of: manager.options.notifyOnFinish) { _, enabled in
                if enabled {
                    Task {
                        await Notifier.requestAuthorizationIfNeeded()
                        notificationsDenied = await Notifier.isDenied()
                    }
                }
            }
            .navigationTitle(tr("Ustawienia", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Gotowe", "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .environment(\.locale, Lang.localeForCode(languageRaw))
    }

    // MARK: Safety (battery, mobile data, notifications)

    private var safetySection: some View {
        Section {
            Toggle(isOn: $manager.options.allowCellular) {
                Label(tr("Pobieraj z iCloud przez sieć komórkową", "Download from iCloud over cellular"),
                      systemImage: "antenna.radiowaves.left.and.right")
            }
            Toggle(isOn: $manager.options.warnOnLowPower) {
                Label(tr("Ostrzegaj przy niskiej baterii", "Warn on low battery"), systemImage: "battery.25")
            }
            Toggle(isOn: $manager.options.notifyOnFinish) {
                Label(tr("Powiadomienia o zakończeniu i błędach", "Notify when finished or on errors"),
                      systemImage: "bell.badge")
            }
        } header: {
            Text(tr("Zabezpieczenia i powiadomienia", "Safety and notifications"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Gdy pobieranie przez sieć komórkową jest wyłączone (zalecane), zdjęcia i filmy, które są tylko w iCloud, są pomijane, dopóki telefon nie połączy się z Wi-Fi. Potem dotknij „Spróbuj ponownie”. Dotyczy też Personal Hotspot.",
                        "While downloading over cellular is off (recommended), photos and videos that exist only in iCloud are skipped until the phone is on Wi-Fi. Then tap “Try again”. This also applies to Personal Hotspot."))
                Text(tr("Ostrzeżenie pojawia się, gdy bateria ma poniżej 20% i telefon się nie ładuje albo włączony jest tryb niskiego zużycia energii.",
                        "The warning appears when the battery is below 20% and not charging, or Low Power Mode is on."))
                Text(tr("Powiadomienie pojawi się też, gdy aplikacja przejdzie w tło podczas kopiowania (iOS wstrzymuje wtedy kopię).",
                        "You'll also get a notification if the app goes to the background while copying (iOS then suspends the backup)."))
                if notificationsDenied && manager.options.notifyOnFinish {
                    Text(tr("Powiadomienia są wyłączone dla tej aplikacji w Ustawieniach iOS.",
                            "Notifications are turned off for this app in iOS Settings."))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Picker(selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language.rawValue)
                }
            } label: {
                Label(tr("Język aplikacji", "App language"), systemImage: "globe")
            }
        } header: {
            Text(tr("Język", "Language"))
        } footer: {
            Text(tr("Zmiana języka działa od razu.", "The language changes immediately."))
        }
    }

    // MARK: Content

    private var contentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Co kopiować", "What to back up"))
                Picker(selection: $manager.options.media) {
                    ForEach(MediaFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Skąd kopiować", "Where from"))
                Picker(selection: $manager.options.source) {
                    ForEach(MediaSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 2)

            Toggle(isOn: $manager.options.includeEdited) {
                Label(tr("Zapisuj edytowane wersje", "Save edited versions"), systemImage: "slider.horizontal.3")
            }
        } header: {
            Text(tr("Zawartość kopii", "Backup content"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
            Text(tr("Edytowana wersja zapisuje się obok oryginału z końcówką _edited. Live Photo zawsze zapisuje się razem z filmem. Zmiana dotyczy kolejnych kopii, to, co już jest na dysku, zostaje.",
                    "An edited version is saved next to the original with an _edited suffix. Live Photos are always saved together with their video. Changes apply to future backups; what is already on the drive stays."))
            if manager.options.source == .camera {
                Text(tr("„Tylko z aparatu” to przybliżenie, bo iOS nie oznacza, co zrobiono aparatem. Pomijane są zrzuty ekranu, nagrania ekranu, elementy zsynchronizowane z komputerem i pliki bez nazwy typu IMG_1234. Zdjęcia odebrane przez AirDrop mogą się załapać.",
                        "“Camera only” is an approximation because iOS does not flag what was shot with the camera. Screenshots, screen recordings, items synced from a computer and files without a camera-style name (IMG_1234) are skipped. Photos received via AirDrop may still be included."))
            }
            }
        }
    }

    // MARK: Theme

    private var themeSection: some View {
        Section {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    themeRaw = theme.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(LinearGradient(colors: theme.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Text(theme.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if themeRaw == theme.rawValue {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        } header: {
            Text(tr("Motyw kolorystyczny", "Colour theme"))
        }
    }

    // MARK: Folder layout

    private var layoutSection: some View {
        Section {
            Picker(selection: $manager.options.layout) {
                ForEach(FolderLayout.allCases) { layout in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layout.title)
                        Text(layout.example)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(layout)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(tr("Układ folderów", "Folder layout"))
        } footer: {
            Text(tr("Przykład: \(manager.folderName ?? "Backup")/\(manager.options.layout.example)/IMG_1234.HEIC. Zmiana układu nie przenosi i nie kopiuje ponownie plików, które już są na dysku w innym układzie.",
                    "Example: \(manager.folderName ?? "Backup")/\(manager.options.layout.example)/IMG_1234.HEIC. Changing the layout does not move or re-copy files that are already on the drive in another layout."))
        }
    }
}
