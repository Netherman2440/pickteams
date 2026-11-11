---
opened: 2026-11-11
---

# F014 · Player rows are shared and draft selection scrolls as one list

## Outcome

Wiersze graczy w drafcie, propozycjach, meczu i zwykłej liście graczy korzystają z jednego języka wizualnego; zmienia się gęstość i potrzebne akcje, nie cały wygląd. Wybór do draftu przypomina listę zakupów: zaznaczeni są na górze, dostępni poniżej, a całość przewija się jednym gestem pod wspólną wyszukiwarką.

## Scope

- Kanoniczny wiersz gracza z kontrolowaną gęstością i miejscem na akcje kontekstowe.
- Wspólna implementacja nazw i rankingu zamiast osobnych wariantów ekranu.
- Jedna powierzchnia przewijania obu sekcji wyboru graczy.
- Jedno zapytanie wyszukiwania filtrujące obie sekcje bez utraty zaznaczeń.
- Zachowanie nawigacji do profilu i przeciągania tam, gdzie są dostępne.

## Out of scope

- Wymuszanie zmieszczenia całego draftu na ekranie i zmiana limitów generatora.
- Zapis meczu, akceptacja propozycji i nawigacja Wstecz.
- Zwijany nagłówek meczu i zmiany precyzji rankingu.

## Acceptance

- Oba zbiory graczy są częścią jednego przewijanego widoku, z wybranymi nad dostępnymi.
- Wyszukiwanie ogranicza obie sekcje, ale nie usuwa wybranych identyfikatorów.
- Wybranie i odznaczenie gracza przenosi go między właściwymi sekcjami bez duplikatu.
- Zwykła, długa lista przewija się bez zagnieżdżonych pionowych scrolli.
- Użycia w meczu, propozycjach i wyborze współdzielą komponent wiersza z konfiguracją gęstości.
- Testy prawdziwych stron potwierdzają czytelność przy 360 px, 1440 px i większym tekście.

## Notes

Ranking nie powinien automatycznie tworzyć drugiego wiersza pod każdym krótkim nazwiskiem. Widok składów potrzebuje wariantu zwartego, a klikalna lista wyboru wygodnego celu dotykowego. Nie zmniejszać czcionki całego interfejsu, by uzyskać zrzut mieszczący więcej elementów. Zmiany wnętrza layoutu wyboru należy oddzielić od równoległej poprawki cyklu życia draftu.
