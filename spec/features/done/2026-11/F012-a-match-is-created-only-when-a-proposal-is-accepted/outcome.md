# Wynik

Generowanie i przeglądanie propozycji nie zapisuje niczego; mecz z wybranym składem i pełnym zestawem propozycji powstaje dopiero po akceptacji, jedną transakcyjną operacją `accept_match_draft`. Oba powroty odtwarzają wybór graczy, relacje i ustawienie zmian, a błąd pozostawia podgląd do ponowienia. Implementacja weszła w commicie `13389bde8763299e421e1f5af864ab2b6ecdcb4b`, a 27 testów VM, niezależne 27 asercji PostgREST/JWT i lokalne testy SQL przeszły przed integracją.

Migrację wykonano na hostowanym projekcie 12 listopada 2026 artefaktem z commitu `3eba467180199e0fd4bd4214a44332b49a1bf33e`, po decyzji właściciela o rezygnacji z tabeli potwierdzeń: serwer nie deduplikuje ponowień, duplikat po zgubionej odpowiedzi kasuje „Usuń mecz”, a sygnatura RPC pozostała bez zmian. Po wdrożeniu API odrzuca anonimowe wywołania (401/42501), co potwierdza obecność funkcji; pełne scenariusze ról potwierdziły wcześniejsze testy pętli zwrotnej. Właściciel zgłosił wszystkie flagi metadanych jako true.

Nowy klient opublikowano jako APK 1.0.2 (2026111201) pod dotychczasowym adresem pobierania; SHA256 `9e185e96030946d38aacd329f067bde709a0f09eea08c518d87781ea70752efc`. Sprawdzenie end-to-end akceptacji na fizycznym urządzeniu oraz testy logowania Google i wyświetlania nazwy pozostają w bramkach urządzeniowych pozostałych funkcji.
