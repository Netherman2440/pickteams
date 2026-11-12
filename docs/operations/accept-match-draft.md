# Włączenie atomowej akceptacji draftu przez SQL Editor

Ten krok dodaje brakującą funkcję `accept_match_draft`, bez tabeli potwierdzeń.
Nie wywołuje funkcji, nie tworzy meczów i nie zmienia Auth ani ustawień projektu.
Nie jest potwierdzeniem gotowości hostowanego API ani zgodą na wymianę APK.
Stary APK pozostaje opublikowany do przejścia wszystkich bramek wydania.

## Instrukcja dla operatora

1. Po przeglądzie przez koordynatora otwórz plik
   [`accept_match_draft_operator.sql`](../../supabase/tools/accept_match_draft_operator.sql)
   z zatwierdzonego commitu (widok **Raw**, nie podgląd skrócony).
2. W Supabase Dashboard wybierz właściwy projekt i **SQL Editor → New query**.
   Użyj sesji administracyjnej z prawem do DDL i zapisu istniejącej historii migracji.
   Nie przesyłaj nikomu tokenu ani hasła.
3. Wklej **cały plik** i uruchom go raz, bez zaznaczania fragmentu. Nie doklejaj
   migracji ręcznie. Plik sam wykonuje `BEGIN`, migrację, zapis historii,
   kontrolę uprawnień, `NOTIFY pgrst, 'reload schema'` i `COMMIT`.
4. Oczekiwany wynik to brak błędu SQL i jeden wiersz wartości logicznych:
   `function_exists`, `authenticated_execute_allowed`, `anonymous_execute_denied`,
   `invoker_mode` — wszystkie `true`.
   `migration_history_present` powinno być `true`, jeśli historia już istnieje.
   `false` oznacza brak historii; nie oznacza nieudanej migracji.
5. Przekaż koordynatorowi tylko te wartości i informację o braku błędu.
   Nie przesyłaj zrzutu panelu zawierającego dane projektu. Koordynator osobno
   sprawdzi dostępność właściwej trasy API i pozostałe bramki wydania.

Przy **dowolnym błędzie** zatrzymaj się. Jeśli edytor zachował otwartą sesję,
wykonaj w niej `ROLLBACK;`. Nie uruchamiaj dalszych fragmentów, nie usuwaj
obiektów i nie zmieniaj skryptu na `IF NOT EXISTS` lub `CREATE OR REPLACE`.
Przekaż zanonimizowany komunikat błędu do przeglądu. Wiersz wynikowy bez
potwierdzenia braku błędów całego wykonania nie jest dowodem powodzenia.
Po utracie odpowiedzi nie ponawiaj kroku w ciemno: wynik zatwierdzenia może być
nieznany. Najpierw koordynator sprawdza metadane i historię.

## Historia i wycofanie

- Całe DDL i zapis wersji `20261111120000` są w jednej transakcji. Błąd przed
  `COMMIT` cofa oba. Powiadomienie jest dostarczane dopiero po zatwierdzeniu.
- Jeśli `supabase_migrations.schema_migrations` istnieje, skrypt blokuje ją na
  czas transakcji i dopisuje dokładnie tę wersję. Wypełnia `name` i `statements`
  tylko wtedy, gdy te kolumny istnieją. `statements` zawiera pełny kanoniczny SQL
  jako jeden element tablicy. Nie nadpisuje istniejących wierszy. Nietypowy
  schemat historii, brak praw albo limit czasu blokady powoduje błąd i rollback.
- Istniejąca wersja, pozostałość starej tabeli `match_draft_acceptances` lub dowolne przeciążenie tej funkcji
  powoduje bezpieczną odmowę. Ponowne wykonanie nie naprawia ani nie uzgadnia
  rozbieżnych obiektów. Zatrzymaj się i przekaż sprawę do przeglądu.
- Gdy historii nie ma, skrypt jej **nie tworzy** i nie udaje zastosowania starych
  migracji. Wynik `migration_history_present = false` trzeba zachować jako
  ograniczenie. **Nie uruchamiaj później `supabase db push`**, dopóki osobny
  przegląd nie uzgodni rzeczywistego schematu z historią. Samo dopisanie nowej
  wersji nie rozwiązuje brakującego starego baseline'u. Nawet przy istniejącej
  historii ten krok nie dowodzi zgodności wszystkich wcześniejszych migracji.
- Po udanym `COMMIT` polecenie `ROLLBACK` nie cofnie wdrożenia. Nie usuwaj funkcji
  ani wpisu historii jako „rollback”.
  Cofnięcie po zatwierdzeniu wymaga osobnego, zatwierdzonego planu. Brak API po
  poprawnym SQL nie jest powodem do ponownego uruchamiania migracji.

## Ponawianie akceptacji w aplikacji

Funkcja zachowuje cztery parametry, ale przyjmuje i ignoruje `p_request_id`,
aby istniejący APK działał bez przebudowy. Blokada po stronie klienta chroni
przed szybkim podwójnym kliknięciem. Ponowienie po utracie odpowiedzi może jednak
utworzyć drugi mecz, gdy `p_match_id` jest `null`. Właściciel zaakceptował to
ryzyko: duplikat usuwa się istniejącą akcją **Usuń mecz**. Redraw wskazanego meczu
nadal blokuje jego wiersz i nie powiela snapshotów rankingu. To zachowanie RPC,
nie zgoda na ponawianie skryptu wdrożeniowego bez sprawdzenia metadanych.

## Odtwarzanie i lokalny dowód (dla recenzenta)

Generator używa tylko biblioteki standardowej Pythona. Czyta
`supabase/migrations/20261111120000_accept_match_draft.sql`.
Nagłówek artefaktu zawiera SHA256; między znacznikami `BEGIN CANONICAL MIGRATION`
i `END CANONICAL MIGRATION` znajdują się niezmienione bajty źródła oraz jeden
zewnętrzny separator nowej linii. Nie edytuj artefaktu ręcznie.

```sh
python3 supabase/tools/generate_draft_rollout.py
python3 supabase/tools/generate_draft_rollout.py --check
python3 -m unittest discover -s supabase/tools -v
python3 supabase/tools/prove_draft_rollout.py \
  --pg-bin /sciezka/do/postgresql/16/bin \
  --proof-dir /absolutna/krotka/nowa/sciezka
```

Ostatnia komenda tworzy własny klaster PostgreSQL 16, używa wyłącznie prywatnego
socketu Unix, stosuje `supabase/tests/fixtures/local_auth.sql` i wcześniejsze
migracje. Katalog dowodu musi być nowy; ścieżka socketu musi mieścić się w limicie
systemowym. Klaster jest zatrzymywany także po błędzie. Logi pozostają w podanym
katalogu. Test sprawdza brak częściowych zmian przez porównanie pełnych dumpów,
a nie tylko kod wyjścia. Sam artefakt nie wywołuje RPC. Osobny test SQL w tym
samym klastrze wywołuje funkcję na danych syntetycznych i wycofuje te dane.
Sprawdza też duplikaty po ponowieniu i redraw bez powielania snapshotów.
Żaden test nie zawiera danych produkcyjnych ani nie wywołuje hostowanego API.

To nie jest pełny Supabase, GoTrue ani PostgREST. Lokalne booleany nie dowodzą
odświeżenia hostowanego cache, rzeczywistych tokenów JWT, wszystkich reguł RLS,
zachowania aplikacji ani gotowości wydania. Nie ma sekwencyjnego fallbacku.
