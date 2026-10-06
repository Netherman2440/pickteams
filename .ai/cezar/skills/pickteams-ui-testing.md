---
name: pickteams-ui-testing
description: Weryfikacja UI Pickteams na wąskich ekranach w żywej przeglądarce (serwer debug + Playwright). Użyj przy każdym tasku dotyczącym layoutu/responsywności.
---

# Pickteams — weryfikacja UI na żywo (mobile/ responsywność)

Ten skkill to instrukcja operacyjna: jak odpalić aplikację lokalnie, chodzić po
ekranach w przeglądarce headless, mierzyć geometrię i zbierać dowody przed/po
zmianie. Zawsze zaczynaj od niego przy taskach UI/layout, nawet jeśli task
wydaje się "tylko kodowy" — kryterium akceptacji mierzy się na ekranie.

## 0. Zasady ogólne

- Pracujesz w worktree cezara. Nie pushuj, nie merguj do main/dev — zostaw
  surowy diff + ewentualne commity na swoim branchu `cez/<id>`.
- Przed deklaracją "gotowe" musisz mieć **dowód geometryczny przed/po**
  (sekcja 5) + `flutter analyze` bez nowych błędów + `dart format`.
- Serwer bindowany jest na stały port **4370**; jeśli coś na nim wisi,
  skrypt sam to zabije.

## 1. Serwer deweloperski (debug mode — wymagany)

```bash
bash scripts/ui-serve.sh start     # pierwszy start: kompilacja 1–4 min
bash scripts/ui-serve.sh restart   # po każdej zmianie kodu (15–60 s)
bash scripts/ui-serve.sh stop      # na koniec taska
```

- Skrypt sam tworzy `app/.env` (gitignored; klucz publishable Supabase —
  publiczny, produkcyjny projekt). Nie kopiuj go nigdzie do commita.
- **Tylko tryb debug**: on eksponuje `flt-semantics-placeholder` (drzewo
  dostępności — bez niego przeglądarka nie widzi żadnych elementów) i maluje
  paski przepełnienia RenderFlex. Release/profil nie mają tego.
- Log serwera: `.ai/cezar/tmp/ui-serve.log` (szukaj tam stacktrace'ów, jeśli
  ekran jest pusty).

## 2. Przeglądarka (Playwright MCP)

Narzędzia przeglądarkowe są odroczone — najpierw je załaduj:

- `tool_search` z frazą `playwright browser navigate resize screenshot snapshot click evaluate scroll`.
- Przeglądarka jest **headless Chrome**; każda sesja zaczyna od about:blank.

### 2.1. Stały cykl otwarcia ekranu

1. Ustaw viewport: `browser_resize` — kanoniczne rozmiary audytu:
   - **360×800** — mobile (główny), **768×1024** — tablet, **1280×800** — desktop.
2. `browser_navigate` na `http://127.0.0.1:4370/#/<route>` (routing haszowy;
   mapa w sekcji 4).
3. **Poczekaj na boot aplikacji** — pierwsze cold boot 10–60 s. Poll
   (`browser_evaluate`, w pętli co ~3 s, do ~120 s):
   ```js
   () => ({ view: !!document.querySelector('flutter-view'),
            placeholder: !!document.querySelector('flt-semantics-placeholder') })
   ```
4. **Włącz semantics** (raz na sesję, debug only):
   ```js
   () => { const ph = document.querySelector('flt-semantics-placeholder');
           if (ph) { ph.click(); return 'ok'; } return 'no-placeholder'; }
   ```
   Po ~1–2 s drzewo a11y jest gotowe (`flt-semantics` w DOM).
5. Dopiero teraz: `browser_snapshot` / `browser_find` czytają ekran jako tekst.

Bez kroku 4 snapshot jest pusty — to najczęstszy błąd. Nie używaj
`screenshot` do "czytania" ekranu (to canvas); snapshotty rób jako dowód
wizualny dla człowieka.

### 2.2. Interakcja

- **Klik**: `browser_click` z refem ze snapshota (`browser_find` najpierw).
- **Pole tekstowe** (szukajka, login): `fill` bywa zawodny na Flutter web —
  kliknij pole, potem wpisz przez klawiaturę:
  ```js
  async (page) => { await page.getByRole('textbox', { name: 'Szukaj' }).click();
    await page.keyboard.type('tekst', { delay: 20 }); }
  ```
  (użyj `browser_run_code_unsafe`).
- **Scroll listy**: Flutter scrolluje sam (viewport strony się nie rusza):
  ```js
  async (page) => { await page.mouse.move(180, 400);
    await page.mouse.wheel(0, 900); }
  ```
- **Drag&drop kafelków** (LongPressDraggable): mouse down → odczekaj ~600 ms
  → move w małych krokach → up. Bywa dropkowy; do weryfikacji layoutu wystarczy
  zwykły klik (wybór gracza) — drag testuj tylko, gdy task tego wprost dotyczy.

### 2.3. Konsola

Błędy JS/Flutter (łącznie z wyjątkami renderowania) lądują w logu konsoli
(MCP je raportuje) oraz w `.ai/cezar/tmp/ui-serve.log`. Puste ekrany
diagnozuj tam.

## 3. Dane testowe

Gość (bez logowania) widzi publiczne składy:

| Skład | squad_id | Co ma |
|---|---|---|
| Politechnika Lubelska | `4f7ae6f4-537e-4187-aa83-9f6324afa1f6` | gracze, mecze, draft selection działa |
| Sobota na Orliku | `3026234c-6c55-4410-bdaf-6ec985cbb7d0` | turnieje (`02cfd990-c2a1-4908-ac9b-26c023af92be` i in.) |

Konto testowe **owner** (pełne flowy: draft z danymi, turnieje, ustawienia):

- login: `cezarpta171412072@maxxspace.com`
- hasło: `CezarUiTest-2026!x`
- skład: „Cezar UI Test" `1cab175e-a1e8-4e6f-99b5-2f6575c76315`
  (prywatny, 12 graczy o różnym rankingu)

Logowanie: `#/auth` → kliknij i wpisz E-mail → kliknij i wpisz Hasło
(klawiatura, patrz 2.2) → „Zaloguj się" → URL zmienia się na `#/me`.

Zasady: to produkcyjna baza — **nie usuwaj ani nie twórz** danych, których
task nie wymaga; nic nie zapisuj poza składem testowym; wylogowanie nie jest
konieczne (sesja jest lokalna i efemeryczna).

## 4. Mapa ekranów (hash routing)

Baza: `http://127.0.0.1:4370/#`

| Ekran | Route |
|---|---|
| Landing | `/` |
| Logowanie | `/auth` · rejestracja `/auth/register` |
| Profil | `/me` |
| Lista składów | `/squads` |
| Strona główna składu | `/squads/<sid>` |
| Gracze | `/squads/<sid>/players` |
| Szczegóły gracza | `/squads/<sid>/players/<pid>` (+ `/stats`, `/matches`, `/tournaments`) |
| Mecze | `/squads/<sid>/matches` |
| Draft: wybór | `/squads/<sid>/matches/draft` |
| Draft: relacje | `/squads/<sid>/matches/relations` (+ `/against`) |
| Draft: wyniki | `/squads/<sid>/matches/<mid>/draft` |
| Szczegóły meczu | `/squads/<sid>/matches/<mid>` |
| Turnieje | `/squads/<sid>/tournaments` |
| Turniej: tworzenie | `/squads/<sid>/tournaments/create` |
| Turniej: draft | `/squads/<sid>/tournaments/<tid>/draft` |
| Turniej: szczegóły | `/squads/<sid>/tournaments/<tid>` |
| Turniej: drużyny | `/squads/<sid>/tournaments/<tid>/teams` |
| Ustawienia składu | `/squads/<sid>/settings` · ranking `/settings/ranking` |
| Statystyki składu | `/squads/<sid>/stats` |

`mid` do draft-results bierzesz z URL po wygenerowaniu propozycji (flow:
draft → wybierz ≥2 graczy → „Wygeneruj propozycję").

## 5. Pomiary geometrii (dowody bez wzroku)

Semantics nodes mają pozycje DOM — mierz przez `browser_evaluate`:

```js
() => {
  const targets = ['Wygeneruj', 'Przejdź', 'Ustawienia', 'Drużyny', 'Generuj'];
  const out = [];
  document.querySelectorAll('flt-semantics').forEach(n => {
    const t = (n.getAttribute('aria-label') || n.textContent || '').trim();
    const r = n.getBoundingClientRect();
    if (r.width > 5 && r.height > 5 && t.length > 0 && t.length < 120) {
      out.push({ t: t.slice(0, 40), x: Math.round(r.x), right: Math.round(r.right),
                 y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) });
    }
  });
  return { viewport: window.innerWidth, elements: out };
}
```

Kryteria oceny (mierzalne):

- **Wycięcie**: `right > viewport` (element za ekranem) → zła szerokość.
- **Zgnieciony element**: szerokość ~0 lub label tytułu nieobecny w snapshocie,
  a powinien być (np. tytuł AppBar).
- **Nachodzenie**: recty dwóch elementów się przecinają, a nie powinny.
- **Wymuszony poziomy scroll**: panel/element z `x > 0` i `right > viewport`,
  który powinien być widoczny w całości (np. panel drużyny w wynikach draftu).
- Debug rysuje też **żółto-czarne pasy** przy RenderFlex overflow — widać je
  na screenshocie; w konsoli/`ui-serve.log` pojawia się "A RenderFlex
  overflowed by N pixels".

Screenshots jako dowód: `browser_run_code_unsafe`:
```js
async (page) => { await page.screenshot({ path: '<worktree>/.ai/cezar/tmp/ui/<nazwa>-360-before.png' }); }
```
Katalog `.ai/cezar/tmp/ui/` jest gitignored; ścieżki podaj w raporcie końcowym.

## 6. Protokół weryfikacji taska UI

1. **Baseline**: `ui-serve.sh start` → otwórz dotknięte ekrany na 360×800
   (i jednym szerszym), zrób snapshot + geometrię + screenshot `-before`.
   Jeśli ekran wymaga ownera — zaloguj konto testowym.
2. **Zmiana kodu** w worktree.
3. `bash scripts/ui-serve.sh restart` (obowiązkowo — hot reload nie działa
   headless).
4. **Re-verify**: te same ekrany, ta sama procedura → `-after`.
5. Kryteria akceptacji z taska muszą być **zmierzone** (liczby przed/po),
   nie tylko "wygląda ok".
6. `cd app && flutter analyze` — zero nowych błędów; `dart format .` — czysto.
   Jeśli istnieją testy dotkniętych widgetów — `flutter test` (lub przynajmniej
   pliki, które ruszasz).
7. Screenshoty + liczby + ścieżki plików wpisz do raportu końcowego.
8. `bash scripts/ui-serve.sh stop` na koniec (zostaw port czysty dla
   następnego taska).

## 7. Pułapki

- Snapshot pusty → nie włączyłeś semantics (sekcja 2.1 krok 4) albo aplikacja
  się jeszcze bootuje.
- `fill` nie wpisuje tekstu → użyj click + `keyboard.type`.
- Scroll strony nie działa → to Flutter scrolluje wewnętrznie: `mouse.wheel`
  nad listą.
- Port zajęty / stary serwer → `ui-serve.sh start` sam zabija; nie odpalaj
  drugiego serwera obok.
- Supabase 4xx na ekranie → sprawdź czy jesteś zalogowany tam gdzie trzeba;
  gość widzi tylko publiczne składy.
- Nigdy nie commituj `app/.env` (jest gitignored, zostaw tak).
