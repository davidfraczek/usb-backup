# USB Backup

Prywatna aplikacja na iPhone'a, która robi **przyrostową kopię zdjęć i filmów** z biblioteki Zdjęć prosto na **pendrive lub dysk SSD** podłączony do telefonu (USB-C / Lightning). Bez chmury, bez kont, bez serwerów.

*English summary: a private, free iOS app (SwiftUI) that incrementally backs up your Photos library to an external USB drive. Originals are copied unchanged (EXIF, GPS, RAW, ProRes), Live Photos as HEIC+MOV pairs, iCloud originals are downloaded when needed, and every copied file is verified. UI in Polish and English. Build with GitHub Actions, install from Windows with Sideloadly or from a Mac with Xcode.*

## Najważniejsze funkcje

- **Przyrostowa kopia:** kopiuje tylko to, czego jeszcze nie ma na dysku. Kolejne kopie są szybkie.
- **Oryginały bez zmian:** zapisywane są dokładnie te bajty, które ma iOS, więc zostają metadane, data, GPS, RAW i ProRes. Live Photo zapisuje się jako para HEIC/JPG + MOV, a edytowane wersje opcjonalnie jako `_edited`.
- **Porządek w folderach:** `2026-10/IMG_1234.HEIC` (albo `2026/10/`, `2026/10/14/` do wyboru w ustawieniach).
- **iCloud:** jeśli oryginał jest tylko w chmurze, aplikacja pobiera go w pełnej jakości przed zapisem. Pobieranie przez sieć komórkową jest domyślnie wyłączone.
- **Weryfikacja:** po zapisie rozmiar pliku na dysku jest porównywany z oryginałem, a na końcu kopii sprawdzane są wszystkie skopiowane pliki. Niezgodny plik jest usuwany i kopiowany od nowa przy następnej kopii.
- **Informacje o dysku:** wolne miejsce, rozmiar folderu z kopią, szacowany rozmiar nowej kopii, data ostatniej kopii.
- **Historia kopii:** ostatnie 30 przebiegów (data, ile skopiowano, błędy, czas, weryfikacja), zapisana na dysku.
- **Odporność na błędy:** „Spróbuj ponownie" dla nieudanych plików, ostrzeżenie i pytanie przy braku miejsca, czytelne komunikaty po odłączeniu dysku.
- **Zabezpieczenia i powiadomienia:** ostrzeżenie przy niskiej baterii, powiadomienie o końcu kopii lub błędzie, eksport logu błędów do pliku tekstowego.
- **Źródło:** cała biblioteka albo tylko zdjęcia i filmy z aparatu (przybliżone, patrz Ograniczenia).
- **Filtry:** zakres dat oraz wybór albumów (tylko wybrane albo pomiń wybrane).
- **Podział na foldery:** opcjonalnie zrzuty ekranu osobno albo Camera / Screenshots / Other.
- **albums.json:** zapis albumów, ulubionych i ukrytych zdjęć (ścieżki plików), by dało się je odtworzyć.
- **Pauza i wznowienie** kopii, czas do końca z godziną zakończenia, **przypomnienie** o kopii po 7/14/30 dniach.
- **Blokada aplikacji:** PIN 4-cyfrowy i Face ID / Touch ID.
- **Wygląd:** trzy motywy kolorystyczne (Klasyczny, Zachód słońca, Las).
- **Język:** polski i angielski (wybór w ustawieniach).

## Wymagania

- iPhone z **iOS 17** lub nowszym i dysk zewnętrzny (USB-C w iPhone 15 i nowszych albo Lightning z adapterem).
- Dysk sformatowany jako **exFAT** lub **APFS**. FAT32 nie pomieści plików powyżej 4 GB, a NTFS jest na iOS tylko do odczytu.
- Darmowe konto GitHub i darmowe Apple ID.
- Komputer: **Windows** (Sideloadly + iTunes) **albo Mac** (Xcode). Samej aplikacji nie da się zbudować na Windowsie, dlatego korzystamy z kompilacji w chmurze (GitHub Actions).

## Struktura repozytorium

```
.github/workflows/build.yml   kompilacja w GitHub Actions (tworzy plik .ipa)
project.yml                   opis projektu dla XcodeGen (generuje projekt Xcode)
Sources/
  USBPhotoBackupApp.swift     punkt startowy aplikacji
  ContentView.swift           główny ekran
  BackupManager.swift         logika kopii: skanowanie, kopiowanie, weryfikacja, historia
  AppSettings.swift           język i opcje kopii
  SettingsView.swift          ekran ustawień
  HistoryView.swift           historia kopii
  AlbumPickerView.swift       wybór albumów
  AppLock.swift               blokada PIN / Face ID
  Theme.swift                 motywy kolorystyczne
  Safety.swift                bateria, wykrywanie sieci komórkowej
  Notifier.swift              powiadomienia lokalne
  LogExport.swift             eksport logu
  Assets.xcassets/            ikona aplikacji
  en.lproj, pl.lproj/         tłumaczenia opisu uprawnienia i nazwy aplikacji
```

## Budowanie i instalacja

### 1. Kompilacja na GitHubie (bez Maca)

1. Wrzuć zawartość repozytorium na GitHub (folder `Sources`, `project.yml` i plik `.github/workflows/build.yml`).
2. Wejdź w **Actions › Build IPA › Run workflow**. Kompilacja trwa kilka minut.
3. Pobierz `USBPhotoBackup.ipa` z sekcji **Artifacts** ukończonego uruchomienia (plik jest w zipie).

Jeśli kompilacja się nie powiedzie, otwórz uruchomienie i sprawdź krok **Build** albo pobierz artefakt `build-log`.

### 2a. Instalacja z Windowsa (Sideloadly)

1. Zainstaluj **iTunes** ze strony apple.com (nie ze sklepu Microsoft Store) i **[Sideloadly](https://sideloadly.io)**.
2. Podłącz iPhone'a, zatwierdź „Ufaj temu komputerowi".
3. Przeciągnij `USBPhotoBackup.ipa` do Sideloadly, wpisz swoje Apple ID i kliknij **Start**.
4. Na iPhonie włącz **Tryb dewelopera** (Ustawienia › Prywatność i ochrona) i zaufaj profilowi (Ustawienia › Ogólne › VPN i zarządzanie urządzeniem).

### 2b. Instalacja z Maca (Xcode)

Zainstaluj [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), uruchom `xcodegen generate`, otwórz `USBPhotoBackup.xcodeproj`, wybierz swój zespół w **Signing & Capabilities** i uruchom na podłączonym iPhonie (⌘R).

> **Darmowe Apple ID podpisuje aplikację na 7 dni.** Po tym czasie zainstaluj ten sam `.ipa` ponownie (Sideloadly lub Xcode). Dane na dysku i ustawienia zostają. Automatyczne odnawianie umożliwia np. AltStore.

Jeśli Apple odrzuci identyfikator pakietu jako zajęty, zmień `pl.moja` w `project.yml` na własny prefiks.

## Użycie

1. Podłącz pendrive lub dysk.
2. Dotknij **Wybierz** i wskaż (lub utwórz) folder na dysku.
3. Dotknij **Rozpocznij kopię** i zezwól na **pełny dostęp** do Zdjęć.
4. Zostaw ekran włączony i aplikację na wierzchu do końca kopii. iOS zawiesza aplikację w tle, a wtedy kopia się zatrzymuje.
5. Przycisk **Sprawdź, ile zostało** liczy, ile jeszcze trzeba skopiować, niczego nie zapisując.

Przerwaną kopię uruchom ponownie. Wznowi się od miejsca przerwania.

## Jak to działa

- **Rozpoznawanie „już skopiowane":** plik o tej samej nazwie i zgodnej dacie utworzenia jest uznawany za skopiowany. Jeśli nazwa się zgadza, a data nie (np. `IMG_0001` z innego telefonu), nowy plik dostaje końcówkę `_1`, `_2` itd., więc nic nie jest nadpisywane.
- **Bezpieczny zapis:** plik powstaje jako `.partial` i dopiero po zapisie, zrzuceniu na dysk i sprawdzeniu rozmiaru dostaje docelową nazwę.
- **Znacznik na dysku:** ukryty plik `.usb-backup-info.json` w wybranym folderze przechowuje datę ostatniej kopii i historię. Można go bezpiecznie skasować, wtedy zniknie tylko historia.
- **Brak miejsca:** gdy analiza pokazuje, że kopia się nie zmieści, aplikacja pyta, czy kopiować mimo to (od najstarszych plików).
- **Sieć:** aplikacja nie łączy się z żadnym serwerem. Jedyny ruch to pobieranie oryginałów z iCloud przez system Zdjęć.

## Ograniczenia

- Kopia działa tylko, gdy aplikacja jest na ekranie.
- Weryfikacja porównuje **rozmiary**, a nie sumy kontrolne. Nie wykryje uszkodzenia, które zachowuje rozmiar.
- Rozmiar kopii jest szacunkiem (iOS oficjalnie nie podaje rozmiarów zdjęć). Wartość z „~" oznacza, że dla części plików rozmiaru nie ma.
- Kopiowane są zdjęcia i filmy z biblioteki (także ukryte). Albumy i ulubione nie są odwzorowywane w strukturze folderów (są zapisane w `albums.json`), Zdjęcia Współdzielone nie są kopiowane, a „Ostatnio usunięte" nie jest kopiowane.
- Dysk z zasilaniem z telefonu zużywa baterię. Przy wymagających SSD przydaje się hub z zasilaniem.
- Blokada sieci komórkowej dotyczy sieci uznanych przez iOS za „kosztowne" (komórkowa, Personal Hotspot).

- „Tylko z aparatu" opiera się na typie źródła, braku zrzutów ekranu i nazwie pliku `IMG_xxxx`, bo iOS nie podaje, czy zdjęcie zrobiono aparatem. Zdjęcia z AirDrop mogą się załapać.

## Rozwiązywanie problemów

| Objaw | Co zrobić |
|---|---|
| „Nie można uzyskać dostępu do wybranego folderu" | Podłącz dysk i wybierz folder ponownie. |
| Data ostatniej kopii się nie pokazuje | Poczekaj kilka sekund po podłączeniu dysku. Data jest zapisana osobno dla każdego folderu. |
| Pliki z iCloud są pomijane | Telefon jest w sieci komórkowej. Połącz się z Wi-Fi i dotknij „Spróbuj ponownie" albo włącz pobieranie przez sieć komórkową w ustawieniach. |
| Kopia zatrzymuje się po zablokowaniu telefonu | Tak działa iOS. Zostaw aplikację na wierzchu. |
| Aplikacja przestała się uruchamiać po tygodniu | Wygasł podpis darmowego Apple ID. Zainstaluj `.ipa` ponownie. |
| Coś poszło nie tak | Po kopii dotknij **Udostępnij log** i dołącz plik do zgłoszenia. Zawiera nazwy plików i komunikaty błędów, bez zdjęć i lokalizacji. |

## Status

Projekt jest rozwijany na własny użytek, a kod powstał z pomocą Claude. Nowsze funkcje (weryfikacja, pobieranie z iCloud z kontrolą sieci, powiadomienia) wymagają sprawdzenia na prawdziwym urządzeniu. **Przed poleganiem na kopii zrób próbę na małej partii** i sprawdź na komputerze, czy pliki się otwierają i mają poprawną datę oraz lokalizację.

## Licencja

Brak licencji. Projekt do użytku prywatnego.
