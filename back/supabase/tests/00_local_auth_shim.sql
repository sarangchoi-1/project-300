-- LOCAL TEST FIXTURE - NOT A MIGRATION. NEVER APPLY THIS TO A SUPABASE PROJECT.
--
-- Supabase provides the `auth` schema, auth.uid(), and the anon / authenticated /
-- service_role roles. A plain local PostgreSQL cluster does not. This file
-- recreates the minimum surface the migrations depend on so that
-- back/scripts/verify-local.sh can apply and test them without Docker.
--
-- It lives in tests/ (not migrations/) precisely so the Supabase CLI never picks
-- it up.

--------------------------------------------------------------------------------
-- Roles that Supabase pre-creates
--------------------------------------------------------------------------------

do $$
begin
  create role anon nologin noinherit;
exception when duplicate_object then null;
end $$;

do $$
begin
  create role authenticated nologin noinherit;
exception when duplicate_object then null;
end $$;

do $$
begin
  create role service_role nologin noinherit bypassrls;
exception when duplicate_object then null;
end $$;

grant usage on schema public to anon, authenticated, service_role;

--------------------------------------------------------------------------------
-- auth schema
--------------------------------------------------------------------------------

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

-- Only the columns the migrations actually read. The real table has many more.
create table if not exists auth.users (
  id                  uuid        primary key,
  email               text        unique,
  raw_user_meta_data  jsonb       not null default '{}'::jsonb,
  created_at          timestamptz not null default now()
);

-- In Supabase this reads the `sub` claim of the request JWT. PostgREST sets
-- request.jwt.claims per request; the tests set it with set_config().
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

grant execute on function auth.uid() to anon, authenticated, service_role;
