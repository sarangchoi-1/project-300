-- Backend 1 - Identity / Organization / Authorization foundation
-- Migration 3/6: public.groups and public.group_members.
--
-- public.groups deliberately has NO leader_id column. Leadership is stored on
-- public.group_members.role, which keeps the foreign keys acyclic:
--   auth.users -> profiles -> group_members -> groups

--------------------------------------------------------------------------------
-- groups
--------------------------------------------------------------------------------

create table if not exists public.groups (
  id           uuid         primary key default gen_random_uuid(),
  name         text         not null,
  description  text,
  is_active    boolean      not null default true,
  created_at   timestamptz  not null default now(),
  updated_at   timestamptz  not null default now(),
  constraint groups_name_length
    check (char_length(btrim(name)) between 1 and 80)
);

comment on table public.groups is
  'A young-adult small group / cell. Created and maintained by admins only. '
  'Leadership is NOT stored here - see public.group_members.role.';

-- Case-insensitive unique name so admins cannot create "Group A" twice.
create unique index if not exists groups_name_unique_idx
  on public.groups (lower(btrim(name)));

drop trigger if exists groups_set_updated_at on public.groups;
create trigger groups_set_updated_at
  before update on public.groups
  for each row
  execute function public.set_updated_at();

--------------------------------------------------------------------------------
-- group_members
--------------------------------------------------------------------------------

create table if not exists public.group_members (
  id          uuid               primary key default gen_random_uuid(),
  group_id    uuid               not null references public.groups (id)   on delete cascade,
  user_id     uuid               not null references public.profiles (id) on delete cascade,
  role        public.group_role  not null default 'member',
  is_active   boolean            not null default true,
  joined_at   timestamptz        not null default now(),
  created_at  timestamptz        not null default now(),
  updated_at  timestamptz        not null default now(),
  -- A user appears at most once per group, active or not.
  constraint group_members_group_id_user_id_key unique (group_id, user_id)
);

comment on table public.group_members is
  'Source of truth for group membership AND group leadership. Managed by admins '
  'only in the MVP. Backend 2 should join through here (or use the '
  'public.is_group_member / public.is_group_leader helpers) rather than '
  'duplicating membership state.';
comment on column public.group_members.role is
  'Group-scoped role. ''leader'' is what public.is_group_leader() checks.';
comment on column public.group_members.is_active is
  'Soft membership state. Set false to move someone out of a group while '
  'keeping the historical row (needed by Backend 2 attendance history).';

-- MVP rule: one ACTIVE group per user. Historical (is_active = false) rows are
-- unlimited, so a user's group history is preserved. If the product later needs
-- multi-group membership, drop this index and update back/docs/BACKEND1_HANDOFF.md.
create unique index if not exists group_members_one_active_group_per_user_idx
  on public.group_members (user_id)
  where (is_active);

comment on index public.group_members_one_active_group_per_user_idx is
  'Enforces the MVP rule that a user belongs to at most one ACTIVE group.';

-- Lookup paths used by RLS helpers and by Backend 2 feature queries.
create index if not exists group_members_group_id_idx
  on public.group_members (group_id);

create index if not exists group_members_user_id_idx
  on public.group_members (user_id);

-- "Who leads group X" / is_group_leader() fast path.
create index if not exists group_members_group_leaders_idx
  on public.group_members (group_id, user_id)
  where (is_active and role = 'leader');

drop trigger if exists group_members_set_updated_at on public.group_members;
create trigger group_members_set_updated_at
  before update on public.group_members
  for each row
  execute function public.set_updated_at();
