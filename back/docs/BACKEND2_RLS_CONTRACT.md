# Backend 2 — authorization contract

You own `bulletins`, `meetings`, `attendance`, `prayer_requests`, PDF storage, and
notifications. Backend 1 owns identity, groups, and authorization. This document is
the interface between us.

**Do not query `public.profiles` or `public.group_members` directly in your
policies.** Use the helper functions. If the membership model changes — say we move
to multi-group membership — every policy built on the helpers keeps working, and
every policy built on a hand-written join silently breaks.

Schema reference: [`BACKEND1_HANDOFF.md`](./BACKEND1_HANDOFF.md).

---

## The helpers

All are `stable`, `security definer`, pinned to `search_path = ''`, and executable
by `authenticated` and `service_role`. They return `false` / `null` for anonymous
callers instead of raising, so they are safe to use in any policy expression.

| Function | True when | Use it for |
| --- | --- | --- |
| `public.is_approved()` | caller's profile is `approved` | **every** read policy |
| `public.is_admin()` | caller is an approved admin | admin overrides |
| `public.is_group_member(uuid)` | caller is an active, approved member of that group | group-scoped rows (`meetings`, group bulletins) |
| `public.is_group_leader(uuid)` | caller is the active, approved leader of that group | leader writes on group-scoped rows |
| `public.is_group_leader_of_user(uuid)` | caller leads the active group that this user is in | **user-scoped** rows (`attendance`, `prayer_requests`) |
| `public.active_group_id()` | — returns the caller's single active group id, or `null` | defaulting / scoping a query |
| `public.current_app_role()` | — returns `member` / `leader` / `admin`, or `null` | display logic |

Note that `is_group_member` is also true for leaders, and that `is_group_leader` does
**not** imply admin — check `is_admin()` separately when admins need an override.

---

## Conventions your migrations must follow

1. `alter table <t> enable row level security;` on every exposed table. No
   exceptions — the `anon` key is public, so a table without RLS is a public table.
2. **Never** `force row level security`. Our helpers are `security definer` and rely
   on the owner's RLS bypass; `FORCE` reintroduces infinite recursion and breaks
   every policy in the database. A structural test asserts this stays off.
3. Name the audience explicitly: `to authenticated`. Leaving it off defaults to
   `public`, which includes `anon`.
4. `revoke all on <t> from anon;` and grant `authenticated` only the verbs your
   policies actually use. Prefer column-scoped `grant update (col, ...)` over
   table-wide `UPDATE`.
5. AND `public.is_approved()` into every read policy, so pending and rejected users
   see nothing.
6. Write `(select auth.uid())` rather than bare `auth.uid()`. The scalar subquery is
   evaluated once per statement instead of once per row.
7. One policy per (action, audience), named `<table>_<action>_<audience>`, so the
   `pg_policies` listing reads as the access matrix.
8. Pin `search_path = ''` and schema-qualify everything in any `security definer`
   function you add, and revoke its `EXECUTE` from `public`.

---

## Worked examples

### `attendance` — user-scoped

Assume `attendance(id, user_id, meeting_id, status, ...)`.

```sql
alter table public.attendance enable row level security;

revoke all on public.attendance from anon;
grant select, insert on public.attendance to authenticated;
grant update (status) on public.attendance to authenticated;

-- A member reads their own attendance.
create policy attendance_select_own on public.attendance
  for select to authenticated
  using (public.is_approved() and user_id = (select auth.uid()));

-- A leader reads the attendance of everyone in the group they lead.
create policy attendance_select_group_leader on public.attendance
  for select to authenticated
  using (public.is_group_leader_of_user(user_id));

create policy attendance_select_admin on public.attendance
  for select to authenticated
  using (public.is_admin());

-- Leaders record attendance for their own members; admins for anyone.
create policy attendance_insert_leader on public.attendance
  for insert to authenticated
  with check (public.is_group_leader_of_user(user_id) or public.is_admin());

create policy attendance_update_leader on public.attendance
  for update to authenticated
  using      (public.is_group_leader_of_user(user_id) or public.is_admin())
  with check (public.is_group_leader_of_user(user_id) or public.is_admin());
```

Note `is_group_leader_of_user(user_id)` in both `using` and `with check` on the
update: without the `with check` half, a leader could reassign a row to a user
outside their group.

### `prayer_requests` — user-scoped with visibility

Assume `prayer_requests(id, author_id, group_id, body, visibility, ...)` where
`visibility` is something like `private | group | church`.

```sql
alter table public.prayer_requests enable row level security;

revoke all on public.prayer_requests from anon;
grant select, insert, delete on public.prayer_requests to authenticated;
grant update (body, visibility) on public.prayer_requests to authenticated;

create policy prayer_requests_select_own on public.prayer_requests
  for select to authenticated
  using (public.is_approved() and author_id = (select auth.uid()));

-- Shared with the group: any approved member of that group may read it.
create policy prayer_requests_select_group on public.prayer_requests
  for select to authenticated
  using (visibility = 'group' and public.is_group_member(group_id));

-- A leader sees their members' requests even when marked private-to-leadership.
create policy prayer_requests_select_group_leader on public.prayer_requests
  for select to authenticated
  using (visibility <> 'private' and public.is_group_leader_of_user(author_id));

create policy prayer_requests_select_admin on public.prayer_requests
  for select to authenticated
  using (public.is_admin());

-- Authors write their own rows, and cannot forge author_id or post into a group
-- they do not belong to.
create policy prayer_requests_insert_own on public.prayer_requests
  for insert to authenticated
  with check (
    public.is_approved()
    and author_id = (select auth.uid())
    and (group_id is null or public.is_group_member(group_id))
  );

create policy prayer_requests_update_own on public.prayer_requests
  for update to authenticated
  using      (author_id = (select auth.uid()) and public.is_approved())
  with check (author_id = (select auth.uid()));

create policy prayer_requests_delete_own on public.prayer_requests
  for delete to authenticated
  using (author_id = (select auth.uid()) or public.is_admin());
```

### `meetings` / group-scoped `bulletins`

```sql
create policy meetings_select_group on public.meetings
  for select to authenticated
  using (public.is_admin() or public.is_group_member(group_id));

create policy meetings_write_leader on public.meetings
  for all to authenticated
  using      (public.is_admin() or public.is_group_leader(group_id))
  with check (public.is_admin() or public.is_group_leader(group_id));
```

For church-wide bulletins with no `group_id`, `public.is_approved()` on read and
`public.is_admin()` on write is the whole policy.

---

## Referencing our tables

- Point user foreign keys at `public.profiles(id)`, not `auth.users(id)`. A profile
  is guaranteed to exist for every auth user, and `profiles` cascades from
  `auth.users`, so `on delete cascade` still propagates correctly.
- Point group foreign keys at `public.groups(id)`.
- Do not add a `leader_id` column anywhere. `group_members.role = 'leader'` is the
  single source of truth; a second copy will drift.
- `group_members` rows are soft-deactivated (`is_active = false`) rather than
  deleted, so historical attendance keeps resolving. Filter on `is_active` when you
  want the current roster; the helpers already do.

---

## Storage (PDF bulletins)

Storage has its own RLS on `storage.objects`, and the same helpers work there:

```sql
create policy bulletin_pdfs_read on storage.objects
  for select to authenticated
  using (bucket_id = 'bulletins' and public.is_approved());

create policy bulletin_pdfs_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'bulletins' and public.is_admin());
```

Keep the bucket **private** and serve files with signed URLs. A public bucket
bypasses every policy above.

---

## Before you merge

- [ ] RLS enabled on every new table; `FORCE` RLS not used.
- [ ] Every policy names `to authenticated`.
- [ ] `anon` has no grant on any new table.
- [ ] Every read policy gates on `public.is_approved()`.
- [ ] No policy re-queries `profiles` or `group_members` directly.
- [ ] Every `UPDATE` policy has both `using` and `with check`.
- [ ] Add your cases to `back/supabase/tests/` — a member, a leader of another
      group, a pending user, and an anonymous caller must all be denied — and
      `back/scripts/verify-local.sh` still passes.
