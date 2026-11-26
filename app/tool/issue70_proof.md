# Two-team draft tie-breaking (#70)

## Contract and seams

`TwoTeamBalance` is the shared two-team comparator used by both repositories.
It compares the absolute effective ranking difference first, summing persisted
rankings as integer hundredths. The existing substitute adjustment is compared
as a fraction, without rounding or epsilon equality. Only equal primary differences
compare `0.5 * R + 0.5 * E`. On an exact secondary tie, the existing combined
rule/position penalty precedes the stable player-ID signature. Rules and positions
remain soft preferences, as before; the generators still build the same eligible
candidate pools and team sizes. These preferences cannot override the explicit
two-team primary/secondary order. The existing normalized deviation/penalty score
and squared-rank tie-break remain unchanged for three or four teams.

Ranking pairs and appearance pairs each sort independently, descending. Both use
only `min(home.length, away.length)` existing pairs. This preserves the existing
pairing convention: ignore an unmatched value. There is no invented player,
zero partner or additional penalty. Empty pairs score zero; valid generators
require at least one player per team. Primary scoring still includes every player
and the existing odd-team/substitute adjustment.

The ranking editor admits 0..100. The requested fixed ranking denominator remains
**99**, not 100. Rank 0 is accepted without a clamp. Thus R can be **100/99**;
normalization is a fixed scale, not a guarantee of values in [0,1]. The experience
denominator is `max(1, maximum prior appearances in the full input player pool)`.
It does not shrink when a proposal omits the most experienced available player.
Both weights remain exactly 0.5.

`CreateDraftUseCase` loads appearances once before two-team generation. All three
application providers require the real history repository. The session passes the
current match ID for redraw. Tournament drafts with two teams use the same path;
three/four-team drafts do not read history. Stored drafts are restored unchanged.
No experience value enters `Player`, stored drafts or presentation widgets.

`SupabaseDraftExperienceRepository` reads flat `team_players` pages of 250 with
an explicit match foreign-key join. This avoids nested-list truncation and N+1
queries. A unique `(match, player)` set prevents double-counting across pages.
Both scores must be non-null; 0:0 counts. Match chronology follows existing stats:
`played_at`, falling back to `created_at`. Only dates strictly before the draft
cutoff count. For a new draft the cutoff is now; for redraw it is the earlier of
now and the current match date. The current match ID is always excluded, as are
same-time, later and future matches. A redraw performs one current-match lookup
plus paginated membership queries; a new draft needs only the membership queries.
Read/parse errors propagate as failures with their original stack, not zero counts.
No historical writes, schema change or private data access is needed.

## Acceptance map

`test/draft/application/two_team_experience_test.dart` replaces the old
combinatory-only ranking-baseline example with stronger shared checks:

- Both real generators order 90:90 ahead of 100:80 even when the latter has the
  better secondary score. Greedy uses its public candidate-pool setting of one
  to expose all small-fixture partitions; search logic is not changed.
- Real Supabase HTTP repository fixtures provide 40/39/1/0 scored memberships,
  including a 0:0, accepted/no-score and partial-score exclusions, current-match,
  same-date and future exclusions, duplicate rows, and a second page. Application
  providers send these counts to both real generators (default greedy settings
  for this equal-ranked fixture). Balanced E=1/40 beats E=39/40; R=0 and totals
  are 100:100.
- Both generators and the shared comparator compare two true stored-score
  ties at 138.10 per side using experience. Adding 0.01 to B and C makes one
  partition worse by 0.02 and confirms ranking still wins. The direct
  comparator also checks a genuine one-third-cent gap after substitute weighting.
- Independent sorting, exact 50/50 weights, fixed scales with an omitted maximum,
  rank 0, zero/equal experience, unmatched/empty pairs, strict primary ties,
  stable fallback, odd sizes with substitutes on/off, and three/four-team
  experience isolation have direct assertions.
- All application providers propagate failed history reads. New-draft chronology
  and `created_at` fallback have dedicated checks. Existing generator rule,
  position, limit and determinism tests remain in the scoped lane. Existing
  preview lifecycle tests cover read-only generation and redraw behavior.

## Reproduction and evidence

Use the locked dependencies (`flutter pub get --enforce-lockfile`). Run the focused
lane on `test/draft/application`, `test/draft/infrastructure/repositories` and
`test/draft/presentation/draft_results_page_rules_test.dart`. Run scoped analysis
and changed-file format checks. After committing the clean candidate, run one
complete native `flutter test --no-pub --coverage --reporter expanded` with a
900-second timeout.

Each Flutter/Dart validation command requires its own immediate nonblocking
`flock -n -E75 /tmp/pickteams-flutter-validation.lock`, held through execution,
and `MemAvailable >= 2621440 KiB`. A denied admission ends this worker without
polling. Raw logs, source identities, coverage, diff checks and final handoff are
copied to the coordinator's `worker-evidence/<source-sha>/` directory. Logs retain
failed probes as well as final results. No UI screenshot is required: no widgets,
labels, experience fields or ranking-update behavior change.
