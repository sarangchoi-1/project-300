-- LOCAL TEST FIXTURE - NOT A MIGRATION.
--
-- Regression suite for the Backend 1 auth foundation. Run it with
-- back/scripts/verify-local.sh, which builds a scratch database, applies the
-- auth shim, applies every migration in order, and then runs this file.
--
-- Fixture identities (fixed UUIDs so failures are readable):
--   ...a1  admin@example.test      -> admin, approved, no group
--   ...b1  leader@example.test     -> leader, approved, LEADER of Group A
--   ...c1  member@example.test     -> member, approved, MEMBER of Group A
--   ...c2  member-b@example.test   -> member, approved, MEMBER of Group B
--   ...d1  pending@example.test    -> member, pending,  no group
--   ...e1  rejected@example.test   -> member, rejected, no group
--   ...f1  nometa@example.test     -> member, approved, no group (signed up with no display_name)
--
--   Group A = 10000000-0000-0000-0000-00000000000a
--   Group B = 10000000-0000-0000-0000-00000000000b
--   Group C = 10000000-0000-0000-0000-00000000000c  (created during the admin test)

\set ON_ERROR_STOP on
\timing off
\pset pager off

--------------------------------------------------------------------------------
\echo ''
\echo '### 0. signup trigger'
--------------------------------------------------------------------------------

begin;

-- Simulates Supabase Auth email/password signup. The last three users send
-- hostile metadata that tries to self-assign privileges.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@example.test',    '{"display_name":"Admin Ahn"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'leader@example.test',   '{"display_name":"Leader Lee"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'member@example.test',   '{"display_name":"Member Min"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'member-b@example.test', '{"display_name":"Member Bae"}'),
  ('00000000-0000-0000-0000-0000000000d1', 'pending@example.test',  '{"display_name":"Pending Park"}'),
  ('00000000-0000-0000-0000-0000000000e1', 'rejected@example.test',
     '{"display_name":"Rejected Ryu","role":"admin","approval_status":"approved"}'),
  ('00000000-0000-0000-0000-0000000000f1', 'nometa@example.test',   '{}');

do $$
begin
  perform tests.assert(
    (select count(*) from public.profiles) = 7,
    'the signup trigger created one profile per auth user');

  perform tests.assert(
    (select bool_and(role = 'member' and approval_status = 'pending') from public.profiles),
    'every new profile defaults to member/pending, and client-supplied role/approval_status metadata is ignored');

  perform tests.assert(
    (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000c1')
      = 'Member Min',
    'display_name is taken from raw_user_meta_data.display_name');

  perform tests.assert(
    (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000f1')
      = 'nometa',
    'display_name falls back to the email local part when metadata is empty');

  -- Idempotency / robustness: a hostile 300-char display_name must not break signup.
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    '00000000-0000-0000-0000-0000000000ff',
    'long@example.test',
    jsonb_build_object('display_name', repeat('x', 300))
  );

  perform tests.assert(
    (select char_length(display_name) from public.profiles
      where id = '00000000-0000-0000-0000-0000000000ff') = 60,
    'an over-long display_name is truncated instead of failing signup');

  delete from auth.users where id = '00000000-0000-0000-0000-0000000000ff';

  perform tests.assert(
    not exists (select 1 from public.profiles
                where id = '00000000-0000-0000-0000-0000000000ff'),
    'deleting an auth user cascades the profile away');
end
$$;

commit;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 1. first-admin bootstrap'
--------------------------------------------------------------------------------

-- Reachability: no client role may call the bootstrap function.
begin;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  perform tests.assert_denied(
    $q$select * from public.bootstrap_first_admin('admin@example.test')$q$,
    'an authenticated client cannot execute bootstrap_first_admin()');
end
$$;

rollback;

-- Behaviour when run from a trusted context (the SQL Editor equivalent).
begin;

do $$
declare
  v_role   public.app_role;
  v_status public.approval_status;
begin
  perform tests.assert_denied(
    $q$select * from public.bootstrap_first_admin('who@example.test')$q$,
    'bootstrap refuses an email that has not signed up yet');

  select b.role, b.approval_status
    into v_role, v_status
  from public.bootstrap_first_admin('admin@example.test') b;

  perform tests.assert(v_role = 'admin',       'bootstrap set role = admin');
  perform tests.assert(v_status = 'approved',  'bootstrap set approval_status = approved');

  perform tests.assert_denied(
    $q$select * from public.bootstrap_first_admin('member@example.test')$q$,
    'bootstrap refuses to run a second time once an admin exists');
end
$$;

commit;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 2. fixture: approvals, roles, groups, memberships'
--------------------------------------------------------------------------------

begin;

update public.profiles
   set approval_status = 'approved'
 where id in ('00000000-0000-0000-0000-0000000000b1',
              '00000000-0000-0000-0000-0000000000c1',
              '00000000-0000-0000-0000-0000000000c2',
              '00000000-0000-0000-0000-0000000000f1');

update public.profiles set role = 'leader'
 where id = '00000000-0000-0000-0000-0000000000b1';

update public.profiles set approval_status = 'rejected'
 where id = '00000000-0000-0000-0000-0000000000e1';

insert into public.groups (id, name, description) values
  ('10000000-0000-0000-0000-00000000000a', 'Group A', 'Sunday 1st floor'),
  ('10000000-0000-0000-0000-00000000000b', 'Group B', 'Sunday 2nd floor');

insert into public.group_members (group_id, user_id, role) values
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000b1', 'leader'),
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000c1', 'member'),
  ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000c2', 'member');

do $$
begin
  perform tests.assert_denied(
    $q$insert into public.groups (name) values ('  group a ')$q$,
    'group names are unique case-insensitively');

  perform tests.assert_denied(
    $q$update public.profiles set id = gen_random_uuid()
        where id = '00000000-0000-0000-0000-0000000000c1'$q$,
    'profiles.id is immutable, even for a trusted role');
end
$$;

commit;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 3. unauthenticated (anon)'
--------------------------------------------------------------------------------

begin;
set local role anon;

do $$
begin
  perform tests.assert_denied($q$select 1 from public.profiles$q$,
    'anon cannot read profiles');
  perform tests.assert_denied($q$select 1 from public.groups$q$,
    'anon cannot read groups');
  perform tests.assert_denied($q$select 1 from public.group_members$q$,
    'anon cannot read group_members');
  perform tests.assert_denied($q$insert into public.groups (name) values ('anon group')$q$,
    'anon cannot create groups');
  perform tests.assert_denied($q$select public.is_admin()$q$,
    'anon cannot even execute the authorization helpers');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 4. pending user'
--------------------------------------------------------------------------------

begin;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000d1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  -- The whole point of the waiting-for-approval screen: the pending user MUST be
  -- able to read their own approval_status.
  perform tests.assert_visible($q$select * from public.profiles$q$, 1,
    'a pending user sees exactly their own profile');
  perform tests.assert(
    (select approval_status from public.profiles) = 'pending',
    'a pending user can read their own approval_status');

  perform tests.assert(not public.is_approved(), 'is_approved() is false while pending');
  perform tests.assert(not public.is_admin(),    'is_admin() is false while pending');
  perform tests.assert(public.active_group_id() is null, 'a pending user has no active group');

  perform tests.assert_visible($q$select * from public.groups$q$, 0,
    'a pending user sees no groups');
  perform tests.assert_visible($q$select * from public.group_members$q$, 0,
    'a pending user sees no memberships');

  perform tests.assert_affects($q$update public.profiles set approval_status = 'approved'$q$, 0,
    'a pending user cannot approve themselves');
  perform tests.assert_affects($q$update public.profiles set role = 'admin'$q$, 0,
    'a pending user cannot promote themselves');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 5. approved member'
--------------------------------------------------------------------------------

begin;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  perform tests.assert(public.is_approved(),  'is_approved() is true for an approved member');
  perform tests.assert(not public.is_admin(), 'is_admin() is false for a member');
  perform tests.assert(public.current_app_role() = 'member', 'current_app_role() reports member');

  perform tests.assert(
    public.is_group_member('10000000-0000-0000-0000-00000000000a'),
    'is_group_member() is true for the member''s own group');
  perform tests.assert(
    not public.is_group_member('10000000-0000-0000-0000-00000000000b'),
    'is_group_member() is false for someone else''s group');
  perform tests.assert(
    not public.is_group_leader('10000000-0000-0000-0000-00000000000a'),
    'a plain member is not a group leader');
  perform tests.assert(
    public.active_group_id() = '10000000-0000-0000-0000-00000000000a',
    'active_group_id() returns the member''s single active group');

  -- Reads
  perform tests.assert_visible($q$select * from public.profiles$q$, 1,
    'a member sees only their own profile');
  perform tests.assert_visible($q$select * from public.groups$q$, 1,
    'a member sees exactly one group');
  perform tests.assert(
    (select id from public.groups) = '10000000-0000-0000-0000-00000000000a',
    'and it is their own group');
  perform tests.assert_visible($q$select * from public.group_members$q$, 1,
    'a member sees only their own membership row, not the rest of the roster');

  -- Writes: every one of these is the "normal user must never be able to" list.
  perform tests.assert_affects($q$update public.profiles set role = 'admin'$q$, 0,
    'a member cannot promote themselves');
  perform tests.assert_affects($q$update public.profiles set approval_status = 'approved'
      where id = '00000000-0000-0000-0000-0000000000d1'$q$, 0,
    'a member cannot approve somebody else');
  perform tests.assert_affects($q$update public.profiles set display_name = 'Hacked'$q$, 0,
    'there is no self-service profile update policy yet');
  perform tests.assert_affects($q$update public.group_members set role = 'leader'$q$, 0,
    'a member cannot make themselves a group leader');
  perform tests.assert_affects($q$delete from public.group_members$q$, 0,
    'a member cannot remove themselves from a group');
  perform tests.assert_denied(
    $q$insert into public.groups (name) values ('Member Made This')$q$,
    'a member cannot create a group');
  perform tests.assert_denied(
    $q$insert into public.group_members (group_id, user_id)
       values ('10000000-0000-0000-0000-00000000000b',
               '00000000-0000-0000-0000-0000000000f1')$q$,
    'a member cannot create group memberships');
  perform tests.assert_affects($q$delete from public.groups$q$, 0,
    'a member cannot delete groups');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 6. group leader'
--------------------------------------------------------------------------------

begin;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000b1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  perform tests.assert(
    public.is_group_leader('10000000-0000-0000-0000-00000000000a'),
    'is_group_leader() is true for the group the leader leads');
  perform tests.assert(
    not public.is_group_leader('10000000-0000-0000-0000-00000000000b'),
    'is_group_leader() is false for another group');
  perform tests.assert(
    public.is_group_member('10000000-0000-0000-0000-00000000000a'),
    'a leader is also a member of their group');
  perform tests.assert(not public.is_admin(), 'a leader is not an admin');

  perform tests.assert(
    public.is_group_leader_of_user('00000000-0000-0000-0000-0000000000c1'),
    'is_group_leader_of_user() is true for a member of the leader''s group');
  perform tests.assert(
    not public.is_group_leader_of_user('00000000-0000-0000-0000-0000000000c2'),
    'is_group_leader_of_user() is false for a member of another group');

  -- Reads
  perform tests.assert_visible($q$select * from public.group_members$q$, 2,
    'a leader sees the whole roster of their own group (and nothing else)');
  perform tests.assert_visible($q$select * from public.groups$q$, 1,
    'a leader sees only their own group');
  perform tests.assert_visible($q$select * from public.profiles$q$, 1,
    'KNOWN GAP: a leader currently sees only their own profile, not their members'' profiles');

  -- Writes: leadership is read-only in the MVP.
  perform tests.assert_affects(
    $q$update public.group_members set role = 'leader'
        where user_id = '00000000-0000-0000-0000-0000000000c1'$q$, 0,
    'a leader cannot change roster roles');
  perform tests.assert_affects(
    $q$delete from public.group_members
        where user_id = '00000000-0000-0000-0000-0000000000c1'$q$, 0,
    'a leader cannot remove a member from the group');
  perform tests.assert_denied(
    $q$insert into public.group_members (group_id, user_id)
       values ('10000000-0000-0000-0000-00000000000a',
               '00000000-0000-0000-0000-0000000000f1')$q$,
    'a leader cannot add members to the group');
  perform tests.assert_affects(
    $q$update public.profiles set approval_status = 'approved'
        where id = '00000000-0000-0000-0000-0000000000d1'$q$, 0,
    'a leader cannot approve pending users');
  perform tests.assert_affects(
    $q$update public.groups set name = 'Renamed By Leader'$q$, 0,
    'a leader cannot rename their group');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 7. rejected user'
--------------------------------------------------------------------------------

begin;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000e1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  perform tests.assert(not public.is_approved(), 'is_approved() is false for a rejected user');
  perform tests.assert_visible($q$select * from public.profiles$q$, 1,
    'a rejected user still sees their own profile (so the app can explain why)');
  perform tests.assert_visible($q$select * from public.groups$q$, 0,
    'a rejected user sees no groups');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 8. admin'
--------------------------------------------------------------------------------

begin;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  perform tests.assert(public.is_admin(),    'is_admin() is true for the bootstrapped admin');
  perform tests.assert(public.is_approved(), 'the bootstrapped admin is approved');

  -- Reads
  perform tests.assert_visible($q$select * from public.profiles$q$, 7,
    'an admin reads every profile');
  perform tests.assert_visible($q$select * from public.groups$q$, 2,
    'an admin reads every group');
  perform tests.assert_visible($q$select * from public.group_members$q$, 3,
    'an admin reads every membership');

  -- Approval / role management
  perform tests.assert_affects(
    $q$update public.profiles set approval_status = 'approved'
        where id = '00000000-0000-0000-0000-0000000000d1'$q$, 1,
    'an admin can approve a pending user');
  perform tests.assert_affects(
    $q$update public.profiles set role = 'leader'
        where id = '00000000-0000-0000-0000-0000000000d1'$q$, 1,
    'an admin can change an app-wide role');

  -- Group management
  perform tests.assert_affects(
    $q$insert into public.groups (id, name)
       values ('10000000-0000-0000-0000-00000000000c', 'Group C')$q$, 1,
    'an admin can create a group');
  perform tests.assert_affects(
    $q$update public.groups set description = 'Wednesday'
        where id = '10000000-0000-0000-0000-00000000000c'$q$, 1,
    'an admin can edit a group');
  perform tests.assert_affects(
    $q$insert into public.group_members (group_id, user_id, role)
       values ('10000000-0000-0000-0000-00000000000c',
               '00000000-0000-0000-0000-0000000000f1', 'leader')$q$, 1,
    'an admin can appoint a group leader');

  -- Membership constraints
  perform tests.assert_denied(
    $q$insert into public.group_members (group_id, user_id)
       values ('10000000-0000-0000-0000-00000000000a',
               '00000000-0000-0000-0000-0000000000c1')$q$,
    'duplicate membership in the same group is rejected');
  perform tests.assert_denied(
    $q$insert into public.group_members (group_id, user_id)
       values ('10000000-0000-0000-0000-00000000000c',
               '00000000-0000-0000-0000-0000000000c1')$q$,
    'a user cannot hold two ACTIVE memberships');
  perform tests.assert_affects(
    $q$update public.group_members set is_active = false
        where group_id = '10000000-0000-0000-0000-00000000000a'
          and user_id  = '00000000-0000-0000-0000-0000000000c1'$q$, 1,
    'an admin can deactivate a membership');
  perform tests.assert_affects(
    $q$insert into public.group_members (group_id, user_id)
       values ('10000000-0000-0000-0000-00000000000c',
               '00000000-0000-0000-0000-0000000000c1')$q$, 1,
    'once the old membership is inactive the user can move to another group');
  perform tests.assert_affects(
    $q$delete from public.group_members
        where group_id = '10000000-0000-0000-0000-00000000000c'
          and user_id  = '00000000-0000-0000-0000-0000000000c1'$q$, 1,
    'an admin can remove a membership');
  perform tests.assert_affects(
    $q$delete from public.groups where id = '10000000-0000-0000-0000-00000000000c'$q$, 1,
    'an admin can delete a group');

  -- Even an admin cannot reach the columns we never granted.
  perform tests.assert_denied(
    $q$insert into public.profiles (id, display_name)
       values ('00000000-0000-0000-0000-0000000000a1', 'Duplicate')$q$,
    'nobody may INSERT into profiles from the client - profiles come from the signup trigger');
  perform tests.assert_denied(
    $q$delete from public.profiles where id = '00000000-0000-0000-0000-0000000000e1'$q$,
    'nobody may DELETE a profile from the client - delete the auth user instead');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 9. privilege guard trigger (defense in depth)'
--------------------------------------------------------------------------------

-- Prove that even if somebody later adds the permissive self-update policy that
-- the docs warn about, role / approval_status escalation is still impossible.
begin;

create policy profiles_update_own_probe
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Run as the PENDING user: 'pending' -> 'approved' is a real transition, which is
-- exactly the escalation the guard has to stop.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000d1"}', true) \g /dev/null
set local role authenticated;

do $$
begin
  perform tests.assert_affects(
    $q$update public.profiles set display_name = 'Renamed Self'$q$, 1,
    'with a narrow self-update policy a user can edit their own display_name');
  perform tests.assert_denied(
    $q$update public.profiles set role = 'admin'$q$,
    'the guard trigger blocks self-promotion even with a permissive update policy');
  perform tests.assert_denied(
    $q$update public.profiles set approval_status = 'approved'$q$,
    'the guard trigger blocks self-approval even with a permissive update policy');
  perform tests.assert_denied(
    $q$update public.profiles set role = 'leader', display_name = 'Sneaky'$q$,
    'bundling a role change into a legitimate display_name edit is still blocked');
end
$$;

rollback;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### 10. structural invariants'
--------------------------------------------------------------------------------

begin;

do $$
begin
  -- RLS on, FORCE off.
  perform tests.assert(
    (select bool_and(c.relrowsecurity)
       from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('profiles', 'groups', 'group_members')),
    'RLS is enabled on profiles, groups and group_members');

  perform tests.assert(
    (select not bool_or(c.relforcerowsecurity)
       from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('profiles', 'groups', 'group_members')),
    'FORCE RLS is off - enabling it would break the SECURITY DEFINER helpers');

  -- Every SECURITY DEFINER function pins its search_path.
  perform tests.assert(
    not exists (
      select 1
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.prosecdef
         and not exists (
           select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
            where cfg like 'search_path=%')),
    'every SECURITY DEFINER function in public pins search_path');

  -- anon is fully locked out at the privilege layer, not just by RLS.
  perform tests.assert(
    not (has_table_privilege('anon', 'public.profiles', 'select')
      or has_table_privilege('anon', 'public.profiles', 'insert')
      or has_table_privilege('anon', 'public.profiles', 'delete')
      or has_any_column_privilege('anon', 'public.profiles', 'update')),
    'anon holds no privileges on public.profiles');
  perform tests.assert(
    not (has_table_privilege('anon', 'public.groups', 'select')
      or has_any_column_privilege('anon', 'public.groups', 'update')),
    'anon holds no privileges on public.groups');
  perform tests.assert(
    not (has_table_privilege('anon', 'public.group_members', 'select')
      or has_any_column_privilege('anon', 'public.group_members', 'update')),
    'anon holds no privileges on public.group_members');
  perform tests.assert(
    not has_function_privilege('anon', 'public.is_admin()', 'execute'),
    'anon cannot execute is_admin()');

  -- The bootstrap function is unreachable from every client role.
  perform tests.assert(
    not has_function_privilege('anon', 'public.bootstrap_first_admin(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.bootstrap_first_admin(text)', 'execute')
    and not has_function_privilege('service_role', 'public.bootstrap_first_admin(text)', 'execute'),
    'no client role can execute bootstrap_first_admin()');

  -- Column-scoped grants, not table-wide UPDATE.
  perform tests.assert(
    not has_table_privilege('authenticated', 'public.profiles', 'update'),
    'authenticated has no table-wide UPDATE on profiles, only column grants');
  perform tests.assert(
    has_column_privilege('authenticated', 'public.profiles', 'approval_status', 'update')
    and has_column_privilege('authenticated', 'public.profiles', 'role', 'update'),
    'the admin approval/role columns are grantable (RLS restricts them to admins)');
  perform tests.assert(
    not has_column_privilege('authenticated', 'public.profiles', 'created_at', 'update')
    and not has_column_privilege('authenticated', 'public.profiles', 'id', 'update'),
    'profiles.id and profiles.created_at are not client-updatable');
  perform tests.assert(
    not has_column_privilege('authenticated', 'public.group_members', 'group_id', 'update')
    and not has_column_privilege('authenticated', 'public.group_members', 'user_id', 'update'),
    'group_members.group_id / user_id cannot be rewritten in place');
  perform tests.assert(
    not has_table_privilege('authenticated', 'public.profiles', 'insert')
    and not has_table_privilege('authenticated', 'public.profiles', 'delete'),
    'profiles cannot be inserted or deleted by clients');

  -- Foreign keys, cascade behaviour, acyclic design.
  perform tests.assert(
    exists (
      select 1
        from pg_catalog.pg_constraint c
        join pg_catalog.pg_class t   on t.oid = c.conrelid
        join pg_catalog.pg_class rt  on rt.oid = c.confrelid
        join pg_catalog.pg_namespace rn on rn.oid = rt.relnamespace
       where c.contype = 'f'
         and t.relname = 'profiles'
         and rn.nspname = 'auth' and rt.relname = 'users'
         and c.confdeltype = 'c'),
    'profiles.id references auth.users(id) ON DELETE CASCADE');
  perform tests.assert(
    (select count(*) from pg_catalog.pg_constraint c
       join pg_catalog.pg_class t on t.oid = c.conrelid
      where c.contype = 'f' and t.relname = 'group_members') = 2,
    'group_members has exactly two FKs (groups, profiles)');
  perform tests.assert(
    not exists (
      select 1 from pg_catalog.pg_constraint c
        join pg_catalog.pg_class t on t.oid = c.conrelid
       where c.contype = 'f' and t.relname = 'groups'),
    'groups has no outbound FK, so there is no leader/member cycle');

  -- Indexes the RLS helpers and admin screens depend on.
  perform tests.assert(
    (select count(*) from pg_catalog.pg_indexes
      where schemaname = 'public'
        and indexname in ('profiles_approval_status_idx',
                          'profiles_role_idx',
                          'groups_name_unique_idx',
                          'group_members_one_active_group_per_user_idx',
                          'group_members_group_id_idx',
                          'group_members_user_id_idx',
                          'group_members_group_leaders_idx')) = 7,
    'all expected indexes exist');

  -- updated_at is trigger-maintained everywhere.
  perform tests.assert(
    (select count(*) from pg_catalog.pg_trigger
      where tgname in ('profiles_set_updated_at',
                       'groups_set_updated_at',
                       'group_members_set_updated_at')
        and not tgisinternal) = 3,
    'updated_at triggers exist on all three tables');
  perform tests.assert(
    exists (select 1 from pg_catalog.pg_trigger
             where tgname = 'on_auth_user_created' and not tgisinternal),
    'the signup trigger is installed on auth.users');
  perform tests.assert(
    exists (select 1 from pg_catalog.pg_trigger
             where tgname = 'profiles_privilege_guard' and not tgisinternal),
    'the profiles privilege guard trigger is installed');
end
$$;

commit;
\echo '    ok'

--------------------------------------------------------------------------------
\echo ''
\echo '### access matrix (public schema policies)'
--------------------------------------------------------------------------------

select
  tablename                        as "table",
  policyname                       as policy,
  cmd                              as command,
  array_to_string(roles, ',')      as roles
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

\echo ''
\echo 'ALL BACKEND 1 AUTHORIZATION TESTS PASSED'
