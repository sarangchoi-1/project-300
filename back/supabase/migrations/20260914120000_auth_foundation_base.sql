-- Backend 1 - Identity / Organization / Authorization foundation
-- Migration 1/6: shared enum types and shared trigger helpers.
--
-- Owner: Backend 1. Backend 2 may READ these types but must not redefine them.
-- Every statement in this file is idempotent so it can be re-run safely.

--------------------------------------------------------------------------------
-- Enum types
--------------------------------------------------------------------------------

-- Application-wide role. Governs what a user may do across the whole app.
do $$
begin
  create type public.app_role as enum ('member', 'leader', 'admin');
exception
  when duplicate_object then null;
end
$$;

comment on type public.app_role is
  'App-wide role for a profile. ''leader'' is informational at the app level; '
  'actual group leadership is stored per-group in public.group_members.role.';

-- Approval gate. A user may authenticate before being approved, but must not
-- see normal app content until an admin approves them.
do $$
begin
  create type public.approval_status as enum ('pending', 'approved', 'rejected');
exception
  when duplicate_object then null;
end
$$;

comment on type public.approval_status is
  'Admin approval state for a profile. New signups are always ''pending''.';

-- Role held *within a single group*.
do $$
begin
  create type public.group_role as enum ('member', 'leader');
exception
  when duplicate_object then null;
end
$$;

comment on type public.group_role is
  'Role a user holds inside one group. public.group_members is the single '
  'source of truth for group leadership (no leader_id column on groups, so '
  'there is no circular foreign key).';

--------------------------------------------------------------------------------
-- Shared trigger helper: keep updated_at honest
--------------------------------------------------------------------------------

-- Intentionally left executable by PUBLIC: calling it outside a trigger raises,
-- and revoking EXECUTE risks breaking writes for roles that fire the trigger.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'BEFORE UPDATE trigger helper that stamps updated_at = now(). '
  'Clients cannot forge updated_at because this always overwrites it.';
