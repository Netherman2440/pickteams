---
opened: 2026-11-11
---

# F012 · A match is created only when a proposal is accepted

## Outcome

Wygenerowanie i przeglądanie propozycji nie tworzy meczu. Dopiero akceptacja wybranej propozycji zapisuje mecz z tym składem i całym zestawem propozycji; strzałka Wstecz oraz systemowe Wstecz wracają do draftu z zachowanym wyborem graczy i ustawieniami.

## Scope

- Nowy draft z wyboru graczy oraz ścieżka z relacjami.
- Niewiążący podgląd, przechodzenie między propozycjami i powrót do wyboru graczy.
- Zapis akceptacji wraz ze składami, propozycjami i potrzebnymi snapshotami jako kompletnej operacji.
- Ponowne otwieranie zapisanych propozycji oraz redraw istniejącego meczu bez przedwczesnej mutacji.
- Obsługa błędów i wielokrotnego kliknięcia akceptacji.

## Out of scope

- Zmiana generatora, punktacji, istniejących limitów liczby graczy lub logiki turniejów.
- Usuwanie historycznych pustych meczów i publikacja migracji na produkcji.
- Wizualna przebudowa list i nagłówków.

## Acceptance

- Generowanie, przeglądanie i opuszczenie podglądu wykonuje zero zapisów meczu, drużyn i historii rankingu.
- Oba sposoby powrotu odtwarzają wybranych graczy, relacje i ustawienie zmian.
- Akceptacja tworzy jeden kompletny mecz z wybraną propozycją i zapisanym zestawem propozycji.
- Szybkie ponowne kliknięcie akceptacji nie tworzy drugiego meczu.
- Błąd akceptacji pozostawia podgląd do ponowienia i nie pozostawia pustego lub częściowo zapisanego meczu.
- Redraw przed akceptacją nie zmienia istniejącego meczu.

## Notes

Obecna ścieżka tworzy pusty mecz jeszcze na ekranie wyboru, a notifier zapisuje wygenerowane propozycje przy obecności matchId. Należy zbadać obie granice. Jeśli pełny zapis wymaga migracji/RPC, przygotować transakcyjną operację z zachowaniem RLS i testami; nie stosować sekwencji „utwórz, a po błędzie usuń” ani nie wdrażać bez zgody na produkcję. Zapisany wynik i event-sourced delty pozostają bez zmian. Kod bazowy już przed tym zadaniem ustawia maxPlayersPerMatch na 22 i ma test dopuszczający ponad 16 graczy. Zachowujemy ten stan, zamiast wprowadzać niezamówioną zmianę limitów; rozbieżność z opisanym w vision/docelowym MVP limitem 16 nie jest rozwiązana przez tę poprawkę.
