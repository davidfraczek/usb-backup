import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: BackupManager
    @AppStorage(Lang.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsDenied = false
    @EnvironmentObject private var lock: AppLock
    @State private var pinPurpose: PinFlowView.Purpose?
    @AppStorage(ThemeStore.storageKey) private var themeRaw = AppTheme.classic.rawValue

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                themeSection
                contentSection
                dateSection
                albumSection
                albumInfoSection
                layoutSection
                splitSection
                safetySection
                lockSection
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
            .sheet(item: $pinPurpose) { purpose in
                PinFlowView(purpose: purpose, lock: lock)
                    .presentationDetents([.large])
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
            Picker(selection: $manager.options.reminderDays) {
                Text(tr("Wyłączone", "Off")).tag(0)
                Text(tr("Po 7 dniach", "After 7 days")).tag(7)
                Text(tr("Po 14 dniach", "After 14 days")).tag(14)
                Text(tr("Po 30 dniach", "After 30 days")).tag(30)
            } label: {
                Label(tr("Przypomnij o kopii", "Remind me to back up"), systemImage: "alarm")
            }
        } header: {
            Text(tr("Zabezpieczenia i powiadomienia", "Safety and notifications"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Gdy pobieranie przez sieć komórkową jest wyłączone (zalecane), zdjęcia i filmy, które są tylko w iCloud, są pomijane, dopóki telefon nie połączy się z Wi-Fi. Potem dotknij „Spróbuj ponownie”. Dotyczy też Personal Hotspot.",
                        "While downloading over cellular is off (recommended), photos and videos that exist only in iCloud are skipped until the phone is on Wi-Fi. Then tap “Try again”. This also applies to Personal Hotspot."))
                Text(tr("Ostrzeżenie pojawia się, gdy bateria ma poniżej 20% i telefon się nie ładuje albo włączony jest tryb niskiego zużycia energii.",
                        "The warning appears when the battery is below 20% and not charging, or Low Power Mode is on."))
                Text(tr("Przypomnienie przychodzi o 18:00, gdy od ostatniej w pełni udanej kopii minie wybrana liczba dni. Jeśli już minęło, przypomni za 3 dni (bez codziennego męczenia). Wymaga zgody na powiadomienia.",
                        "The reminder arrives at 6 pm once the chosen number of days has passed since the last fully successful backup. If that is already the case, it comes in 3 days (no daily nagging). Needs permission for notifications."))
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

    // MARK: App lock

    private var lockSection: some View {
        Section {
            if lock.isEnabled {
                if lock.biometryAvailable {
                    Toggle(isOn: $lock.useBiometrics) {
                        Label(tr("Odblokowuj przez \(lock.biometryName)", "Unlock with \(lock.biometryName)"),
                              systemImage: lock.biometryIcon)
                    }
                }
                Button {
                    pinPurpose = .change
                } label: {
                    Label(tr("Zmień PIN", "Change PIN"), systemImage: "key")
                }
                Button(role: .destructive) {
                    pinPurpose = .disable
                } label: {
                    Label(tr("Wyłącz blokadę", "Turn off the lock"), systemImage: "lock.open")
                }
            } else {
                Button {
                    pinPurpose = .enable
                } label: {
                    Label(tr("Włącz blokadę (PIN)", "Turn on the lock (PIN)"), systemImage: "lock")
                }
            }
        } header: {
            Text(tr("Blokada aplikacji", "App lock"))
        } footer: {
            Text(tr("Aplikacja blokuje się po każdym wyjściu z niej i prosi o 4-cyfrowy PIN albo Face ID. Po 5 błędach z rzędu następuje przerwa. Jeśli zapomnisz PIN-u: usuń aplikację i zainstaluj ją ponownie (stracisz tylko ustawienia, zdjęcia i kopia na dysku zostają). Trwająca kopia nie jest przerywana przez blokadę.",
                    "The app locks every time you leave it and asks for a 4-digit PIN or Face ID. After 5 wrong tries in a row there is a short pause. If you forget the PIN: delete the app and install it again (you lose only the settings; your photos and the backup on the drive stay). A running backup is not interrupted by the lock."))
        }
    }

    // MARK: Date range

    private var dateSection: some View {
        Section {
            Picker(selection: $manager.options.dateMode) {
                ForEach(DateRangeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label(tr("Zakres dat", "Date range"), systemImage: "calendar")
            }
            if manager.options.dateMode == .custom {
                DatePicker(tr("Od", "From"), selection: $manager.options.dateFrom, in: ...Date(), displayedComponents: .date)
                DatePicker(tr("Do", "To"), selection: $manager.options.dateTo, in: ...Date(), displayedComponents: .date)
            }
        } header: {
            Text(tr("Zakres dat", "Date range"))
        } footer: {
            Text(tr("Liczy się data wykonania zdjęcia. „Ostatnie 30 dni” liczone jest od dnia uruchomienia kopii. Zdjęcia spoza zakresu, które już są na dysku, zostają.",
                    "The date the photo was taken counts. “Last 30 days” is counted from the day the backup runs. Photos outside the range that are already on the drive stay."))
        }
    }

    // MARK: Albums

    private var albumSection: some View {
        Section {
            Picker(selection: $manager.options.albumMode) {
                ForEach(AlbumMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label(tr("Albumy", "Albums"), systemImage: "rectangle.stack")
            }
            if manager.options.albumMode != .all {
                NavigationLink {
                    AlbumPickerView(manager: manager)
                } label: {
                    HStack {
                        Text(tr("Wybierz albumy", "Choose albums"))
                        Spacer()
                        Text("\(manager.options.albumIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(tr("Albumy", "Albums"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("„Pomiń wybrane” przydaje się np. do albumu „Zrzuty ekranu”. Zdjęcie może być w kilku albumach: przy „Tylko wybrane” wystarczy, że jest w jednym z nich, a przy „Pomiń wybrane” jest pomijane, jeśli jest w którymkolwiek.",
                        "“Skip selected” is handy for e.g. the “Screenshots” album. A photo can be in several albums: with “Only selected” it is copied if it is in any of them, with “Skip selected” it is skipped if it is in any of them."))
                if manager.options.albumMode == .only && manager.options.albumIDs.isEmpty {
                    Text(tr("Nie wybrano żadnego albumu, więc nic nie zostanie skopiowane.",
                            "No album is selected, so nothing will be copied."))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: albums.json

    private var albumInfoSection: some View {
        Section {
            Toggle(isOn: $manager.options.saveAlbumInfo) {
                Label(tr("Zapisuj albumy i ulubione", "Save albums and favorites"), systemImage: "heart.text.square")
            }
        } header: {
            Text(tr("Albumy i ulubione", "Albums and favorites"))
        } footer: {
            Text(tr("Po każdej kopii w folderze kopii powstaje plik albums.json: dla każdego albumu, ulubionych i ukrytych zdjęć zapisuje ścieżki plików na dysku. Dzięki temu można później odtworzyć albumy i serduszka, bo same pliki ich nie niosą. Plik odzwierciedla bieżące filtry (zakres dat, albumy, źródło), więc pełny obraz daje kopia bez filtrów. Nie jest tworzony przy „Spróbuj ponownie”.",
                    "After each backup an albums.json file is written in the backup folder: for every album, favorite and hidden photo it lists the file paths on the drive, so albums and hearts can be rebuilt later (the files themselves don't carry them). The file reflects the current filters (date range, albums, source), so a backup without filters gives the full picture. It is not written on “Try again” runs."))
        }
    }

    // MARK: Sorting into sub-folders

    private var splitSection: some View {
        Section {
            Picker(selection: $manager.options.split) {
                ForEach(FolderSplit.allCases) { split in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(split.title)
                        Text(split.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(split)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(tr("Podział na foldery", "Sorting into folders"))
        } footer: {
            Text(tr("Rozpoznawanie jest przybliżone: „Screenshots” to zrzuty i nagrania ekranu, „Camera” to pliki o nazwach IMG_1234 z Twojej biblioteki, „Other” to reszta (zdjęcia z internetu, komunikatorów, AirDrop). Już skopiowane pliki zostają tam, gdzie są, i nie są kopiowane drugi raz. Nic nie jest przenoszone ani kasowane, więc zrzuty skopiowane wcześniej do folderu z aparatem możesz usunąć ręcznie.",
                    "Detection is approximate: “Screenshots” are screenshots and screen recordings, “Camera” are IMG_1234-style files from your own library, “Other” is the rest (web, messengers, AirDrop). Files that are already copied stay where they are and are not copied again. Nothing is moved or deleted, so screenshots copied earlier into the camera folder can be removed by hand."))
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
