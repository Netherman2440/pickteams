# Build

> Coordinator-maintained narrative board. TRACK, NEXT, PARKED and DROPPED are coordinator prose: keep them true in the change that moves feature state. NOW and PROVEN are generated from the feature lanes by `limen land`, `limen ticket done` and `limen board --write`; edit the tickets, not those lines.

TRACK at most three bullets. NEXT one clause per ticket. PROVEN names the last ten landed features, then one count line per month.

Status marks are prose only: 🟠 ACTIVE · 🔴 PLANNED · 🟢 PROVEN · ⚪ DROPPED. Nothing in `limen` treats them as workflow state.

## TRACK

- Rebuild Pickteams for mobile, reworking the existing Flutter web client.

## NOW

<!-- Generated from spec/features/active/ by limen land, limen ticket done and limen board --write. Edit the tickets, not these lines. -->

- `F012-a-match-is-created-only-when-a-proposal-is-accepted` (🟠 ACTIVE): A match is created only when a proposal is accepted; needs Adam since 2026-11-12: Uruchom zatwierdzony accept_match_draft_operator.sql z commitu a8328b3 w SQL Editor właściwego projektu i przekaż flagi gotowości bez danych dostępowych.
- `F010-android-identifies-the-app-as-pickteams` (🟠 ACTIVE): Android identifies the app as Pickteams
- `F006-google-sign-in-returns-to-the-android-app` (🟠 ACTIVE): Google sign-in returns to the Android app
- `F005-android-launcher-uses-the-pickteams-icon` (🟠 ACTIVE): Android launcher uses the Pickteams icon

## NEXT

- Player ranking history shows one decimal place (`F008-player-ranking-history-shows-one-decimal-place`).

## PROVEN

<!-- Generated from spec/features/done/ by limen land, limen ticket done and limen board --write. Edit the tickets, not these lines. -->

- `F015-lineups-keep-a-compact-team-header-while-scrolling` (🟢 PROVEN): Lineups keep a compact team header while scrolling; landed 2026-11-12
- `F014-player-rows-are-shared-and-draft-selection-scrolls-as-one-list` (🟢 PROVEN): Player rows are shared and draft selection scrolls as one list; landed 2026-11-11
- `F013-match-lists-put-the-date-beside-unboxed-team-scores` (🟢 PROVEN): Match lists put the date beside unboxed team scores; landed 2026-11-11
- `F011-player-details-use-one-edit-mode` (🟢 PROVEN): Player details use one edit mode; landed 2026-11-11
- `F009-android-release-builds-use-a-compatible-toolchain` (🟢 PROVEN): Android release builds use a compatible toolchain; landed 2026-11-11
- `F007-match-lists-show-both-team-names-on-phones` (🟢 PROVEN): Match lists show both team names on phones; landed 2026-11-11
- `F004-match-scores-stay-centered-on-phones` (🟢 PROVEN): Match scores stay centered on phones; landed 2026-11-11
- `F003-match-actions-use-one-menu-at-every-screen-width` (🟢 PROVEN): Match actions use one menu at every screen width; landed 2026-11-10
- `F002-match-actions-stay-in-one-menu-on-small-screens` (🟢 PROVEN): Match actions stay in one menu on small screens; landed 2026-11-10
- `F001-draft-and-match-player-lists-remain-readable-on-small-screens` (🟢 PROVEN): Draft and match player lists remain readable on small screens; landed 2026-11-10
- 2026-11: 10 landed. spec/features/done/2026-11/
