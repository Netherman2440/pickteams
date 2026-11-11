---
opened: 2026-11-11
landed: 2026-11-11
---

# F013 · Match lists put the date beside unboxed team scores

## Outcome

Lista meczów ma spokojny układ inspirowany Flashscore: data DD.MM po lewej, dwie drużyny ze znacznikami kolorów pośrodku i odpowiadające im wyniki po prawej. Wyniki nie mają obramowanych kwadratów konkurujących z kolorami drużyn. Ten układ działa zarówno na telefonie, jak i szerokim ekranie.

## Scope

- Wspólny widget meczu na liście składu i w historii gracza.
- Jedna lewa kolumna daty przy dwóch wierszach drużyn.
- Proste, wyrównane liczby wyniku bez ramek.
- Długie nazwy oraz mecze bez wyniku lub wybranego składu.

## Out of scope

- Układ szczegółów meczu i reguły jego edycji.
- Zmiany wyniku, zapisów dat albo sortowania historii.

## Acceptance

- Widoczna data ma format DD.MM i leży po lewej obu drużyn.
- Każdy wynik jest wyrównany z właściwą nazwą i znacznikiem koloru.
- Żaden wynik nie ma obramowanego pola.
- Długie nazwy nie nakładają się na datę ani wyniki przy 360 px i 1440 px.
- Kliknięcie karty nadal otwiera właściwy mecz w obu listach.
- Pełna data pozostaje dostępna w semantyce lub podpowiedzi.

## Notes

Nowa dyspozycja zastępuje poprzedni wymóg zachowania poziomej karty desktopowej. To inspiracja układem, nie kopiowanie kolorystyki, reklam czy assetów Flashscore.
