-- Disposable local fixture only. Real constraints and existing owner RLS.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000001','stars-owner@example.test'),
 ('10000000-0000-0000-0000-000000000002','stars-other@example.test');
insert into squads(squad_id,owner_id,name,visibility) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Stars','public'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Other','private');
insert into user_squads(user_id,squad_id,role) values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner'),
 ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','admin');

do $$
declare bad double precision[];
begin
  assert public.valid_star_thresholds(null);
  assert public.valid_star_thresholds(array[-10,0,1,2,3]::double precision[]);
  foreach bad slice 1 in array array[
    array[1,2,2,4,5], array[5,4,3,2,1], array[1,2,3,4,'NaN'::float8],
    array[1,2,3,4,'Infinity'::float8], array['-Infinity'::float8,2,3,4,5],
    array[1,2,null,4,5]
  ] loop
    begin
      update squads set star_thresholds=bad where name='Stars';
      raise exception 'Invalid thresholds accepted: %',bad;
    exception when check_violation then null;
    end;
  end loop;
  assert not public.valid_star_thresholds(array[]::double precision[]);
  assert not public.valid_star_thresholds(array[1,2,3,4]::double precision[]);
  assert not public.valid_star_thresholds(array[1,2,3,4,5,6]::double precision[]);
  assert not public.valid_star_thresholds('[0:4]={1,2,3,4,5}'::double precision[]);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
update squads set star_thresholds=array[10,30,70,90,150] where name='Stars';
do $$ begin
  assert (select star_thresholds from squads where name='Stars')=array[10,30,70,90,150]::float8[];
  assert (select star_thresholds is null from squads where name='Other'), 'Other squad unchanged';
end $$;
-- Admin and guest can read, but neither can change the owner's thresholds.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$ declare affected int; begin
  update squads set star_thresholds=array[1,2,3,4,5] where name='Stars';
  get diagnostics affected = row_count;
  assert affected=0, 'Admin cannot update';
  assert (select star_thresholds from squads where name='Stars')=array[10,30,70,90,150]::float8[];
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare affected int; begin
  assert (select star_thresholds from squads where name='Stars')=array[10,30,70,90,150]::float8[];
  update squads set star_thresholds=array[1,2,3,4,5] where name='Stars';
  get diagnostics affected = row_count;
  assert affected=0, 'Guest cannot update';
end $$;
rollback;
