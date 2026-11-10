---
opened: 2026-11-10
landed: 2026-11-10
---

# F002 · Match actions stay in one menu on small screens

## Outcome

On a narrow screen, an organizer reaches every applicable match action from one clearly labelled overflow menu in the match header. The separate Edit/Delete icons and green action rows no longer take space away from the teams. Wide-screen controls and the accepted player lists remain unchanged.

## Scope

- Match-details actions only: score entry, team editing, draft preview, redraft, rematch, team selection changes, and deletion where applicable.
- One narrow-layout overflow entry point using the real available content width.
- Existing action callbacks, permission checks, and destructive confirmations.
- Visible Save and Cancel controls while a score or team edit is active.

## Out of scope

- Draft-screen, home-screen, global navigation, or player-row redesign.
- Changes to ranking, persistence, match rules, roles, or database schema.
- Moving desktop controls or adding new match operations.

## Acceptance

- At 360 × 640, viewing a match exposes one action-menu trigger, with neither standalone Edit/Delete icons nor action rows below the rosters.
- The open menu contains every action allowed by the existing match state and user role, including Edit/Delete for organizers but no modifying action for read-only users.
- Selecting a menu action reaches the existing operation; deletion and rematch still require their existing confirmation.
- During editing, Save and Cancel remain visible and finish or discard edits without reopening the action menu.
- At 768 px and around the actual content breakpoint, score entry still exposes both reachable inputs and saves the entered score.
- At wide desktop sizes, the existing standalone icons and action rows remain available under their original conditions.

## Notes

Preserve the readable eight-player columns and centered headings implemented earlier. Use real Flutter page tests and credential-free fixtures; capture closed/open menu states at 360 × 640 and the desktop view. Run formatting, analysis, the full coverage suite, and a JS web build on the clean committed tree. Native-device and Wasm checks remain outside this slice; report them honestly. No production services or writes are needed.
