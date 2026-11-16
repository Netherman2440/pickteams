-- Preserve generator inputs, not acceptance-time players.score. The nullable
-- option distinguishes old matches whose substitute setting was not stored.
-- No historical data is rewritten. Result delta math and RLS are unchanged.
alter table public.matches add column play_with_substitute boolean;
comment on column public.matches.play_with_substitute is
  'Explicit generation option. NULL means the legacy writer did not preserve it.';

create or replace function public.accept_match_draft(
  p_request_id uuid, p_squad_id uuid, p_match_id uuid, p_payload jsonb
) returns uuid
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  target public.matches%rowtype;
  result_id uuid;
  draft_id_value uuid;
  home_id uuid;
  away_id uuid;
  player_ids uuid[];
  proposal_ids uuid[];
  proposal jsonb;
  proposals jsonb;
  proposal_count integer := 0;
  selected_proposal jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_squads where squad_id = p_squad_id
      and user_id = auth.uid() and role in ('owner', 'admin')
  ) then raise exception 'Only squad owners and admins can accept drafts' using errcode = '42501'; end if;
  if jsonb_typeof(p_payload->'home') is distinct from 'array'
     or jsonb_typeof(p_payload->'away') is distinct from 'array'
     or jsonb_typeof(p_payload->'proposals') is distinct from 'array'
     or jsonb_typeof(p_payload->'win_rate_matrix') is distinct from 'object'
     or jsonb_array_length(p_payload->'home') = 0
     or jsonb_array_length(p_payload->'away') = 0 then
    raise exception 'Complete teams and proposals are required';
  end if;
  select array_agg(value::uuid order by value::uuid) into player_ids
    from jsonb_array_elements_text((p_payload->'home') || (p_payload->'away'));
  if cardinality(player_ids) <> (select count(distinct id) from unnest(player_ids) id)
     or exists (select 1 from unnest(player_ids) id where id is null) then
    raise exception 'A player must occur exactly once';
  end if;
  if (select count(*) from public.players where player_id = any(player_ids) and squad_id = p_squad_id)
      <> cardinality(player_ids) then
    raise exception 'Players must belong to the match squad' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload->'rankings') is distinct from 'object'
     or jsonb_typeof(p_payload->'play_with_substitute') is distinct from 'boolean' then
    raise exception 'Generation rankings and explicit substitute option are required';
  end if;
  if (select count(*) from jsonb_object_keys(p_payload->'rankings')) <> cardinality(player_ids)
     or exists (
       select 1 from unnest(player_ids) id
       where jsonb_typeof(p_payload->'rankings'->id::text) is distinct from 'number'
     ) then
    raise exception 'A numeric generation ranking is required for every player';
  end if;
  proposals := p_payload->'proposals';
  for proposal in select value from jsonb_array_elements(proposals) loop
    if proposal ? '_meta' then continue; end if;
    if jsonb_typeof(proposal->'teams') is distinct from 'array'
       or jsonb_array_length(proposal->'teams') <> 2
       or jsonb_typeof(proposal->'teams'->0) is distinct from 'array'
       or jsonb_typeof(proposal->'teams'->1) is distinct from 'array'
       or jsonb_array_length(proposal->'teams'->0) = 0
       or jsonb_array_length(proposal->'teams'->1) = 0 then
      raise exception 'Each proposal needs two complete teams';
    end if;
    select array_agg(value::uuid order by value::uuid) into proposal_ids
      from jsonb_array_elements_text((proposal->'teams'->0) || (proposal->'teams'->1));
    if proposal_ids is distinct from player_ids then
      raise exception 'All proposals must contain the same players';
    end if;
    if proposal->'rankings' is distinct from p_payload->'rankings'
       or proposal->'play_with_substitute' is distinct from p_payload->'play_with_substitute' then
      raise exception 'All proposals must preserve the same generation inputs';
    end if;
    if proposal_count = (p_payload->>'selected_index')::integer then
      selected_proposal := proposal;
    end if;
    proposal_count := proposal_count + 1;
  end loop;
  if proposal_count not between 1 and 20 or selected_proposal is null then
    raise exception 'Invalid proposal selection';
  end if;

  if p_match_id is null then
    insert into public.matches(squad_id) values (p_squad_id) returning * into target;
  else
    select * into target from public.matches where match_id = p_match_id and squad_id = p_squad_id for update;
    if not found then raise exception 'Match not available' using errcode = '42501'; end if;
    if target.home_score is not null or target.away_score is not null then
      raise exception 'Cannot update teams for a match with score';
    end if;
  end if;
  result_id := target.match_id;
  update public.matches set play_with_substitute = (p_payload->>'play_with_substitute')::boolean
    where match_id = result_id;
  insert into public.teams(match_id, tournament_id, side, color)
    values (result_id, target.tournament_id, 'home', '#FFFFFF')
    on conflict (match_id, side) do update set match_id = excluded.match_id returning team_id into home_id;
  insert into public.teams(match_id, tournament_id, side, color)
    values (result_id, target.tournament_id, 'away', '#000000')
    on conflict (match_id, side) do update set match_id = excluded.match_id returning team_id into away_id;
  delete from public.team_players where match_id = result_id;
  insert into public.team_players(match_id, team_id, player_id, tournament_id)
    select result_id, home_id, value::uuid, target.tournament_id from jsonb_array_elements_text(p_payload->'home')
    union all
    select result_id, away_id, value::uuid, target.tournament_id from jsonb_array_elements_text(p_payload->'away');
  delete from public.ranking_history where match_id = result_id and not (player_id = any(player_ids));
  insert into public.ranking_history(player_id, match_id, ranking)
    select id, result_id, (p_payload->'rankings'->>id::text)::double precision
    from unnest(player_ids) id
    on conflict (player_id, match_id) where match_id is not null
    do update set ranking = excluded.ranking;
  perform public.refresh_match_win_probability(result_id);
  insert into public.drafts(squad_id, match_id, status, team_count, proposals_count)
    values (p_squad_id, result_id, 'completed', 2, proposal_count)
    on conflict (match_id) do update set status = 'completed', team_count = 2,
      proposals_count = excluded.proposals_count, error_message = null, updated_at = now()
    returning draft_id into draft_id_value;
  insert into public.draft_payloads(draft_id, proposals, win_rate_matrix)
    values (draft_id_value, proposals, p_payload->'win_rate_matrix')
    on conflict (draft_id) do update set proposals = excluded.proposals,
      win_rate_matrix = excluded.win_rate_matrix, updated_at = now();
  return result_id;
end;
$$;
revoke all on function public.accept_match_draft(uuid, uuid, uuid, jsonb) from public, anon;
grant execute on function public.accept_match_draft(uuid, uuid, uuid, jsonb) to authenticated;
