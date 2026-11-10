---
opened: 2026-11-10
---

# F001 · Draft and match player lists remain readable on small screens

## Outcome

An organizer can select players and read both eight-player teams on a small phone without horizontal scrolling or hidden controls. Desktop lists remain bounded instead of stretching names and rankings across the screen. This implements the mobile list layout accepted in the prototype review, not an application-wide redesign.

## Scope

- Draft selection: search above selected and available players in one vertical flow.
- Simple player rows in draft results and match details, preserving their existing interactions.
- Adjacent mobile team columns with centered names; mobile rankings below player names.
- Bounded desktop panels with names and rankings on one line.
- Compact feature headers and actions needed to retain room for the full squads.

## Out of scope

- Home screen, navigation behavior, unrelated player lists, and tournament redesign.
- Draft algorithms, ranking calculations, authorization, persistence, and database changes.
- General visual polish, new product features, and changing player-count limits.

## Acceptance

- At 360 × 640, draft selection shows search above selected and available lists in a single vertical scroll area, with generation reachable.
- At default text scale, actual match details show eight players in each adjacent team column within the 360 × 640 viewport without clipped names or rankings.
- Actual draft results show both eight-player rosters within that viewport, with proposal navigation and acceptance reachable.
- At 1440 and 2560 pixels, desktop player names and rankings share a row inside bounded panels: 600 px for selection, 900 px for draft results, and 1000 px for match content.
- Existing draft search widget tests retain their keyboard, software-keyboard, focus, and selection assertions.
- A reproducible Flutter render with fake repository data supplies phone and desktop screenshots of these real screens; HTML mockups are not implementation evidence.

## Notes

Preserve mobile row typography (Open Sans 14 px names, 11 px rankings), subtle dividers, and readable wrapping. Longer names or enlarged text may scroll rather than truncate. Keep the accepted player rows; the simplified prototype header is a reference, not authority to rebuild global navigation. Proof commands, fixtures, interaction checks, and artifact requirements are in `notes.md`.
