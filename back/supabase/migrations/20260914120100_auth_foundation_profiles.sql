-- Backend 1 - Identity / Organization / Authorization foundation
-- Migration 2/6: public.profiles (1:1 with auth.users) and signup automation.
--
-- Passwords live ONLY in auth.users (bcrypt, managed by Supabase Auth). Nothing
-- in this file reads, copies, or mirrors credential data.

--------------------------------------------------------------------------------
-- Table
--------------------------------------------------------------------------------

create table if not exists public.profiles (
  id               uuid                    primary key
                                           references auth.users (id) on delete cascade,
  display_name     text                    not null,
  role             public.app_role         not null default 'member',
  approval_status  public.approval_status  not null default 'pending',
  created_at       timestamptz             not null default now(),
  updated_at       timestamptz             not null default now(),
  constraint profiles_display_name_length
    check (char_length(btrim(display_name)) between 1 and 60)
);

comment on table public.profiles is
  'Application profile for each auth.users row. Created automatically on signup '
  'by public.handle_new_user(). role and approval_status are admin-only fields.';
comment on column public.profiles.id is
  'Same value as auth.users.id / auth.uid(). Deleting the auth user cascades here.';
comment on column public.profiles.role is
  'App-wide role. Only admins may change this (RLS + guard trigger).';
comment on column public.profiles.approval_status is
  'Admin approval gate. Only admins may change this (RLS + guard trigger).';

--------------------------------------------------------------------------------
-- Indexes
--------------------------------------------------------------------------------

-- Admin console: "show me everyone waiting for approval".
create index if not exists profiles_approval_status_idx
  on public.profiles (approval_status);

-- Admin console: "show me all admins / leaders".
create index if not exists profiles_role_idx
  on public.profiles (role);

--------------------------------------------------------------------------------
-- updated_at trigger
--------------------------------------------------------------------------------

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

--------------------------------------------------------------------------------
-- Signup automation
--------------------------------------------------------------------------------

-- SECURITY: raw_user_meta_data is fully client-controlled (it is whatever the
-- Flutter app passed to signUp(data: ...)). We therefore read ONLY display_name
-- from it and hard-code role/approval_status to their safe defaults. A client
-- that posts {"role":"admin"} gets a plain pending member.
--
-- The display_name is trimmed and truncated to 60 chars so a hostile or merely
-- long value can never violate profiles_display_name_length and break signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_display_name text;
begin
  v_display_name := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  if v_display_name = '' then
    -- Fall back to the local part of the email so display_name is never null.
    v_display_name := btrim(split_part(coalesce(new.email, ''), '@', 1));
  end if;

  if v_display_name = '' then
    v_display_name := 'New Member';
  end if;

  insert into public.profiles (id, display_name, role, approval_status)
  values (new.id, left(v_display_name, 60), 'member', 'pending')
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'AFTER INSERT trigger on auth.users. Creates the matching public.profiles row '
  'using only display_name from client metadata; role/approval_status are forced '
  'to member/pending regardless of what the client sent.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

--------------------------------------------------------------------------------
-- Backfill: profiles for any auth user that predates this migration
--------------------------------------------------------------------------------

insert into public.profiles (id, display_name, role, approval_status)
select
  u.id,
  left(
    coalesce(
      nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
      nullif(btrim(split_part(coalesce(u.email, ''), '@', 1)), ''),
      'New Member'
    ),
    60
  ),
  'member',
  'pending'
from auth.users u
on conflict (id) do nothing;
