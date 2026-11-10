---
opened: 2026-11-10
---

# F003 · Match actions use one menu at every screen width

## Outcome

Desktop match details uses the same header action menu already accepted on phones. There is no longer a separate desktop Edit/Delete pair or action row below the teams. Player layout and the score-placement breakpoint remain unchanged.

## Scope

- Extend the existing match action menu to every width.
- Remove the obsolete standalone action presentation and its unused helper.
- Preserve action availability, callbacks, permissions, confirmations, and visible editing controls.

## Out of scope

- New actions, changed match rules, player-row redesign, and global navigation.
- Changes to draft screens, ranking logic, persistence, or database schema.

## Acceptance

- Phone and desktop view mode expose one header menu and no standalone modifying controls.
- The existing state/role matrix verifies the same applicable action sets through the menu at both widths.
- Save/Cancel and score entry continue working across the fourteen existing breakpoint cases.
- Real Flutter phone and desktop frames show the menu closed and open, with player layouts unchanged.

## Notes

This is a direct, local follow-up to the reviewed menu, not a new interaction design. Run formatting, analysis, full coverage, and JS production/fixture builds; retain exact-commit evidence in `.limen/proof/f003/`. Keep physical Android/APK and Wasm limits explicit. The prior desktop-controls exclusion is superseded only for this action-menu presentation.
