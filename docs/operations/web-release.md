# Wydanie web na Vercelu

Build jest zdefiniowany w repozytorium, nie w skrypcie zapisanym wyłącznie w panelu Vercela. `vercel.json` obsługuje projekt z katalogiem głównym repozytorium; `app/vercel.json` obsługuje projekt z katalogiem głównym `app/`. Oba uruchamiają `app/tool/build_web_release.py` i publikują wyłącznie wynik `app/build/web`.

## Wymagania

- Flutter 3.47.9, dokładny framework `c197ca5199e9ee5661e865596c9c07294dfab51c`, taki sam jak w GitHub Actions.
- `SUPABASE_URL` i `SUPABASE_ANON_KEY` w ustawieniach środowisk Preview oraz Production Vercela. Tylko klucz publishable lub JWT z rolą `anon`; klucze serwerowe są odrzucane.
- Numer wersji i builda w `app/pubspec.yaml`.

Nie zapisuj wartości konfiguracji do repozytorium, raportów ani logów. Skrypt przekazuje konfigurację kompilatorowi przez tymczasowy plik z uprawnieniami `0600`, poza katalogiem publikacji, i usuwa go również po nieudanej kompilacji.

Bez istniejącego SDK skrypt pobiera oficjalne archiwum, weryfikuje SHA-256 z metadanych wydania oraz dokładną wersję i rewizję frameworka. W CI i lokalnie można wskazać istniejący SDK przez `PICKTEAMS_FLUTTER_ROOT`; niezgodny SDK kończy build błędem. Instalacja zależności używa `--enforce-lockfile`. Kompilowany jest rzeczywisty `lib/main.dart`, nigdy fixture.

## Sprawdzenia przed scaleniem

Workflow `Main` uruchamia testy narzędzi Python, analizę Flutter, pełny zestaw testów native, osobny przebieg Chrome dla regresji auth — w tym test pomijany w przebiegu native — oraz skonfigurowany build web. Te same sprawdzenia uruchamiają się ponownie po pushu do `main`. Produkcyjne dane klienta są dostępne tylko w kroku kompilacji, nie w zadaniu testowym.

Preview Vercela musi przejść osobno. Zielone GitHub Actions nie dowodzą poprawnego buildu ani konfiguracji w Vercelu. Scalaj dopiero po sprawdzeniu obu wyników. Integracja Git Vercela publikuje produkcję po scaleniu do skonfigurowanej gałęzi produkcyjnej `main`.

## Weryfikacja produkcji

Każdy build zawiera publiczny `/release.json`: wersję, pełny commit, przypięty Flutter oraz SHA-256 `index.html` i `main.dart.js`. Manifest nie zawiera konfiguracji Supabase. Ma nagłówek `Cache-Control: no-store`.

Po wdrożeniu:

1. Sprawdź status produkcyjnego deploymentu i przypisany commit, nie tylko status preview.
2. Pobierz `/release.json` z domeny produkcyjnej. Porównaj commit ze scalonym `main` i wersję z `pubspec.yaml`.
3. Pobierz pliki wymienione w `files` i porównaj ich SHA-256 z manifestem.
4. Otwórz aplikację w świeżym kontekście przeglądarki na szerokim i wąskim ekranie. Sprawdź, że nie ma pustego widoku ani błędu startu. Nie wykonuj operacji zmieniających dane produkcyjne w ramach smoke testu.

Błąd preview lub niedostępne logi nie są podstawą do uznania konkretnej przyczyny awarii. Jeśli build nadal nie przechodzi po nadpisaniu konfiguracji z repozytorium, potrzebne są rzeczywiste logi Vercela lub dostęp operatora.
