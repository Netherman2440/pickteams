---
opened: 2026-11-11
landed: 2026-11-11
---

# F011 · Player details use one edit mode

## Outcome

Szczegóły gracza mają jeden przycisk edycji zamiast osobnego ołówka przy każdym polu. Po włączeniu edycji użytkownik może kliknąć nazwę, ranking albo pozycję i zmienić wybrane pole; działa to na telefonie i desktopie.

## Scope

- Jeden widoczny przełącznik trybu edycji i jednoznaczne zakończenie tego trybu.
- Klikalne, dostępne z klawiatury pola w trybie edycji.
- Zachowanie obecnych dialogów zapisu/anulowania, walidacji i uprawnień.
- Czytelny układ profilu bez poziomego przepełnienia.

## Out of scope

- Zmiana obliczeń, audytu lub precyzji rankingu.
- Przebudowa wykresu, statystyk albo usuwania gracza.

## Acceptance

- W widoku znajdującym się poza edycją uprawniony użytkownik widzi dokładnie jeden ołówek.
- W trybie edycji każde z trzech pól otwiera właściwą edycję bez dodatkowych ołówków.
- Anulowanie dialogu nie zapisuje zmian, a błędny zapis nie udaje sukcesu.
- Użytkownik bez uprawnień nie może uruchomić edycji.
- Prawdziwy profil Flutter mieści się poziomo przy 360 px i 1440 px, także z długą nazwą i większym tekstem.

## Notes

Jedno wejście w edycję nie oznacza nowej transakcji „zapisz wszystko”: zachowujemy istniejące, niezależne operacje pól. Zaokrąglanie historii rankingu pozostaje osobnym, zakolejkowanym zadaniem.
