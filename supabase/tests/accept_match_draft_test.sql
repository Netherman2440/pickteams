-- Run against the migrated disposable database. Every fixture rolls back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id, email) values
 ('10000000-0000-0000-0000-000000000001','owner@example.test'),
 ('10000000-0000-0000-0000-000000000002','admin@example.test'),
 ('10000000-0000-0000-0000-000000000003','member@example.test'),
 ('10000000-0000-0000-0000-000000000004','foreign@example.test');
insert into public.squads(squad_id, owner_id, name, visibility) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Local', 'private'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000004','Foreign', 'private');
insert into public.user_squads(user_id, squad_id, role) values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner'),
 ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','admin'),
 ('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','member'),
 ('10000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000002','owner');
insert into public.players(player_id, squad_id, name, base_score, score)
 select ('30000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
 '20000000-0000-0000-0000-000000000001', 'Player ' || i, 50, 50 + i from generate_series(1,4) i;
insert into public.players(player_id, squad_id, name, base_score, score) values
 ('30000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000002','Foreign player',50,50);

create function pg_temp.payload() returns jsonb language sql as $$
 select '{"home":["30000000-0000-0000-0000-000000000001","30000000-0000-0000-0000-000000000002"],
 "away":["30000000-0000-0000-0000-000000000003","30000000-0000-0000-0000-000000000004"],
 "selected_index":0,"win_rate_matrix":{},"proposals":[{"_meta":{"seed":123}},
 {"teams":[["30000000-0000-0000-0000-000000000001","30000000-0000-0000-0000-000000000002"],
 ["30000000-0000-0000-0000-000000000003","30000000-0000-0000-0000-000000000004"]]},
 {"teams":[["30000000-0000-0000-0000-000000000001","30000000-0000-0000-0000-000000000003"],
 ["30000000-0000-0000-0000-000000000002","30000000-0000-0000-0000-000000000004"]]}]}'::jsonb;
$$;
create function pg_temp.accept(request uuid, target uuid default null, payload jsonb default pg_temp.payload())
 returns uuid language sql as $$
 select public.accept_match_draft(request,'20000000-0000-0000-0000-000000000001',target,payload);
$$;
create function pg_temp.reject(statement text, expected text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlerrm not like '%' || expected || '%' then raise; end if;
    return;
  end;
  raise exception 'Expected rejection: %', expected;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$
declare id uuid;
begin
 id := pg_temp.accept('40000000-0000-0000-0000-000000000001');
 assert (select count(*) from matches) = 1, 'One match';
 assert (select count(*) from teams) = 2, 'Two teams';
 assert (select count(*) from team_players) = 4, 'Complete roster';
 assert (select count(*) from ranking_history where change is null) = 4, 'Pending ranking snapshots';
 assert not exists (select 1 from ranking_history r join players p using(player_id) where r.ranking <> p.score), 'Snapshot ranking';
 assert (select proposals_count from drafts) = 2, 'All proposals';
 assert (select proposals from draft_payloads) = pg_temp.payload()->'proposals', 'Payload including seed';
 assert (select home_win_prob from matches) is not null, 'Existing probability calculation';
 perform set_config('test.match_id',id::text,true);
end;
$$;

-- Failure at the last payload write must roll back match, teams AND snapshots.
reset role;
create function pg_temp.fail_payload() returns trigger language plpgsql as $$
begin raise exception 'injected payload failure'; end;
$$;
create trigger fail_payload before insert or update on draft_payloads for each row execute function pg_temp.fail_payload();
set local role authenticated;
select pg_temp.reject($q$select pg_temp.accept('40000000-0000-0000-0000-000000000002')$q$, 'injected payload failure');
select pg_temp.reject($q$select pg_temp.accept('40000000-0000-0000-0000-000000000003',current_setting('test.match_id')::uuid,
 jsonb_set(jsonb_set(pg_temp.payload(),'{home}',pg_temp.payload()->'away'),'{away}',pg_temp.payload()->'home'))$q$, 'injected payload failure');
do $$ begin
 assert (select count(*) from matches) = 1;
 assert (select count(*) from teams) = 2;
 assert (select count(*) from team_players) = 4;
 assert (select count(*) from ranking_history) = 4;
 assert (select count(*) from drafts) = 1;
 assert (select proposals from draft_payloads) = pg_temp.payload()->'proposals';
 assert (select count(*) from team_players tp join teams t using(team_id) where t.side = 'home'
   and tp.player_id in ('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002')) = 2, 'Failed redraw leaves roster unchanged';
end $$;
reset role;
drop trigger fail_payload on draft_payloads;
set local role authenticated;
-- Retry the failed new acceptance, then accept a redraw without replacing rankings.
select pg_temp.accept('40000000-0000-0000-0000-000000000002');
select pg_temp.accept('40000000-0000-0000-0000-000000000003',current_setting('test.match_id')::uuid,
 jsonb_set(jsonb_set(pg_temp.payload(),'{home}',pg_temp.payload()->'away'),'{away}',pg_temp.payload()->'home'));
-- Re-running redraw, even with no request ID, does not duplicate snapshots.
select pg_temp.accept(null,current_setting('test.match_id')::uuid,
 jsonb_set(jsonb_set(pg_temp.payload(),'{home}',pg_temp.payload()->'away'),'{away}',pg_temp.payload()->'home'));
do $$ begin
 assert (select count(*) from matches) = 2;
 assert (select count(*) from teams) = 4;
 assert (select count(*) from team_players) = 8;
 assert (select count(*) from ranking_history) = 8;
 assert (select count(*) from drafts) = 2;
 assert (select count(*) from draft_payloads) = 2;
end $$;
-- Malformed rosters/proposals and foreign-squad data cannot be accepted.
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid(),null,jsonb_set(pg_temp.payload(),'{home}',pg_temp.payload()->'away'))$q$, 'exactly once');
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid(),null,jsonb_set(pg_temp.payload(),'{proposals}','[]'))$q$, 'Invalid proposal selection');
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid(),null,replace(pg_temp.payload()::text,'30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000005')::jsonb)$q$, 'belong to the match squad');
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid(),'50000000-0000-0000-0000-000000000001')$q$, 'Match not available');
update matches set home_score = 1, away_score = 0 where match_id = current_setting('test.match_id')::uuid;
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid(),current_setting('test.match_id')::uuid)$q$, 'with score');
-- Admin succeeds; Member, foreign owner and anonymous fail.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select pg_temp.accept('40000000-0000-0000-0000-000000000004');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid())$q$, 'Only squad owners and admins');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid())$q$, 'Only squad owners and admins');
do $$ begin
 assert (select count(*) from matches) = 0, 'Foreign owner cannot read private matches';
end $$;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.reject($q$select pg_temp.accept(gen_random_uuid())$q$, 'permission denied for function accept_match_draft');
reset role;
do $$ begin
 assert (select count(*) from matches) = 3, 'Only three authorized new acceptances';
 assert (select count(*) from teams) = 6;
 assert (select count(*) from team_players) = 12;
 assert (select count(*) from ranking_history) = 12;
 assert (select count(*) from drafts) = 3;
 assert (select count(*) from draft_payloads) = 3;
 assert to_regclass('public.match_draft_acceptances') is null, 'No acceptance ledger';
 assert not (select prosecdef from pg_proc where oid = 'public.accept_match_draft(uuid,uuid,uuid,jsonb)'::regprocedure), 'Invoker preserves RLS';
end $$;
-- A lost-response retry can create a duplicate; request IDs are accepted and ignored.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$
declare duplicate_id uuid; changed_id uuid; null_id uuid;
begin
 duplicate_id := pg_temp.accept('40000000-0000-0000-0000-000000000001');
 changed_id := pg_temp.accept('40000000-0000-0000-0000-000000000001',null,
   jsonb_set(pg_temp.payload(),'{selected_index}','1'));
 null_id := pg_temp.accept(null);
 assert duplicate_id <> current_setting('test.match_id')::uuid, 'Same request creates a second match';
 assert changed_id <> duplicate_id, 'Same request accepts a different payload';
 assert null_id not in (duplicate_id, changed_id), 'Null request ID is also ignored';
 assert (select count(*) from matches) = 6, 'Every new acceptance creates a complete match';
 assert (select count(*) from teams) = 12;
 assert (select count(*) from team_players) = 24;
 assert (select count(*) from ranking_history) = 24;
 assert (select count(*) from drafts) = 6;
 assert (select count(*) from draft_payloads) = 6;
end $$;
reset role;
rollback;
\echo 'accept_match_draft transaction, retry, role and constraint checks passed'
