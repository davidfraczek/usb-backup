# USB Backup – instalacja z Windowsa (bez Maca)

Idea: GitHub zbuduje aplikację na darmowym Macu w chmurze, a Ty zainstalujesz plik `.ipa` na iPhonie programem Sideloadly.

## Część 1 – kompilacja na GitHubie

1. Załóż darmowe konto na https://github.com.
2. Kliknij **+** (prawy górny róg) › **New repository**. Nazwa: `usb-backup`. Wybierz **Private** (lub Public, jeśli nie przeszkadza Ci, że kod jest widoczny). Zaznacz **Add a README file**. Kliknij **Create repository**.
3. Rozpakuj ten zip na Windowsie. W repozytorium kliknij **Add file › Upload files** i przeciągnij tam:
   - folder `Sources` (z trzema plikami `.swift`),
   - plik `project.yml`.
   
   Kliknij **Commit changes**.
4. Dodaj plik workflow ręcznie (przeciąganie ukrytego folderu `.github` często zawodzi):
   - **Add file › Create new file**,
   - w polu nazwy wpisz dokładnie: `.github/workflows/build.yml` (ukośniki same utworzą foldery),
   - otwórz z rozpakowanego zipa plik `.github/workflows/build.yml` w Notatniku, skopiuj całą zawartość i wklej do GitHuba,
   - **Commit changes**.
5. Wejdź w zakładkę **Actions**. Jeśli GitHub poprosi o włączenie, zatwierdź. Wybierz workflow **Build IPA** › **Run workflow** (zielony przycisk).
6. Poczekaj kilka minut aż obok uruchomienia pojawi się zielony ptaszek. Kliknij uruchomienie i na dole, w sekcji **Artifacts**, pobierz **USBPhotoBackup-ipa**. Rozpakuj zip, w środku jest `USBPhotoBackup.ipa`.

Jeśli kompilacja zakończy się czerwonym krzyżykiem, pobierz artefakt **build-log** (albo skopiuj końcówkę logu) i wklej mi go. Poprawię kod.

## Część 2 – instalacja na iPhonie

1. Zainstaluj **iTunes** ze strony Apple (nie ze sklepu Microsoft Store). Sideloadly wymaga wersji ze strony apple.com, szczegóły podaje instrukcja na https://sideloadly.io.
2. Zainstaluj **Sideloadly** (https://sideloadly.io).
3. Podłącz iPhone'a kablem do komputera i zatwierdź na telefonie **Ufaj temu komputerowi**.
4. W Sideloadly przeciągnij plik `USBPhotoBackup.ipa`, wpisz swoje Apple ID i kliknij **Start**. Zalogujesz się hasłem Apple ID i kodem dwuskładnikowym. Jeśli wolisz, użyj osobnego, darmowego Apple ID tylko do tego.
5. Na iPhonie włącz **Tryb dewelopera**: Ustawienia › Prywatność i ochrona › Tryb dewelopera (pojawia się po pierwszej próbie instalacji, wymaga restartu).
6. Zaufaj profilowi: Ustawienia › Ogólne › VPN i zarządzanie urządzeniem › Twoje Apple ID › **Zaufaj**.
7. Uruchom aplikację **USB Backup**.

## Część 3 – użycie

1. Podłącz dysk (sformatowany jako **exFAT** lub **APFS**, formatować można na Windowsie, exFAT).
2. **Select USB Folder** › wybierz folder na dysku.
3. **Start Backup** › zezwól na **pełny dostęp** do zdjęć.
4. Zostaw ekran włączony i aplikację na wierzchu aż do końca.

## Co tydzień

Darmowe Apple ID podpisuje aplikację tylko na **7 dni**. Wtedy ponownie zainstaluj ten sam `.ipa` w Sideloadly (nie trzeba budować od nowa). Kopia na dysku i ustawienia zostają. Kolejne kopie są przyrostowe.

## Uwagi

- Kod nie był kompilowany przeze mnie. Pierwsza kompilacja może wymagać drobnych poprawek.
- Zmiana nazwy pakietu: w `project.yml` zmień `pl.moja` na coś własnego, jeśli Apple odrzuci identyfikator jako zajęty.
- Na darmowym koncie GitHub kompilacje na Macu w prywatnych repozytoriach mają miesięczny limit minut. Do tego zastosowania powinno w zupełności wystarczyć.
