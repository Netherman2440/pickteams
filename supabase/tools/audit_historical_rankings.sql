-- Read-only inventory, under the caller's existing RLS. No service-role access.
-- Counts are limited to records visible to that caller, not all production.
-- Works before or after the issue #60 migration. No names or IDs are exported.
\set ON_ERROR_STOP on
begin transaction read only;
show transaction_read_only;
select current_user, auth.uid() is not null as authenticated;
select count(*) as visible_matches,
  count(*) filter (where home_score is not null or away_score is not null) as scored,
  count(*) filter (where to_jsonb(m)->'play_with_substitute' in ('true'::jsonb, 'false'::jsonb)) as explicit_substitute_option
from public.matches m;
select count(*) as visible_match_inputs,
  count(*) filter (where change is not null) as inputs_with_result_delta,
  count(*) filter (where ranking is null) as null_inputs
from public.ranking_history where match_id is not null;
select count(*) as roster_rows,
  count(*) filter (where exists (select 1 from public.ranking_history r
    where r.player_id = tp.player_id and r.match_id = tp.match_id)) as match_input_available,
  count(*) filter (where not exists (select 1 from public.ranking_history r
    where r.player_id = tp.player_id and r.match_id = tp.match_id)
    and exists (select 1 from public.ranking_history r
      where r.player_id = tp.player_id and r.tournament_id = m.tournament_id)) as tournament_input_only,
  count(*) filter (where not exists (select 1 from public.ranking_history r
    where r.player_id = tp.player_id and (r.match_id = tp.match_id
      or (m.tournament_id is not null and r.tournament_id = m.tournament_id)))) as no_preserved_input
from public.team_players tp join public.matches m using (match_id);
select count(*) as visible_proposals,
  count(*) filter (where jsonb_typeof(p->'rankings') = 'object') as proposals_with_scores,
  count(*) filter (where jsonb_typeof(p->'play_with_substitute') = 'boolean') as proposals_with_substitute_option
from public.draft_payloads d cross join lateral jsonb_array_elements(d.proposals) p
where not p ? '_meta';
rollback;
