# PILNE: poprawka „chce kopiować wszystko od nowa" po zmianie czasu

**Przyczyna (najbardziej prawdopodobna):** zmiana czasu z letniego na zimowy (25 października). Pendrive w formacie FAT/exFAT zapisuje daty plików jako czas lokalny **bez strefy czasowej**, więc po zmianie czasu wszystkie daty z okresu letniego „przesunęły się" o godzinę. Aplikacja rozpoznawała skopiowane pliki po nazwie i dacie (z tolerancją 3 sekund), więc uznała je za inne pliki. Aktualizacja iOS to raczej nie ten powód.

**Poprawka:** teraz plik jest uznawany za już skopiowany, gdy ma tę samą nazwę i **ten sam rozmiar** co oryginał, albo gdy daty różnią się o pełną liczbę godzin (przesunięcie czasu). Dzięki temu zmiana czasu nie powtórzy tego problemu.

**Co zrobić:**
1. **Nie uruchamiaj kopii na starej wersji.** Zainstaluj tę aktualizację (podmień folder `Sources`, Build IPA, Sideloadly).
2. Dotknij „Sprawdź, ile zostało". Powinno pokazać tylko nowe zdjęcia z ostatnich dni.
3. Jeśli kopia już ruszyła i skopiowała dużo plików, na dysku mogły powstać duplikaty z końcówką `_1`, `_2` (np. `IMG_1234_1.HEIC`). Nic z nich nie jest kasowane przez aplikację. Napisz do mnie, przygotuję skrypt na Windows, który znajdzie identyczne pliki i pozwoli je bezpiecznie usunąć.

# Aktualizacja: wybór źródła (cała biblioteka / tylko z aparatu) i motywy kolorystyczne

Wszystko jest w **Ustawieniach** (zębatka). Dotychczasowe ustawienia zostają.

## 1. Skąd kopiować
W sekcji „Zawartość kopii" jest nowy przełącznik **Cała biblioteka / Tylko z aparatu**.

„Tylko z aparatu" jest **przybliżeniem**, bo iOS nie oznacza, co zrobiono aparatem. Kopiowane są elementy, które:
- są w Twojej własnej bibliotece (nie zsynchronizowane z komputera i nie ze współdzielonych albumów),
- nie są zrzutem ekranu ani nagraniem ekranu,
- mają oryginalną nazwę pliku typu `IMG_1234`, `MVI_1234` albo `PANO_1234`.

Pomijane są więc m.in. zdjęcia zapisane z internetu, z komunikatorów (np. WhatsApp) i zrzuty ekranu. Zdjęcia odebrane przez AirDrop zachowują nazwy `IMG_xxxx`, więc mogą się załapać. Przełącznik działa razem z filtrem „Zdjęcia / Filmy". To, co już jest na dysku, nie jest usuwane.

## 2. Motywy kolorystyczne
Nowa sekcja „Motyw kolorystyczny": **Klasyczny** (dotychczasowy niebiesko-granatowy), **Zachód słońca** (róż i fiolet) i **Las** (zieleń i turkus). Zmiana działa od razu i obejmuje tło, przyciski, pasek pojemności i okrągły wskaźnik postępu.

## 3. Podział na foldery (np. zrzuty ekranu osobno)
Nowa sekcja „Podział na foldery" w Ustawieniach:
- **Wszystko razem** (jak dotąd),
- **Zrzuty ekranu osobno**: zrzuty i nagrania ekranu trafiają do `Screenshots/2026-10/…`, reszta zostaje tam, gdzie była,
- **Aparat / zrzuty / inne**: foldery `Camera/`, `Screenshots/` i `Other/` (zdjęcia z internetu, komunikatorów, AirDrop), a w nich układ rok-miesiąc.

Rozpoznawanie jest przybliżone (typ „zrzut ekranu" z iOS, nazwa pliku `IMG_1234`, źródło elementu). Pliki, które już są na dysku, zostają na miejscu i **nie są kopiowane drugi raz**. Aplikacja niczego nie przenosi ani nie kasuje, więc zrzuty skopiowane wcześniej do folderu z aparatem możesz usunąć ręcznie (na dysku sortuj po nazwie, zrzuty to zwykle `IMG_xxxx.PNG`).

## 4. Czyszczenie logu i historii
- **Usuń log:** w podsumowaniu po kopii, obok „Udostępnij log", jest przycisk „Usuń log". Kasuje wyeksportowany plik logu (i starsze pliki logów z pamięci tymczasowej telefonu).
- **Wyczyść historię:** w oknie „Historia kopii" jest przycisk z koszem (po lewej u góry). Po potwierdzeniu usuwa listę przebiegów z dysku i z aplikacji. **Zdjęcia na dysku i data ostatniej kopii zostają.** Przycisk jest nieaktywny w trakcie kopii.

## 5. Zakres dat
Sekcja „Zakres dat" w Ustawieniach: **Wszystkie**, **Ostatnie 30 / 90 dni**, **Ostatni rok** albo **Własny zakres** (od, do). Liczy się data wykonania zdjęcia. Dobre do pierwszej próby na małej partii. Zdjęcia spoza zakresu, które już są na dysku, zostają.

## 6. Wybór albumów
Sekcja „Albumy": **Wszystkie**, **Tylko wybrane** albo **Pomiń wybrane**. Po wybraniu trybu dotknij „Wybierz albumy" i zaznacz albumy. Lista zawiera Twoje albumy oraz kilka systemowych (Zrzuty ekranu, Ulubione, Selfie, Live Photos, Panoramy, Filmy). Pierwsze otwarcie listy może poprosić o dostęp do Zdjęć.
- „Pomiń wybrane" + album „Zrzuty ekranu" to prosty sposób, by zrzutów w ogóle nie kopiować.
- Zdjęcie może być w kilku albumach: przy „Tylko wybrane" jest kopiowane, jeśli jest w którymkolwiek z zaznaczonych, a przy „Pomiń wybrane" jest pomijane, jeśli jest w którymkolwiek.
- Przy „Tylko wybrane" bez zaznaczonego albumu nic nie zostanie skopiowane (aplikacja o tym ostrzega).
- Wszystkie filtry (media, źródło, daty, albumy) działają razem i łączą się warunkiem „i".

## 7. Blokada aplikacji (PIN 4-cyfrowy i Face ID)
Ustawienia › „Blokada aplikacji".
- **Włącz blokadę (PIN):** ustawiasz 4-cyfrowy PIN (wpisujesz dwa razy). PIN nie jest zapisany wprost: w pęku kluczy iOS (Keychain) jest tylko jego skrót z solą.
- **Odblokowuj przez Face ID** (lub Touch ID): przełącznik pojawia się, gdy telefon to obsługuje. Face ID jest tylko skrótem, a PIN działa zawsze. Przy pierwszym użyciu iOS zapyta o zgodę.
- **Zmień PIN** i **Wyłącz blokadę** wymagają podania obecnego PIN-u.
- Aplikacja blokuje się po każdym wyjściu z niej (też po zablokowaniu telefonu) i przy uruchomieniu. W przełączniku aplikacji treść jest zasłonięta. Otwarte okna (ustawienia, historia) zamykają się przy blokadzie.
- Po 5 błędnych PIN-ach z rzędu jest przerwa 30 s, po kolejnych 5 dłuższa (do 10 min).
- **Trwająca kopia nie jest przerywana przez blokadę** (iOS i tak zawiesza aplikację w tle).
- **Zapomniany PIN:** usuń aplikację i zainstaluj ją ponownie (Sideloadly). Tracisz tylko ustawienia. Zdjęcia, kopia na dysku i historia (zapisana na dysku) zostają. Blokada nie chroni więc przed kimś, kto ma dostęp do Twojego komputera z Sideloadly i telefonu, tylko przed zwykłym zajrzeniem do aplikacji.

## 8. Albumy i ulubione w pliku albums.json
Pliki zdjęć nie niosą informacji o albumach ani o serduszkach (ulubionych), więc po przywróceniu zdjęć z dysku by zniknęły. Po każdej kopii aplikacja zapisuje w folderze kopii plik **`albums.json`**: dla każdego albumu, ulubionych i ukrytych zdjęć lista ścieżek plików na dysku, np.:

```
{
  "albums": [ { "title": "Rodzina", "items": ["2026-10/IMG_1234.HEIC", "…"] } ],
  "favorites": ["2026-10/IMG_1234.HEIC"],
  "hidden": [],
  "generated": "2026-10-16T20:50:00Z",
  "version": 1
}
```
- Włączone domyślnie. Wyłączysz w Ustawieniach › „Albumy i ulubione".
- Obejmuje Twoje własne albumy (nie współdzielone) oraz ulubione i ukryte zdjęcia. Wpis trafia tylko tam, gdzie plik naprawdę jest na dysku.
- Plik odzwierciedla **bieżące filtry** (zakres dat, albumy, źródło), więc pełny obraz daje kopia bez filtrów. Przy dużej bibliotece zapis może chwilę potrwać po końcu kopii.
- Nie powstaje przy „Spróbuj ponownie", przy analizie ani przy kopii anulowanej lub przerwanej.
- Plik jest zwykłym JSON-em. Na jego podstawie można później napisać skrypt, który odtworzy albumy (np. na komputerze albo przy imporcie do innej aplikacji). Mogę taki skrypt przygotować.

## 9. Przypomnienie o kopii
Ustawienia › „Zabezpieczenia i powiadomienia" › **Przypomnij o kopii**: Wyłączone / po 7 / po 14 / po 30 dniach (domyślnie 14).
- Powiadomienie przychodzi o **18:00** w dniu, w którym od ostatniej **w pełni udanej** kopii minie wybrana liczba dni.
- Jeśli ten termin już minął, przypomnienie przychodzi za 3 dni (bez codziennego męczenia). Po każdej udanej kopii termin liczy się od nowa.
- Wymaga zgody na powiadomienia (aplikacja zapyta po włączeniu). Bez zrobionej choć jednej kopii przypomnienie się nie pojawi.
- Data ostatniej kopii jest brana z dysku albo zapamiętana w aplikacji, więc działa też przy odłączonym dysku.

## 10. Prędkość i czas do końca
Prędkość i czas do końca były już w aplikacji, ale liczyły się ze **średniej z całej kopii**, więc jeden wolny plik z iCloud psuł wynik na długo. Teraz:
- prędkość liczy się z **ostatniej minuty**,
- czas do końca pokazuje też **godzinę zakończenia** („koniec ok. 21:40"),
- czas wstrzymania nie jest liczony.

## 11. Wstrzymaj i wznów
Podczas kopii nad „Anuluj kopię" jest przycisk **Wstrzymaj kopię**.
- Wstrzymanie następuje **po bieżącym pliku** (pojedynczego pliku nie da się zatrzymać w połowie). Do tego czasu widać „Wstrzymuję po bieżącym pliku…", a przycisk pozwala to cofnąć.
- Gdy kopia stoi, widać „Wstrzymano (45 z 1200)", a ekran może się wygaszać. **Wznów kopię** kontynuuje od następnego pliku, bez ponownego skanowania.
- Nie odpinaj dysku podczas pauzy, jeśli chcesz wznowić: po wznowieniu kopia przerwałaby się z komunikatem o odłączeniu dysku. Wtedy wystarczy podłączyć dysk i uruchomić kopię normalnie, bo pominie to, co już skopiowano.
- „Anuluj kopię" działa także w czasie pauzy.
- Uwaga: iOS i tak zawiesza aplikację w tle, więc pauza służy do przerwy z aplikacją na wierzchu (np. żeby użyć telefonu do czegoś na chwilę).

## Jak zaktualizować
Pojawiły się nowe pliki (`Theme.swift`, `AlbumPickerView.swift`, `AppLock.swift`), a **`project.yml` się zmienił** (opis uprawnienia Face ID). Podmień cały folder `Sources` **oraz plik `project.yml`**:
1. Rozpakuj `USBPhotoBackup-pakiet.zip`.
2. Na GitHubie: **Add file › Upload files**, przeciągnij cały folder **`Sources`** oraz plik **`project.yml`** i zatwierdź.
3. **Actions › Build IPA › Run workflow**, pobierz nowy `.ipa` i zainstaluj w Sideloadly na wierzchu starej wersji.

Workflow się nie zmienił. W poprzedniej wersji build zgłosił błąd w filtrze „Tylko z aparatu” (nieistniejący znacznik nagrań ekranu), jest poprawiony. Kodu nie kompilowałem, więc jeśli build zgłosi błąd, wklej mi końcówkę logu.
