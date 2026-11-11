---
opened: 2026-11-11
---

# F010 · Android identifies the app as Pickteams

## Outcome

Android pokazuje nazwę „Pickteams” zamiast „app” pod ikonką i w informacjach o aplikacji. Dotychczasowa instalacja zachowuje swoją tożsamość i dane.

## Scope

- Nazwa użytkowa aplikacji w runnerze Androida.
- Kontrola etykiety w źródłach i gotowym APK.
- Zachowanie istniejącej ikonki, identyfikatora i sposobu podpisywania.

## Out of scope

- Zmiana application ID, nazwy pakietu Dart, deep linków lub klucza.
- Przebudowa brandingu WWW i innych runnerów.

## Acceptance

- Launcher i informacje Androida otrzymują nazwę „Pickteams”, nie „app”.
- Kontrola manifestu wykrywa regresję tej etykiety.
- Gotowy pakiet ma nadal application ID com.example.app.
- Zasoby ikonki i callback Google nie zmieniają się.

## Notes

Obecny manifest Androida ma dosłowną etykietę „app”. Kontrola gotowego APK może być wykonana przy wspólnym wydaniu całego zestawu; sama zmiana źródła nie dowodzi aktualizacji launchera na urządzeniu.
