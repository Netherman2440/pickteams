-- Match-level thresholds are optional until explicitly configured/calibrated.
-- Keep existing squads SELECT and owner-only UPDATE RLS. No new privileges,
-- history writes, backfill, or invented numeric defaults. Half steps are derived.
create or replace function public.valid_star_thresholds(v double precision[])
returns boolean language sql immutable set search_path = '' as $$
  select v is null or coalesce(
    array_ndims(v) = 1 and array_lower(v, 1) = 1 and cardinality(v) = 5
    and v[1] > '-Infinity'::double precision
    and v[5] < 'Infinity'::double precision
    and v[1] < v[2] and v[2] < v[3] and v[3] < v[4] and v[4] < v[5], false
  );
$$;

alter table public.squads add column star_thresholds double precision[] null;
alter table public.squads add constraint squads_star_thresholds_valid
  check (public.valid_star_thresholds(star_thresholds));
