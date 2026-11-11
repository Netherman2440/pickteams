-- Lightweight PostgreSQL fixture only. Not Supabase Auth or PostgREST.
-- Run only in a fresh disposable local database before the real migrations.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  created_at timestamptz default now(),
  raw_user_meta_data jsonb default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
grant usage on schema auth, public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
-- Supabase's normal API table grants; RLS still applies to both roles.
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;
