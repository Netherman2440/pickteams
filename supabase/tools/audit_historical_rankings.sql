-- COUNTS ONLY. Existing authorized authenticated psql connection only.
-- Pin this file's SHA256 and candidate commit before a separately authorized run.
-- Required private inputs: authorized_squad_id, expected_caller_id (UUIDs).
-- No access creation, role/JWT changes, migration, repair, or backfill.
-- Counts cover ONE authorized squad under existing RLS, not global inventory.
-- Preserved legacy inputs do not prove exact old generation-time fidelity.
\set ON_ERROR_STOP on
begin transaction read only;
set local statement_timeout = '30s';
\if :{?authorized_squad_id}
\else
\echo 'STOP: required private squad scope is absent. No inventory produced.'
rollback;
-- psql has no portable nonzero quit argument. A fixed read-only error exits 3.
select 1 / 0 as audit_scope_rejected;
\quit
\endif
\if :{?expected_caller_id}
\else
\echo 'STOP: required private caller scope is absent. No inventory produced.'
rollback;
select 1 / 0 as audit_scope_rejected;
\quit
\endif

-- CASE prevents invalid private input from appearing in UUID cast errors.
select coalesce(
  current_user = 'authenticated'
  and auth.uid() is not null
  and auth.uid() = (case when :'expected_caller_id' ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    then :'expected_caller_id' end)::uuid
  and current_setting('transaction_read_only') = 'on'
  and current_setting('row_security') = 'on'
  and not exists (select 1 from pg_roles
    where rolname in (current_user, session_user) and (rolsuper or rolbypassrls))
  and (select count(*) = 10 from pg_class c where c.oid in (
    'public.matches'::regclass, 'public.ranking_history'::regclass,
    'public.team_players'::regclass, 'public.drafts'::regclass,
    'public.draft_payloads'::regclass, 'public.user_squads'::regclass,
    'public.squads'::regclass, 'public.tournaments'::regclass,
    'public.tournament_drafts'::regclass, 'public.tournament_draft_payloads'::regclass)
    and c.relrowsecurity and not pg_has_role(current_user, c.relowner, 'USAGE'))
  and exists (select 1 from public.user_squads us
    join public.squads s using (squad_id)
    where us.user_id = auth.uid()
      and us.squad_id = (case when :'authorized_squad_id' ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
        then :'authorized_squad_id' end)::uuid), false) as scope_ok \gset audit_
\if :audit_scope_ok
select 1 as scope_guard_passed, 1 as single_squad_only,
  1 as existing_rls_caller_only, 1 as transaction_read_only;

select count(*) as visible_matches,
  count(*) filter (where home_score is not null or away_score is not null) as scored_matches,
  count(*) filter (where jsonb_typeof(to_jsonb(m)->'play_with_substitute') = 'boolean') as explicit_substitute_options,
  count(*) filter (where jsonb_typeof(to_jsonb(m)->'score_meta'->'draft_rankings') = 'object') as matches_with_preserved_vectors
from public.matches m where m.squad_id = :'authorized_squad_id'::uuid;

select count(*) as match_history_inputs,
  count(*) filter (where r.change is not null) as inputs_with_result_delta,
  count(*) filter (where r.ranking is null) as null_inputs
from public.ranking_history r join public.matches m using (match_id)
where m.squad_id = :'authorized_squad_id'::uuid;

-- Only tournament creation inputs (match_id IS NULL) cover legacy gaps.
with roster as (
  select case when coalesce(to_jsonb(m)->'score_meta' ? 'draft_rankings', false)
    then jsonb_typeof(to_jsonb(m)->'score_meta'->'draft_rankings'->tp.player_id::text) = 'number'
    else exists (select 1 from public.ranking_history r
      where r.match_id = tp.match_id and r.player_id = tp.player_id) end as match_input,
    not coalesce(to_jsonb(m)->'score_meta' ? 'draft_rankings', false)
    and exists (select 1 from public.ranking_history r
      join public.tournaments t on t.tournament_id = r.tournament_id
      where t.squad_id = m.squad_id and t.tournament_id = m.tournament_id
        and r.match_id is null and r.player_id = tp.player_id) as tournament_input
  from public.team_players tp join public.matches m using (match_id)
  where m.squad_id = :'authorized_squad_id'::uuid
)
select count(*) as roster_rows,
  count(*) filter (where match_input) as match_input_available,
  count(*) filter (where not coalesce(match_input, false) and tournament_input) as tournament_input_only,
  count(*) filter (where not coalesce(match_input, false) and not tournament_input) as no_preserved_input
from roster;

-- Include both proposal writers. Exclude metadata rows and foreign/orphan
-- payloads by joining through drafts to the authorized match/tournament.
with scoped_payloads as (
  select d.proposals from public.draft_payloads d
  join public.drafts dr using (draft_id)
  join public.matches m on m.match_id = dr.match_id
  where m.squad_id = :'authorized_squad_id'::uuid and dr.squad_id = m.squad_id
  union all
  select d.proposals from public.tournament_draft_payloads d
  join public.tournament_drafts dr using (tournament_draft_id)
  join public.tournaments t using (tournament_id)
  where t.squad_id = :'authorized_squad_id'::uuid and dr.squad_id = t.squad_id
), proposals as (
  select p from scoped_payloads d
  cross join lateral jsonb_array_elements(d.proposals) p
  where jsonb_typeof(p->'teams') = 'array' and not p ? '_meta'
)
select count(*) as visible_proposals,
  count(*) filter (where jsonb_typeof(p->'rankings') = 'object') as proposals_with_score_objects,
  count(*) filter (where jsonb_typeof(p->'play_with_substitute') = 'boolean') as proposals_with_substitute_options,
  count(*) filter (where jsonb_typeof(p->'rankings') = 'object'
    and not exists (
      select 1 from jsonb_array_elements(p->'teams') team
      cross join lateral jsonb_array_elements_text(team) player_id
      where jsonb_typeof(p->'rankings'->player_id) is distinct from 'number'
    )) as proposals_with_all_numeric_inputs
from proposals;
rollback;
\else
\echo 'STOP: caller, role, RLS, membership, or private squad scope did not match. No inventory produced.'
rollback;
select 1 / 0 as audit_scope_rejected;
\quit
\endif
