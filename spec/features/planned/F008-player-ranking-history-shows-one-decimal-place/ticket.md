---
opened: 2026-11-10
---

# F008 · Player ranking history shows one decimal place

## Outcome

Player ranking history displays readable values with one decimal place instead of exposing long floating-point fractions. This changes display precision only; historical ranking events and calculations keep their original precision.

## Scope

- Format ranking values and deltas shown in player history consistently.
- Include history chart labels and tooltips where they expose the same values.
- Cover positive, negative, integer, zero, and long-fraction examples with presentation tests.

## Out of scope

- Ranking formulas, event deltas, stored values, migrations, and corrections to historical data.
- Player-list redesign or changing the accepted ranking precision on unrelated screens.

## Acceptance

- A history value such as 79.93456789 displays as 79.9 rather than its raw fraction.
- Integer and zero history values retain exactly one decimal place.
- Positive and negative deltas retain their meaning and use the same one-decimal precision.
- Visible history labels and tooltips use consistent precision.
- Formatting does not mutate the source entry or change ranking calculations.
