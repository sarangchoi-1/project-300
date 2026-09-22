-- Backend 1 - Identity / Organization / Authorization foundation
-- Migration 4/6: reusable authorization helpers.
--
-- THESE ARE THE AUTHORIZATION CONTRACT. Backend 2 must express its RLS policies
-- for attendance / prayer_requests / meetings / bulletins in terms of these
-- functions instead of re-querying public.profiles or public.group_members.
--
-- Why SECURITY DEFINER:
--   RLS on public.profiles must be able to ask "is the caller an admin?", which
--   means reading public.profiles from inside a policy on public.profiles. Doing
--   that directly is infinite recursion. A SECURITY DEFINER function owned by the
--   table owner reads the row without re-entering RLS, which breaks the cycle.
--
-- CONSEQUENCE - DO NOT enable `alter table ... force row level security` on
-- public.profiles or public.group_members. FORCE applies RLS to the table owner
-- too, which would re-introduce the recursion and break every policy below.
--
-- Hardening applied to each function:
--   * `set search_path = ''` so a hostile schema on the caller's search_path can
--     never shadow a table or operator used in the body.
--   * everything schema-qualified.
--   * `stable` so results are cached per statement.
--   * EXECUTE revoked from PUBLIC and from anon; granted only to authenticated
--     and service_role.

--------------------------------------------------------------------------------
-- Caller identity
--------------------------------------------------------------------------------

-- Returns the caller's app-wide role, or null when unauthenticated / profileless.
create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid());
$$;

comment on function public.current_app_role() is
  'Caller''s public.profiles.role, or null if unauthenticated. Read-only.';

--------------------------------------------------------------------------------
-- is_admin()
--------------------------------------------------------------------------------

-- An admin must also be approved: a pending/rejected account is never active,
-- even if someone set its role to admin.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.approval_status = 'approved'
  );
$$;

comment on function public.is_admin() is
  'True when the caller has an approved profile with role = admin. '
  'Returns false (never null, never an error) for anonymous callers.';

--------------------------------------------------------------------------------
-- is_approved()
--------------------------------------------------------------------------------

create or replace function public.is_approved()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.approval_status = 'approved'
  );
$$;

comment on function public.is_approved() is
  'True when the caller''s profile is approved. Backend 2 should AND this into '
  'every read policy so pending and rejected users see no app content.';

--------------------------------------------------------------------------------
-- is_group_member(group_id)
--------------------------------------------------------------------------------

-- Requires an ACTIVE membership *and* an approved profile, so revoking approval
-- immediately removes group-scoped access without touching group_members.
create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.group_id = p_group_id
      and gm.user_id = (select auth.uid())
      and gm.is_active
      and p.approval_status = 'approved'
  );
$$;

comment on function public.is_group_member(uuid) is
  'True when the caller has an active membership in p_group_id and an approved '
  'profile. Group leaders are also members, so this is true for them too.';

--------------------------------------------------------------------------------
-- is_group_leader(group_id)
--------------------------------------------------------------------------------

create or replace function public.is_group_leader(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.group_id = p_group_id
      and gm.user_id = (select auth.uid())
      and gm.is_active
      and gm.role = 'leader'
      and p.approval_status = 'approved'
  );
$$;

comment on function public.is_group_leader(uuid) is
  'True when the caller is the active, approved leader of p_group_id. '
  'Does NOT imply admin - admins are checked separately with public.is_admin().';

--------------------------------------------------------------------------------
-- Convenience helpers for Backend 2
--------------------------------------------------------------------------------

-- Backend 2 rows are usually keyed by group_id, but attendance and prayer
-- requests are keyed by *user*. This answers "may I, as a leader, act on this
-- person's record?" without Backend 2 having to join group_members itself.
create or replace function public.is_group_leader_of_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members target
    join public.group_members leader
      on leader.group_id = target.group_id
    join public.profiles leader_profile
      on leader_profile.id = leader.user_id
    where target.user_id = p_user_id
      and target.is_active
      and leader.user_id = (select auth.uid())
      and leader.is_active
      and leader.role = 'leader'
      and leader_profile.approval_status = 'approved'
  );
$$;

comment on function public.is_group_leader_of_user(uuid) is
  'True when the caller is an active approved leader of the active group that '
  'p_user_id belongs to. Intended for Backend 2 attendance / prayer_requests RLS.';

-- Null when the caller has no active group. Handy for `group_id = (select public.active_group_id())`
-- style policies and for Flutter to scope a feature screen.
create or replace function public.active_group_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select gm.group_id
  from public.group_members gm
  where gm.user_id = (select auth.uid())
    and gm.is_active
  limit 1;
$$;

comment on function public.active_group_id() is
  'The caller''s single active group id, or null. Unique per user via '
  'group_members_one_active_group_per_user_idx.';

--------------------------------------------------------------------------------
-- Execute grants
--------------------------------------------------------------------------------

-- Tighten from the PostgreSQL default (EXECUTE to PUBLIC). anon is excluded on
-- purpose: every policy in this project is scoped `to authenticated`, so anon
-- never needs to evaluate a helper.

revoke all on function public.current_app_role()             from public, anon;
revoke all on function public.is_admin()                     from public, anon;
revoke all on function public.is_approved()                  from public, anon;
revoke all on function public.is_group_member(uuid)          from public, anon;
revoke all on function public.is_group_leader(uuid)          from public, anon;
revoke all on function public.is_group_leader_of_user(uuid)  from public, anon;
revoke all on function public.active_group_id()              from public, anon;

grant execute on function public.current_app_role()            to authenticated, service_role;
grant execute on function public.is_admin()                    to authenticated, service_role;
grant execute on function public.is_approved()                 to authenticated, service_role;
grant execute on function public.is_group_member(uuid)         to authenticated, service_role;
grant execute on function public.is_group_leader(uuid)         to authenticated, service_role;
grant execute on function public.is_group_leader_of_user(uuid) to authenticated, service_role;
grant execute on function public.active_group_id()             to authenticated, service_role;
