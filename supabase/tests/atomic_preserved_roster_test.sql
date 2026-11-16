-- Run with psql -X -v ON_ERROR_STOP=1 -f this-file on a disposable migrated DB.
\set ON_ERROR_STOP on
begin;
\ir fixtures/preserved_roster.sql
do $$ declare fn regprocedure := 'public.update_preserved_match_roster(uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure;
begin
 assert not (select prosecdef from pg_proc where oid=fn), 'SECURITY INVOKER';
 assert not has_function_privilege('anon',fn,'EXECUTE'), 'Anonymous RPC execution revoked';
 assert has_function_privilege('authenticated',fn,'EXECUTE'), 'Authenticated RPC execution granted';
 assert not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   where p.oid=fn and a.grantee=0 and a.privilege_type='EXECUTE'), 'No PUBLIC execution';
end $$;
create function pg_temp.ids(variadic n integer[]) returns jsonb language sql as $$
 select coalesce(jsonb_agg('30000000-0000-0000-0000-' || lpad(i::text,12,'0')), '[]') from unnest(n) i;
$$;
create function pg_temp.ranks(n integer[], scores numeric[]) returns jsonb language sql as $$
 select coalesce(jsonb_object_agg('30000000-0000-0000-0000-' || lpad(n[i]::text,12,'0'), scores[i]),'{}')
 from generate_subscripts(n,1) i;
$$;
create function pg_temp.edit(n integer, home jsonb default pg_temp.ids(1,2), away jsonb default pg_temp.ids(3,4),
 ranks jsonb default pg_temp.ranks(array[1,2,3,4],array[90,52,53,94]), base integer default null)
 returns void language sql as $$
 select public.update_preserved_match_roster('40000000-0000-0000-0000-000000000001',
 ('90000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,home,away,ranks,
 case when base is not null then '90000000-0000-0000-0000-' || lpad(base::text,12,'0') end);
$$;
create function pg_temp.state() returns jsonb language sql as $$
 select jsonb_build_object('matches',(select jsonb_agg(to_jsonb(m) order by match_id) from matches m),
 'roster',(select jsonb_agg(to_jsonb(tp) order by player_id) from team_players tp),
 'teams',(select jsonb_agg(to_jsonb(t) order by team_id) from teams t),
 'history',(select jsonb_agg(to_jsonb(r)) from ranking_history r),
 'players',(select jsonb_agg(to_jsonb(p) order by player_id) from players p));
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
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select pg_temp.reject('select pg_temp.edit(1)', 'Only squad owners and admins');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select pg_temp.reject('select pg_temp.edit(1)', 'Only squad owners and admins');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.reject('select pg_temp.edit(1)', 'permission denied for function update_preserved_match_roster');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select pg_temp.reject('select pg_temp.edit(1)', 'permission denied for function update_preserved_match_roster');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.reject('select pg_temp.edit(1)', 'Not authenticated');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('test.before',pg_temp.state()::text,true);
-- Overflow is valid JSONB numeric syntax but cannot be read as a finite double.
select pg_temp.reject('select pg_temp.edit(1,ranks=>pg_temp.ranks(array[1,2,3,4],array[1e400,52,53,94]))', 'finite double');
select pg_temp.reject('select pg_temp.edit(1,ranks=>pg_temp.ranks(array[1,2,3,4],array[-1e400,52,53,94]))', 'finite double');
do $$ begin assert pg_temp.state()=current_setting('test.before')::jsonb, 'Overflow rejects without any mutation'; end $$;
-- Fail the authoritative metadata update AFTER roster additions have executed.
reset role;
create function pg_temp.fail_vector() returns trigger language plpgsql as $$
begin raise exception 'injected vector failure'; end;
$$;
create trigger fail_vector before update of score_meta on matches for each row execute function pg_temp.fail_vector();
set local role authenticated;
select pg_temp.reject('select pg_temp.edit(1)', 'injected vector failure');
do $$ begin assert pg_temp.state() = current_setting('test.before')::jsonb, 'Vector failure must roll back roster and receipt'; end $$;
reset role;
drop trigger fail_vector on matches;
-- A constraint failure after a partial multi-player insert rolls back deletion
-- and every inserted row, not only the failing addition.
alter table team_players add constraint injected_partial_addition check (player_id <> '30000000-0000-0000-0000-000000000004');
set local role authenticated;
select pg_temp.reject('select pg_temp.edit(1)', 'injected_partial_addition');
do $$ begin assert pg_temp.state() = current_setting('test.before')::jsonb, 'Partial addition rollback'; end $$;
reset role;
alter table team_players drop constraint injected_partial_addition;
set local role authenticated;
-- Chosen operation inputs are still 90/94 after current scores drift to 12.
update players set score=12;
select pg_temp.edit(1);
do $$ begin
 assert (select count(*) from team_players) = 4;
 assert (select score_meta->'draft_rankings'->>'30000000-0000-0000-0000-000000000001' from matches) = '90';
 assert (select score_meta->'draft_rankings'->>'30000000-0000-0000-0000-000000000004' from matches) = '94';
 assert not exists(select 1 from team_players tp join matches m using(match_id)
   where jsonb_typeof(m.score_meta->'draft_rankings'->tp.player_id::text) is distinct from 'number'), 'Readable complete vector';
 assert (select score_meta->'unrelated' from matches) = '{"keep":true}'::jsonb;
 assert (select score_meta->>'tournament_home_team_id' from matches) = 'synthetic-home';
 assert (select name from teams where side='home') = 'Keep home';
 assert (select color from teams where side='away') = '#445566';
 assert (select play_with_substitute from matches) = false;
 assert not exists(select 1 from ranking_history), 'No experience-factor events';
 assert (select bool_and(score=12) from players), 'Current ranking unchanged';
end $$;
-- Lost-response replay is an exact no-op even with later current scores.
update players set score=80;
select set_config('test.before',pg_temp.state()::text,true);
select pg_temp.edit(1);
do $$ begin assert pg_temp.state()=current_setting('test.before')::jsonb, 'Exact lost-response replay'; end $$;
select pg_temp.reject('select pg_temp.edit(1, ranks => pg_temp.ranks(array[1,2,3,4],array[12,52,53,94]))', 'request ID reused');
select pg_temp.reject('select pg_temp.edit(2, ranks => pg_temp.ranks(array[1,2,3,4],array[90,12,53,94]),base=>1)', 'Retained player input changed');
select pg_temp.reject('select pg_temp.edit(2, ranks => pg_temp.ranks(array[1,2,3],array[90,52,53]),base=>1)', 'Exact numeric input vector');
select pg_temp.reject('select pg_temp.edit(2, home => pg_temp.ids(1,1),base=>1)', 'exactly once');
select pg_temp.reject('select pg_temp.edit(2, home => pg_temp.ids(1,6),base=>1)', 'Players must belong');
do $$ begin assert pg_temp.state()=current_setting('test.before')::jsonb, 'Invalid commands do not mutate'; end $$;
-- Admin transfer retains every value. Owner removal/re-add chooses NEW input.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select pg_temp.edit(2, pg_temp.ids(1,3),pg_temp.ids(2,4),base=>1);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select pg_temp.edit(3, pg_temp.ids(3),pg_temp.ids(2),pg_temp.ranks(array[2,3],array[52,53]),2);
do $$ begin
 assert (select count(*) from matches m cross join lateral jsonb_object_keys(m.score_meta->'draft_rankings'))=2;
end $$;
select pg_temp.edit(4,pg_temp.ids(1,3),pg_temp.ids(2),pg_temp.ranks(array[1,2,3],array[70,52,53]),3);
do $$ begin assert (select score_meta->'draft_rankings'->>'30000000-0000-0000-0000-000000000001' from matches)='70', 'Re-add new chosen input'; end $$;
select set_config('test.before',pg_temp.state()::text,true);
select pg_temp.reject('select pg_temp.edit(1)', 'Roster changed');
do $$ begin assert pg_temp.state()=current_setting('test.before')::jsonb, 'Older replay cannot undo a later edit'; end $$;
-- Score guard applies to fresh edits, but exact committed replay does no edit.
update matches set home_score=1;
select set_config('test.before',pg_temp.state()::text,true);
select pg_temp.reject('select pg_temp.edit(5,base=>4)', 'match with score');
select pg_temp.edit(4,pg_temp.ids(1,3),pg_temp.ids(2),pg_temp.ranks(array[1,2,3],array[70,52,53]),3);
do $$ begin
 assert pg_temp.state()=current_setting('test.before')::jsonb, 'Scored guard / replay leaves all state unchanged';
 assert not exists(select 1 from ranking_history), 'No history events after all operations';
end $$;
-- Finite-double extrema stay readable; no unrelated minimum team size is added.
update matches set home_score=null;
select pg_temp.edit(5,pg_temp.ids(1,3),pg_temp.ids(2,4),pg_temp.ranks(array[1,2,3,4],array[70,52,53,1.7976931348623157e308]),4);
do $$ begin
 assert (select (score_meta->'draft_rankings'->>'30000000-0000-0000-0000-000000000004')::numeric from matches)='1.7976931348623157e308'::numeric;
end $$;
select pg_temp.edit(6,'[]','[]','{}',5);
do $$ begin
 assert not exists(select 1 from team_players), 'Empty teams retain existing editing semantics';
 assert (select score_meta->'draft_rankings' from matches)='{}'::jsonb;
 assert (select count(*) from teams)=2;
end $$;
select pg_temp.edit(7,pg_temp.ids(1),'[]',pg_temp.ranks(array[1],array[0]),6);
select pg_temp.edit(8,pg_temp.ids(1),pg_temp.ids(5),pg_temp.ranks(array[1,5],array[0,-1.7976931348623157e308]),7);
select pg_temp.edit(9,pg_temp.ids(1),pg_temp.ids(4,5),pg_temp.ranks(array[1,4,5],array[0,1e-400,-1.7976931348623157e308]),8);
do $$ begin
 assert (select count(*) from team_players)=3;
 assert (select (score_meta->'draft_rankings'->>'30000000-0000-0000-0000-000000000004')::numeric from matches)='1e-400'::numeric;
 assert not exists(select 1 from ranking_history);
end $$;
rollback;
