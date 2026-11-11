---
opened: 2026-11-10
landed: 2026-11-11
---

# F004 · Match scores stay centered on phones

## Outcome

A phone shows the match score centered above both teams, not shifted into the away team's column by the match date. Existing player rows, rankings, team headings, and desktop layout remain accepted as-is.

## Scope

- Fix the compact match-header alignment, including saved multi-digit results and missing results.
- Keep score entry usable at the same widths, including a visible keyboard and Android insets.
- Extend the real-page fixture and geometric tests to cover the reported result.

## Out of scope

- Player-list redesign, global navigation, action-menu changes, and ranking logic.
- Persistence, database changes, launcher branding, and authentication.

## Acceptance

- A saved 14 : 5 score is centered within the padded match content at realistic phone widths.
- Missing results and larger scores do not overflow or overlap the date.
- Score editing and saving work across all fourteen existing viewport breakpoints.
- Desktop retains its existing score placement between the two teams.
- Real Flutter closed/view and editing frames show the correction at 360 × 640, without changing the player-row design.

## Notes

The reported screenshot is on Android. The compact header currently puts the date and score in a single centered Row, which centers their combined width rather than the score itself. Avoid a height increase that needlessly pushes the accepted eight-player rows out of the phone viewport.
