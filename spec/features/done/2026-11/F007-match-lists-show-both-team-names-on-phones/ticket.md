---
opened: 2026-11-10
landed: 2026-11-11
---

# F007 · Match lists show both team names on phones

## Outcome

Phone match lists show both team names instead of truncating the away label to “G…”. Each team has its own row with its matching color and score, so the result stays easy to read. Desktop cards retain their current horizontal presentation.

## Scope

- Fix the shared match-list card used by squad and player match history.
- Preserve dates, colors, result values, missing-result state, and whole-card navigation.
- Keep unselected-team messaging readable on narrow layouts.
- Add realistic responsive and route tests plus actual Flutter page evidence.

## Out of scope

- Match details, player rows, tournament-specific cards, ranking, and persistence.
- Authentication, launcher branding, global navigation, and result editing.

## Acceptance

- GOSPODARZE and GOŚCIE are both fully visible on a 360-pixel phone in the real shell.
- Each home/away score remains aligned with the correct team's name and color, including 14 : 5 and 8 : 16.
- Long custom names receive independent space without the home name consuming the away label's width.
- Missing results and unselected teams do not overflow at narrow widths or larger text sizes.
- Tapping either team row opens the original match-details route with the correct squad and match IDs.
- A real Flutter phone frame demonstrates the fix; desktop retains the current horizontal card layout.

## Notes

The current shared MatchTile puts both names into one single-line rich text beside two 40-pixel score boxes. The second name therefore disappears first. Use the card's actual available width, not assumptions about the full viewport. Test 320/360/390-pixel widths and Android insets. Do not copy real player or match data from the user's screenshot into public evidence.
