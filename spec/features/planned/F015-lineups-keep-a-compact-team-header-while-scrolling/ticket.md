---
opened: 2026-11-11
---

# F015 · Lineups keep a compact team header while scrolling

## Outcome

Szczegóły meczu i podgląd propozycji pokazują zwarte, dwukolumnowe składy z czytelną tożsamością drużyn. Na wejściu znaczniki kolorów są większe; podczas przewijania nagłówek zwija się, ale kolory i nazwy drużyn nadal pozwalają rozpoznać strony. Lista zawodników ma pierwszeństwo przed panelem szans.

## Scope

- Zwijany nagłówek z istniejącymi kolorami drużyn zamiast nowych herbów.
- Przypięta, kompaktowa tożsamość drużyn przy oglądaniu składów.
- Wspólny zwarty wiersz gracza w obu kolumnach, także w propozycjach draftu.
- Panel prawdopodobieństwa i inne podsumowania poniżej pełnych składów.
- Zachowanie wyśrodkowanego wyniku, menu akcji, edycji i bezpośredniego Zapisz/Anuluj.

## Out of scope

- Widok boiska, zakładki, reklamy i assety Flashscore.
- Zmiana globalnej nawigacji, wzorów rankingu lub limitu draftu.
- Wymaganie, by cały wybór graczy do draftu mieścił się na jednym ekranie.

## Acceptance

- Przewijanie zmniejsza znaczniki drużyn, lecz nie gubi ich kolorów ani stron.
- Przy zwykłym tekście widoczne jednocześnie są nagłówki drużyn i osiem wierszy każdej drużyny w prawdziwej powłoce 360 × 640.
- Układ z jedenastoma graczami na stronę jest sprawdzony w zwiniętym stanie; ewentualnego ograniczenia nie maskuje większy viewport ani nieczytelna czcionka.
- Długie nazwy i większy tekst pozostają dostępne przez naturalne przewijanie.
- Panel szans nie zajmuje miejsca między nagłówkiem drużyn a ostatnim graczem.
- Akcje i edycja wyniku zachowują swoje uprawnienia i zachowanie.

## Notes

Wykorzystuje wspólny wiersz gracza przygotowywany dla wyboru i składów. Dopasowanie 11-osobowego składu dotyczy renderowania listy, nie zwiększenia limitu generatora ponad 16 uczestników. Osiem na stronę jest twardą kontrolą podstawową; 11 na stronę jest celem przy zachowaniu czytelności. Panel szans może wymagać dalszego przewinięcia.
