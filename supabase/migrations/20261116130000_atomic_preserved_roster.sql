-- Issue #60: one transaction for tournament-match roster/vector edits.
-- SECURITY INVOKER keeps existing table RLS; explicit owner/admin authorization
-- and a match row lock also protect score races. No grants, history events,
-- current-score reads, backfill, or ranking-formula changes.
-- The last successful operation is a bounded receipt/version in score_meta.
-- Exact replay is read-only; older operations conflict after a later edit.
create function public.update_preserved_match_roster(
  p_match_id uuid,
  p_request_id uuid,
  p_home jsonb,
  p_away jsonb,
  p_rankings jsonb,
  p_expected_version text
) returns void
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  target public.matches%rowtype;
  ids uuid[];
  home_id uuid;
  away_id uuid;
  receipt jsonb;
  command jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select * into target from public.matches where match_id = p_match_id for update;
  if not found or not exists (
    select 1 from public.user_squads where squad_id = target.squad_id
      and user_id = auth.uid() and role in ('owner', 'admin')
  ) then
    raise exception 'Only squad owners and admins can edit rosters' using errcode = '42501';
  end if;
  if p_request_id is null or jsonb_typeof(p_home) is distinct from 'array'
      or jsonb_typeof(p_away) is distinct from 'array'
      or jsonb_typeof(p_rankings) is distinct from 'object' then
    raise exception 'Complete preserved roster command required';
  end if;
  command := jsonb_build_object('id', p_request_id, 'home', p_home,
    'away', p_away, 'rankings', p_rankings, 'base', p_expected_version);
  receipt := target.score_meta->'_roster_operation';
  if receipt->>'id' = p_request_id::text then
    if receipt is distinct from command then
      raise exception 'Roster request ID reused with different inputs';
    end if;
    return; -- Lost-response replay, including after a result was entered.
  end if;
  if target.home_score is not null or target.away_score is not null then
    raise exception 'Cannot update teams for a match with score';
  end if;
  if receipt->>'id' is distinct from p_expected_version then
    raise exception 'Roster changed; reload before a different edit' using errcode = '40001';
  end if;
  if target.tournament_id is null
      or jsonb_typeof(target.score_meta->'draft_rankings') is distinct from 'object' then
    raise exception 'Preserved tournament match vector required';
  end if;
  select coalesce(array_agg(value::uuid), '{}'::uuid[]) into ids
    from jsonb_array_elements_text(p_home || p_away);
  if cardinality(ids) <> (select count(distinct id) from unnest(ids) id)
      or exists (select 1 from unnest(ids) id where id is null) then
    raise exception 'Each player must occur exactly once';
  end if;
  if (select count(*) from public.players where squad_id = target.squad_id
        and player_id = any(ids)) <> cardinality(ids) then
    raise exception 'Players must belong to the match squad' using errcode = '42501';
  end if;
  if (select count(*) from jsonb_object_keys(p_rankings)) <> cardinality(ids)
      or exists (select 1 from unnest(ids) id
        where jsonb_typeof(p_rankings->id::text) is distinct from 'number') then
    raise exception 'Exact numeric input vector required';
  end if;
  -- Retained players cannot be silently reranked. Additions use the frozen
  -- operation input, not a new read of players.score at retry/commit time.
  if exists (
    select 1 from public.team_players tp where tp.match_id = p_match_id
      and tp.player_id = any(ids)
      and (jsonb_typeof(target.score_meta->'draft_rankings'->tp.player_id::text) is distinct from 'number'
        or target.score_meta->'draft_rankings'->tp.player_id::text is distinct from p_rankings->tp.player_id::text)
  ) then
    raise exception 'Retained player input changed';
  end if;
  select team_id into home_id from public.teams where match_id = p_match_id and side = 'home';
  select team_id into away_id from public.teams where match_id = p_match_id and side = 'away';
  if home_id is null or away_id is null then
    raise exception 'Both match teams required';
  end if;
  delete from public.team_players where match_id = p_match_id;
  insert into public.team_players(match_id, team_id, player_id, tournament_id)
    select p_match_id, home_id, value::uuid, target.tournament_id from jsonb_array_elements_text(p_home)
    union all
    select p_match_id, away_id, value::uuid, target.tournament_id from jsonb_array_elements_text(p_away);
  update public.matches set score_meta = target.score_meta ||
    jsonb_build_object('draft_rankings', p_rankings, '_roster_operation', command)
    where match_id = p_match_id;
  perform public.refresh_match_win_probability(p_match_id);
end;
$$;
comment on function public.update_preserved_match_roster(uuid, uuid, jsonb, jsonb, jsonb, text) is
  'Atomic preserved tournament roster edit; existing RLS and owner/admin membership required. Exact last-operation replay is a no-op.';
notify pgrst, 'reload schema';
