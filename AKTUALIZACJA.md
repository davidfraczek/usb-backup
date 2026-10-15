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

## Jak zaktualizować
Pojawił się nowy plik `Theme.swift`, więc podmień cały folder `Sources`:
1. Rozpakuj `USBPhotoBackup-pakiet.zip`.
2. Na GitHubie: **Add file › Upload files**, przeciągnij cały folder **`Sources`** i zatwierdź.
3. **Actions › Build IPA › Run workflow**, pobierz nowy `.ipa` i zainstaluj w Sideloadly na wierzchu starej wersji.

`project.yml` i workflow się nie zmieniły. Kodu nie kompilowałem, więc jeśli build zgłosi błąd, wklej mi końcówkę logu.
