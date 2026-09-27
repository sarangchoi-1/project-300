-- Backend 1 - Identity / Organization / Authorization foundation
-- Migration 5/6: RLS, table/column grants, and the privilege guard trigger.
--
-- Conventions Backend 2 must follow for its own tables:
--   1. `alter table ... enable row level security;` on every exposed table.
--   2. NEVER `force row level security` (it breaks the SECURITY DEFINER helpers).
--   3. Every policy names its roles explicitly: `to authenticated`. anon gets
--      nothing, which means an unauthenticated request is default-deny.
--   4. One policy per (action, audience) with a descriptive name
--      `<table>_<action>_<audience>`, so a reviewer can read the policy list and
--      see the whole access matrix.
--   5. Read policies AND in public.is_approved() so pending / rejected users see
--      no app content.
--   6. Grant the narrowest privilege that the policies actually need. Prefer
--      column-scoped UPDATE grants over table-wide UPDATE.
--   7. Wrap auth.uid() as `(select auth.uid())` so the planner evaluates it once
--      per statement instead of once per row.

--------------------------------------------------------------------------------
-- Enable RLS (default-deny for anon and authenticated)
--------------------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.groups        enable row level security;
alter table public.group_members enable row level security;

--------------------------------------------------------------------------------
-- Grants
--------------------------------------------------------------------------------
-- Grants decide which *columns and verbs* are reachable at all; RLS decides
-- which *rows*. Both must allow an operation for it to succeed.

-- anon can reach nothing in this schema. Signup / signin go through Supabase
-- Auth (the auth schema), not through these tables.
revoke all on public.profiles      from anon;
revoke all on public.groups        from anon;
revoke all on public.group_members from anon;

revoke all on public.profiles      from authenticated;
revoke all on public.groups        from authenticated;
revoke all on public.group_members from authenticated;

-- profiles: no INSERT (rows are created by the signup trigger, and an insert
-- without a matching auth.users row would violate the FK) and no DELETE
-- (deleting a profile would orphan the auth user and leave a user who can log in
-- with no profile). Deactivate with approval_status = 'rejected'; hard-delete via
-- the Auth Admin API, which cascades into this table.
grant select on public.profiles to authenticated;
grant update (display_name, role, approval_status) on public.profiles to authenticated;

grant select, insert, delete on public.groups to authenticated;
grant update (name, description, is_active) on public.groups to authenticated;

-- group_id / user_id are intentionally not updatable: reassigning a membership
-- in place would silently rewrite history. Admins delete and re-insert, or flip
-- is_active.
grant select, insert, delete on public.group_members to authenticated;
grant update (role, is_active) on public.group_members to authenticated;

--------------------------------------------------------------------------------
-- profiles policies
--------------------------------------------------------------------------------

-- Read own profile. Deliberately NOT gated on approval: the Flutter app needs to
-- read approval_status while pending in order to show the waiting screen.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()));

drop policy if exists profiles_select_admin on public.profiles;
create policy profiles_select_admin
  on public.profiles
  for select
  to authenticated
  using (public.is_admin());

-- Admins approve/reject and promote/demote. This is the ONLY update policy on
-- profiles, so a normal member cannot approve or promote anyone - including
-- themselves - no matter what payload they send.
--
-- There is deliberately NO self-service update policy. Self-editing of
-- display_name is not an approved requirement yet; when it is, add a narrow
-- `profiles_update_own` policy - the guard trigger below already prevents such a
-- policy from being abused to escalate role or approval_status.
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin
  on public.profiles
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

--------------------------------------------------------------------------------
-- groups policies
--------------------------------------------------------------------------------

drop policy if exists groups_select_admin on public.groups;
create policy groups_select_admin
  on public.groups
  for select
  to authenticated
  using (public.is_admin());

-- An approved member (or leader) sees exactly the group they belong to.
drop policy if exists groups_select_own_group on public.groups;
create policy groups_select_own_group
  on public.groups
  for select
  to authenticated
  using (public.is_approved() and public.is_group_member(id));

drop policy if exists groups_insert_admin on public.groups;
create policy groups_insert_admin
  on public.groups
  for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists groups_update_admin on public.groups;
create policy groups_update_admin
  on public.groups
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists groups_delete_admin on public.groups;
create policy groups_delete_admin
  on public.groups
  for delete
  to authenticated
  using (public.is_admin());

--------------------------------------------------------------------------------
-- group_members policies
--------------------------------------------------------------------------------

drop policy if exists group_members_select_own on public.group_members;
create policy group_members_select_own
  on public.group_members
  for select
  to authenticated
  using (user_id = (select auth.uid()) and public.is_approved());

-- A leader sees every membership row of the group they lead (their roster).
drop policy if exists group_members_select_group_leader on public.group_members;
create policy group_members_select_group_leader
  on public.group_members
  for select
  to authenticated
  using (public.is_group_leader(group_id));

drop policy if exists group_members_select_admin on public.group_members;
create policy group_members_select_admin
  on public.group_members
  for select
  to authenticated
  using (public.is_admin());

-- Membership and leadership are admin-only for the MVP. Because there is no
-- non-admin insert/update/delete policy, a member cannot add themselves to a
-- group, leave a group, or promote themselves to leader.
drop policy if exists group_members_insert_admin on public.group_members;
create policy group_members_insert_admin
  on public.group_members
  for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists group_members_update_admin on public.group_members;
create policy group_members_update_admin
  on public.group_members
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists group_members_delete_admin on public.group_members;
create policy group_members_delete_admin
  on public.group_members
  for delete
  to authenticated
  using (public.is_admin());

--------------------------------------------------------------------------------
-- Defense in depth: privilege guard trigger on profiles
--------------------------------------------------------------------------------

-- RLS already blocks self-promotion. This trigger is a second, independent lock
-- so that a future broad `profiles_update_own` policy (or a careless grant)
-- cannot turn into privilege escalation.
--
-- It only polices the PostgREST client roles (anon / authenticated). Trusted
-- server-side contexts - postgres running a migration, service_role in an Edge
-- Function, or a SECURITY DEFINER function such as
-- public.bootstrap_first_admin() - run as a different current_user and pass
-- through.
create or replace function public.enforce_profile_privilege_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'profiles.id is immutable'
      using errcode = '42501';
  end if;

  if (new.role, new.approval_status) is distinct from (old.role, old.approval_status) then
    if current_user in ('anon', 'authenticated') and not public.is_admin() then
      raise exception
        'Only administrators may change profiles.role or profiles.approval_status'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_profile_privilege_guard() is
  'BEFORE UPDATE guard on public.profiles. Blocks client roles from changing '
  'role / approval_status unless public.is_admin(), and makes id immutable. '
  'Independent of RLS on purpose.';

drop trigger if exists profiles_privilege_guard on public.profiles;
create trigger profiles_privilege_guard
  before update on public.profiles
  for each row
  execute function public.enforce_profile_privilege_guard();
