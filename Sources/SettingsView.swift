import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager: BackupManager
    @AppStorage(Lang.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                contentSection
                layoutSection
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

            Toggle(isOn: $manager.options.includeEdited) {
                Label(tr("Zapisuj edytowane wersje", "Save edited versions"), systemImage: "slider.horizontal.3")
            }
        } header: {
            Text(tr("Zawartość kopii", "Backup content"))
        } footer: {
            Text(tr("Edytowana wersja zapisuje się obok oryginału z końcówką _edited. Live Photo zawsze zapisuje się razem z filmem. Zmiana dotyczy kolejnych kopii, to, co już jest na dysku, zostaje.",
                    "An edited version is saved next to the original with an _edited suffix. Live Photos are always saved together with their video. Changes apply to future backups; what is already on the drive stays."))
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
