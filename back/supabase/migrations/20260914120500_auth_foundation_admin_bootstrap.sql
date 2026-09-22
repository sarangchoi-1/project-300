-- Backend 1 - Identity / Organization / Authorization foundation
-- Migration 6/6: one-time first-admin bootstrap.
--
-- The chicken-and-egg problem: only an admin can promote an admin, and there is
-- no admin yet. Solved with a SECURITY DEFINER function that is NOT executable by
-- any client role, so the only way to run it is from a trusted context (the
-- Supabase SQL Editor, which runs as the database owner).
--
-- Three independent safety properties:
--   1. No client role (anon / authenticated / service_role) has EXECUTE, so it is
--      unreachable from the Flutter app and from the PostgREST /rpc endpoint.
--   2. It refuses to run once ANY admin exists, so even if EXECUTE were granted
--      by mistake it cannot be used a second time to escalate.
--   3. It targets a user by email and requires that the person has already signed
--      up. It never creates users and never touches credentials.
--
-- No key, password, or secret is embedded here. See back/docs/BACKEND1_HANDOFF.md.

create or replace function public.bootstrap_first_admin(p_email text)
returns table (
  id               uuid,
  display_name     text,
  role             public.app_role,
  approval_status  public.approval_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if exists (select 1 from public.profiles p where p.role = 'admin') then
    raise exception
      'An administrator already exists. Refusing to bootstrap; promote further admins from an existing admin account.'
      using errcode = '42501';
  end if;

  select u.id
    into v_user_id
  from auth.users u
  where lower(u.email) = lower(btrim(p_email));

  if v_user_id is null then
    raise exception
      'No auth user found with email %. Have that person sign up in the app first, then re-run this function.', p_email
      using errcode = 'P0002';
  end if;

  return query
  update public.profiles p
     set role = 'admin',
         approval_status = 'approved'
   where p.id = v_user_id
  returning p.id, p.display_name, p.role, p.approval_status;
end;
$$;

comment on function public.bootstrap_first_admin(text) is
  'One-time bootstrap of the very first admin. Run from the Supabase SQL Editor '
  'AFTER that person has signed up. Raises if an admin already exists. Not '
  'executable by anon / authenticated / service_role.';

-- Reachable only by the database owner (SQL Editor / migrations).
revoke all on function public.bootstrap_first_admin(text)
  from public, anon, authenticated, service_role;
